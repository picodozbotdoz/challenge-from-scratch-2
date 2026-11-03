/* echo_main.c — M2 bring-up harness: prove the raw io_uring loop before the HTTP
 * layer exists. Echoes bytes back on every connection. NOT part of the server
 * build (dev tool only).
 *
 *   cc -O2 -o /tmp/echo echo_main.c uring.c && /tmp/echo 3458
 */
#include "uring.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define MAXCONN 64
#define BUFSZ   4096

enum { OP_ACCEPT = 1, OP_READ, OP_WRITE };

/* user_data: op in the top byte, slot in the low bits */
static uint64_t ud(int op, int slot) { return ((uint64_t)op << 56) | (uint32_t)slot; }
static int ud_op(uint64_t x) { return (int)(x >> 56); }
static int ud_slot(uint64_t x) { return (int)(x & 0xffffffff); }

static int conns[MAXCONN];
static char bufs[MAXCONN][BUFSZ];

static void arm_accept(uring_t *u, int lfd) {
  struct io_uring_sqe *s = uring_next_sqe(u);
  if (!s) { fprintf(stderr, "sq full\n"); exit(1); }
  s->opcode = IORING_OP_ACCEPT;
  s->fd = lfd;
  s->off = 0; s->addr = 0;   /* sockaddr*: none wanted */
  s->rw_flags = SOCK_NONBLOCK | SOCK_CLOEXEC;
  s->user_data = ud(OP_ACCEPT, 0);
}

static void arm_read(uring_t *u, int slot) {
  struct io_uring_sqe *s = uring_next_sqe(u);
  if (!s) { fprintf(stderr, "sq full\n"); exit(1); }
  s->opcode = IORING_OP_READ;
  s->fd = conns[slot];
  s->addr = (uint64_t)bufs[slot];
  s->len = BUFSZ;
  s->user_data = ud(OP_READ, slot);
}

static void arm_write(uring_t *u, int slot, int len) {
  struct io_uring_sqe *s = uring_next_sqe(u);
  if (!s) { fprintf(stderr, "sq full\n"); exit(1); }
  s->opcode = IORING_OP_WRITE;
  s->fd = conns[slot];
  s->addr = (uint64_t)bufs[slot];
  s->len = len;
  s->user_data = ud(OP_WRITE, slot);
}

int main(int argc, char **argv) {
  int port = argc > 1 ? atoi(argv[1]) : 3458;
  int lfd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
  if (lfd < 0) { perror("socket"); return 1; }
  int one = 1;
  setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {0};
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl(INADDR_ANY);
  a.sin_port = htons((uint16_t)port);
  if (bind(lfd, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind"); return 1; }
  if (listen(lfd, 512) < 0) { perror("listen"); return 1; }

  uring_t u;
  if (uring_open(&u, 256) < 0) { perror("io_uring_setup"); return 1; }
  fprintf(stderr, "echo: listening on %d (io_uring fd %d)\n", port, u.fd);

  arm_accept(&u, lfd);
  uring_submit(&u);

  for (;;) {
    struct io_uring_cqe cqe;
    if (uring_wait(&u, &cqe) < 0) { perror("enter"); return 1; }
    int op = ud_op(cqe.user_data), slot = ud_slot(cqe.user_data);
    if (op == OP_ACCEPT) {
      if (cqe.res >= 0) {
        int cfd = cqe.res;
        int i;
        for (i = 0; i < MAXCONN && conns[i]; i++) {}
        if (i == MAXCONN) { close(cfd); }
        else {
          conns[i] = cfd;
          int nd = 1; setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &nd, sizeof nd);
          arm_read(&u, i);
        }
      }
      arm_accept(&u, lfd);   /* re-arm */
    } else if (op == OP_READ) {
      if (cqe.res <= 0) {
        close(conns[slot]); conns[slot] = 0;
      } else {
        arm_write(&u, slot, cqe.res);
      }
    } else if (op == OP_WRITE) {
      if (cqe.res < 0) { close(conns[slot]); conns[slot] = 0; }
      else arm_read(&u, slot);
    }
    /* drain anything else ready before blocking again */
    while (uring_get_cqe(&u, &cqe) == 0) {
      op = ud_op(cqe.user_data); slot = ud_slot(cqe.user_data);
      if (op == OP_READ) {
        if (cqe.res <= 0) { close(conns[slot]); conns[slot] = 0; }
        else arm_write(&u, slot, cqe.res);
      } else if (op == OP_WRITE) {
        if (cqe.res < 0) { close(conns[slot]); conns[slot] = 0; }
        else arm_read(&u, slot);
      }
    }
    uring_submit(&u);
  }
}
