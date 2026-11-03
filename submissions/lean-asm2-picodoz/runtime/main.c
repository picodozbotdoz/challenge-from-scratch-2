/* main.c — server bootstrap + the single-threaded io_uring event loop.
 *
 * env: SQLITE_PATH, JWT_SECRET, HOST, PORT (nothing else).
 * The application layer (routing/JSON/JWT/SQL selection) lives in the emitted
 * asm (gen/app_gen.s): C only transports, frames, and wraps SQLite.
 */
#include "uring.h"
#include "http.h"

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#define MAXCONN 16384
#define RBUF_INIT 4096
#define RBUF_MAX  (32 * 1024)

static uring_t ring;
static int listener_fd = -1;

enum { OP_ACCEPT = 1, OP_READ, OP_WRITE };
static uint64_t ud(int op, int slot) { return ((uint64_t)op << 56) | (uint32_t)slot; }
static int ud_op(uint64_t x) { return (int)(x >> 56); }
static int ud_slot(uint64_t x) { return (int)(x & 0xffffffff); }

static struct conn conns[MAXCONN];   /* slot 0 unused (fd 0 marks free) */
static int free_slots[MAXCONN];
static int free_top = -1;

int db_open(const char *path);
void db_close(void);

static void arm_accept(void) {
  struct io_uring_sqe *s = uring_next_sqe(&ring);
  if (!s) { fprintf(stderr, "sq full\n"); exit(1); }
  s->opcode = UOP_ACCEPT;
  s->fd = listener_fd;
  s->rw_flags = SOCK_NONBLOCK | SOCK_CLOEXEC;
  s->user_data = ud(OP_ACCEPT, 0);
}

static void arm_read(struct conn *c, int slot) {
  if (c->rlen + 1 >= c->rcap) {
    if (c->rcap >= RBUF_MAX) { c->closing = 1; return; }
    size_t ncap = c->rcap * 2;
    char *nb = realloc(c->rbuf, ncap);
    if (!nb) { c->closing = 1; return; }
    c->rbuf = nb; c->rcap = ncap;
  }
  struct io_uring_sqe *s = uring_next_sqe(&ring);
  if (!s) { c->closing = 1; return; }
  s->opcode = UOP_READ;
  s->fd = c->fd;
  s->addr = (uint64_t)(c->rbuf + c->rlen);
  s->len = (uint32_t)(c->rcap - c->rlen - 1);
  s->user_data = ud(OP_READ, slot);
}

static void arm_write(struct conn *c, int slot) {
  struct io_uring_sqe *s = uring_next_sqe(&ring);
  if (!s) { c->closing = 1; return; }
  s->opcode = UOP_WRITE;
  s->fd = c->fd;
  s->addr = (uint64_t)(c->wbuf + c->woff);
  s->len = (uint32_t)(c->wlen - c->woff);
  s->user_data = ud(OP_WRITE, slot);
}

static void conn_close(struct conn *c) {
  if (c->fd > 0) close(c->fd);
  free(c->rbuf); free(c->wbuf);
  int slot = (int)(c - conns);
  memset(c, 0, sizeof *c);
  free_slots[++free_top] = slot;
}

int main(void) {
  signal(SIGPIPE, SIG_IGN);
  setvbuf(stdout, NULL, _IOLBF, 0);

  const char *db_path = getenv("SQLITE_PATH");
  const char *host = getenv("HOST");
  const char *port_s = getenv("PORT");
  if (!db_path || !port_s) {
    fprintf(stderr, "need SQLITE_PATH and PORT env\n");
    return 1;
  }
  int port = atoi(port_s);
  if (!host) host = "127.0.0.1";

  if (db_open(db_path) != 0) {
    fprintf(stderr, "cannot open db %s\n", db_path);
    return 1;
  }
  if (app_init() != 0) {
    fprintf(stderr, "app_init failed\n");
    return 1;
  }

  listener_fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC, 0);
  if (listener_fd < 0) { perror("socket"); return 1; }
  int one = 1;
  setsockopt(listener_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {0};
  a.sin_family = AF_INET;
  a.sin_port = htons((uint16_t)port);
  if (inet_pton(AF_INET, host, &a.sin_addr) != 1) { fprintf(stderr, "bad HOST\n"); return 1; }
  if (bind(listener_fd, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind"); return 1; }
  if (listen(listener_fd, 1024) < 0) { perror("listen"); return 1; }

  if (uring_open(&ring, 1024) < 0) { perror("io_uring_setup"); return 1; }
  fprintf(stderr, "feed-asm serving %s:%d\n", host, port);

  for (int i = 1; i < MAXCONN; i++) free_slots[++free_top] = i;

  arm_accept();
  uring_submit(&ring);

  for (;;) {
    struct io_uring_cqe cqe;
    if (uring_wait(&ring, &cqe) < 0) { perror("enter"); break; }
    int budget = 64;   /* process a batch without blocking on enter */
    for (;;) {
      int op = ud_op(cqe.user_data), slot = ud_slot(cqe.user_data);
      if (op == OP_ACCEPT) {
        if (cqe.res >= 0) {
          if (free_top >= 0) {
            struct conn *c = &conns[free_slots[free_top--]];
            memset(c, 0, sizeof *c);
            c->fd = cqe.res;
            c->keep_alive = 1;
            c->rbuf = malloc(RBUF_INIT);
            c->rcap = RBUF_INIT;
            int nd = 1; setsockopt(c->fd, IPPROTO_TCP, TCP_NODELAY, &nd, sizeof nd);
            arm_read(c, (int)(c - conns));
          } else {
            close(cqe.res);   /* out of slots */
          }
        }
        arm_accept();
      } else {
        struct conn *c = &conns[slot];
        if (op == OP_READ) {
          if (cqe.res <= 0) {
            conn_close(c);
          } else {
            c->rlen += (size_t)cqe.res;
            c->rbuf[c->rlen] = 0;
            /* parse+serve as many pipelined requests as are complete */
            int served = 0;
            int need_more = 0;
            while (!c->closing) {
              struct AppReq req;
              size_t consumed = 0;
              int prc = http_parse_request(c, &req, &consumed);
              if (prc == 0) { need_more = 1; break; }
              if (prc < 0) {
                const char *bad = "{\"error\":\"not found\"}";
                c->keep_alive = 0;
                http_frame_response(c, 404, bad, strlen(bad));
                c->rlen = 0;
                break;
              }
              struct OutBuf out = {0};
              int status = app_request(&req, &out);
              http_frame_response(c, status, out.base ? out.base : "", out.len);
              free(out.base);
              c->rlen -= consumed;
              if (c->rlen > 0) memmove(c->rbuf, c->rbuf + consumed, c->rlen);
              if (++served >= 16) break;   /* fairness */
            }
            if (c->closing) { conn_close(c); }
            else if (served > 0) { arm_write(c, slot); }   /* flush framed response */
            else if (need_more) { arm_read(c, slot); }     /* request still partial */
            else arm_write(c, slot);
          }
        } else if (op == OP_WRITE) {
          if (cqe.res < 0) {
            conn_close(c);
          } else {
            c->woff += (size_t)cqe.res;
            if (c->woff >= c->wlen) {
              if (!c->keep_alive) { conn_close(c); }
              else arm_read(c, slot);
            } else {
              arm_write(c, slot);   /* short write: continue */
            }
          }
        }
      }
      if (--budget <= 0) uring_submit(&ring);
      if (uring_get_cqe(&ring, &cqe) < 0) break;
    }
    uring_submit(&ring);
  }
  return 0;
}
