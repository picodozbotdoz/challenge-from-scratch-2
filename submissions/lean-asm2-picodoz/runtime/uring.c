/* uring.c — raw-syscall io_uring setup + submit/complete. No liburing. */
#include "uring.h"

#include <errno.h>
#include <string.h>
#include <stddef.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stdio.h>

_Static_assert(sizeof(struct io_uring_sqe) == 64, "sqe size");
_Static_assert(sizeof(struct io_uring_cqe) == 16, "cqe size");
_Static_assert(offsetof(struct io_uring_sqe, opcode) == 0, "sqe.opcode");
_Static_assert(offsetof(struct io_uring_sqe, fd) == 4, "sqe.fd");
_Static_assert(offsetof(struct io_uring_sqe, off) == 8, "sqe.off");
_Static_assert(offsetof(struct io_uring_sqe, addr) == 16, "sqe.addr");
_Static_assert(offsetof(struct io_uring_sqe, len) == 24, "sqe.len");
_Static_assert(offsetof(struct io_uring_sqe, rw_flags) == 28, "sqe.rw_flags");
_Static_assert(offsetof(struct io_uring_sqe, user_data) == 32, "sqe.user_data");
_Static_assert(offsetof(struct io_sqring_offsets, array) == 24, "sqring.array");

static int sys_io_uring_setup(uint32_t entries, struct io_uring_params *p) {
  return (int)syscall(425, entries, p);
}
static int sys_io_uring_enter(int fd, uint32_t to_submit, uint32_t min_complete,
                              uint32_t flags) {
  return (int)syscall(426, fd, to_submit, min_complete, flags, NULL, 0);
}

int uring_open(uring_t *u, uint32_t entries) {
  memset(u, 0, sizeof *u);
  struct io_uring_params p;
  memset(&p, 0, sizeof p);
  int fd = sys_io_uring_setup(entries, &p);
  if (fd < 0) return -1;

  /* the *_off.ring_entries fields are OFFSETS of count fields inside the rings;
   * the counts to size the mappings come from params.sq_entries / cq_entries. */
  size_t sq_ring_sz = (size_t)p.sq_off.array + p.sq_entries * sizeof(uint32_t);
  size_t cq_ring_sz = (size_t)p.cq_off.cqes + p.cq_entries * sizeof(struct io_uring_cqe);

  /* IORING_FEAT_SINGLE_MMAP (present since 5.5): SQ and CQ can share one mapping
   * of max(sq, cq) size — we still map both for simplicity; both must succeed. */
  void *sq_ring = mmap(NULL, sq_ring_sz, PROT_READ | PROT_WRITE,
                       MAP_SHARED | MAP_POPULATE, fd, IORING_OFF_SQ_RING);
  if (sq_ring == MAP_FAILED) { perror("mmap sq"); return -1; }
  void *cq_ring = mmap(NULL, cq_ring_sz, PROT_READ | PROT_WRITE,
                       MAP_SHARED | MAP_POPULATE, fd, IORING_OFF_CQ_RING);
  if (cq_ring == MAP_FAILED) { perror("mmap cq"); return -1; }
  void *sqes = mmap(NULL, (size_t)p.sq_entries * sizeof(struct io_uring_sqe),
                    PROT_READ | PROT_WRITE, MAP_SHARED | MAP_POPULATE, fd, IORING_OFF_SQES);
  if (sqes == MAP_FAILED) { perror("mmap sqes"); return -1; }

  u->fd = fd;
  u->sq_head = (uint32_t *)((char *)sq_ring + p.sq_off.head);
  u->sq_tail = (uint32_t *)((char *)sq_ring + p.sq_off.tail);
  u->sq_mask = (uint32_t *)((char *)sq_ring + p.sq_off.ring_mask);
  u->sq_flags = (uint32_t *)((char *)sq_ring + p.sq_off.flags);
  u->sq_dropped = (uint32_t *)((char *)sq_ring + p.sq_off.dropped);
  u->sq_array = (uint32_t *)((char *)sq_ring + p.sq_off.array);
  u->sqes = (struct io_uring_sqe *)sqes;
  u->sq_ring_entries = *(uint32_t *)((char *)sq_ring + p.sq_off.ring_entries);

  u->cq_head = (uint32_t *)((char *)cq_ring + p.cq_off.head);
  u->cq_tail = (uint32_t *)((char *)cq_ring + p.cq_off.tail);
  u->cq_mask = (uint32_t *)((char *)cq_ring + p.cq_off.ring_mask);
  u->cq_overflow = (uint32_t *)((char *)cq_ring + p.cq_off.overflow);
  u->cqes = (struct io_uring_cqe *)((char *)cq_ring + p.cq_off.cqes);
  u->cq_ring_entries = *(uint32_t *)((char *)cq_ring + p.cq_off.ring_entries);
  return 0;
}

struct io_uring_sqe *uring_next_sqe(uring_t *u) {
  uint32_t tail = __atomic_load_n(u->sq_tail, __ATOMIC_ACQUIRE);
  uint32_t head = __atomic_load_n(u->sq_head, __ATOMIC_ACQUIRE);
  if (tail - head >= u->sq_ring_entries) return NULL;   /* full */
  uint32_t idx = tail & *u->sq_mask;
  u->sq_array[idx] = idx;
  struct io_uring_sqe *sqe = &u->sqes[idx];
  memset(sqe, 0, sizeof *sqe);
  __atomic_store_n(u->sq_tail, tail + 1, __ATOMIC_RELEASE);
  u->sq_pending++;
  return sqe;
}

int uring_submit(uring_t *u) {
  if (u->sq_pending == 0) return 0;
  int n = sys_io_uring_enter(u->fd, u->sq_pending, 0, 0);
  if (n < 0) return -1;
  u->sq_pending = 0;
  return n;
}

/* non-blocking: 0 on success, -EAGAIN when the queue is empty */
int uring_get_cqe(uring_t *u, struct io_uring_cqe *out) {
  uint32_t head = __atomic_load_n(u->cq_head, __ATOMIC_ACQUIRE);
  uint32_t tail = __atomic_load_n(u->cq_tail, __ATOMIC_ACQUIRE);
  if (head == tail) return -EAGAIN;
  *out = u->cqes[head & *u->cq_mask];
  uring_cq_advance(u, 1);
  return 0;
}

/* blocking wait for one completion */
int uring_wait(uring_t *u, struct io_uring_cqe *out) {
  for (;;) {
    if (uring_get_cqe(u, out) == 0) return 0;
    int n = sys_io_uring_enter(u->fd, 0, 1, IORING_ENTER_GETEVENTS);
    if (n < 0 && errno != EINTR && errno != EAGAIN) return -1;
  }
}

void uring_cq_advance(uring_t *u, uint32_t n) {
  uint32_t head = __atomic_load_n(u->cq_head, __ATOMIC_ACQUIRE);
  __atomic_store_n(u->cq_head, head + n, __ATOMIC_RELEASE);
}
