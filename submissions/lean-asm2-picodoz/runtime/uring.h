/* uring.h — minimal raw-syscall io_uring (NO liburing).
 *
 * Single-threaded server event loop:
 *   - one listener fd, re-armed accept
 *   - one read and at most one write in flight per connection
 *   - user_data encodes {op, connection slot}
 *
 * The kernel uapi comes from the system header — no struct layout is hand-rolled.
 */
#ifndef FEED_URING_H
#define FEED_URING_H

#include <stdint.h>
#include <linux/io_uring.h>

/* opcodes we use (from the header's enum, pinned for readability) */
#define UOP_TIMEOUT IORING_OP_TIMEOUT
#define UOP_ACCEPT  IORING_OP_ACCEPT
#define UOP_CLOSE   IORING_OP_CLOSE
#define UOP_READ    IORING_OP_READ
#define UOP_WRITE   IORING_OP_WRITE

typedef struct {
  int fd;
  uint32_t *sq_head, *sq_tail, *sq_mask, *sq_flags, *sq_dropped, *sq_array;
  struct io_uring_sqe *sqes;
  uint32_t sq_ring_entries;
  uint32_t *cq_head, *cq_tail, *cq_mask, *cq_overflow;
  struct io_uring_cqe *cqes;
  uint32_t cq_ring_entries;
  uint32_t sq_pending;
} uring_t;

int  uring_open(uring_t *u, uint32_t entries);
/* non-blocking: 0 on success, -EAGAIN when empty */
int  uring_get_cqe(uring_t *u, struct io_uring_cqe *out);
/* blocking wait for one completion */
int  uring_wait(uring_t *u, struct io_uring_cqe *out);
/* raw sqe slot; caller fills it, then calls uring_submit */
struct io_uring_sqe *uring_next_sqe(uring_t *u);
int  uring_submit(uring_t *u);
void uring_cq_advance(uring_t *u, uint32_t n);

#endif
