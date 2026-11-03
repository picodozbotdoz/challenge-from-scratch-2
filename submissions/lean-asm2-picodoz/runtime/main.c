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
#include <sys/resource.h>
#include <unistd.h>
#include <time.h>
#include <sys/time.h>
#include <signal.h>
static volatile sig_atomic_t g_sweep = 0;
static void on_alarm(int sig) { (void)sig; g_sweep = 1; }

#define MAXCONN 16384
#define RBUF_INIT 4096
#define RBUF_MAX  (32 * 1024)

static uring_t ring;
static int listener_fd = -1;

enum { OP_ACCEPT = 1, OP_READ, OP_WRITE, OP_TIMER };
static uint32_t g_tick = 0;
static int ud_op(uint64_t x) { return (int)(x >> 56); }
static int ud_slot(uint64_t x) { return (int)(x & 0xffffff); }
static uint32_t ud_gen(uint64_t x) { return (uint32_t)(x >> 24) & 0xffffffff; }

/* idle sweep: keep-alive idle connections >= IDLE_MAX_TICKS ticks are closed
 * (>= 65 s required; we default to 8 x 10 s = 80 s) */
static int g_tick_secs = 10;
static int g_idle_max_ticks = 8;

static struct conn conns[MAXCONN];   /* slot 0 unused (fd 0 marks free) */
static int free_slots[MAXCONN];
static int free_top = -1;
static uint64_t ud(int op, int slot) {
  return ((uint64_t)op << 56) | ((uint64_t)conns[slot].gen << 24) | (uint32_t)slot;
}

int db_open(const char *path);
void db_close(void);

/* ---- deferred re-arm queue (M11) ------------------------------------------
 * When the SQ is full we must NOT close the conn (drop storm under burst) nor
 * exit (arm_accept did). A conn with a deferred arm has no in-flight op, so no
 * cqe can race it; flush revalidates (fd, closing, flag) before re-arming.
 * flush runs after the final submit of each batch and everything is submitted
 * again before the next wait — a deferred accept can never sit unsubmitted
 * behind a blocking wait. */
struct defer_ent { uint16_t slot; uint8_t op; };
static struct defer_ent g_dq[MAXCONN + 8];
static int g_dq_head, g_dq_tail;                 /* empty: head == tail */
static int g_accept_deferred = 0;
static void arm_accept(void);
static void arm_read(struct conn *c, int slot);
static void arm_write(struct conn *c, int slot);
static int flush_deferred(void);

static void defer_arm(int op, int slot) {
  struct conn *c = &conns[slot];
  if (c->deferred) return;                       /* already queued */
  int next = (g_dq_tail + 1) % (MAXCONN + 8);
  if (next == g_dq_head) { c->closing = 1; return; }   /* cannot happen: one entry per conn */
  c->deferred = 1;
  g_dq[g_dq_tail].slot = (uint16_t)slot;
  g_dq[g_dq_tail].op = (uint8_t)op;
  g_dq_tail = next;
}

static int flush_deferred(void) {
  int armed = 0;
  while (g_dq_head != g_dq_tail) {
    struct defer_ent *e = &g_dq[g_dq_head];
    struct conn *c = &conns[e->slot];
    int op = e->op;
    g_dq_head = (g_dq_head + 1) % (MAXCONN + 8);
    c->deferred = 0;                             /* clear before retry: re-full re-queues */
    if (!c->fd || c->closing) continue;          /* closed while queued (sweep) */
    if (op == OP_READ) { arm_read(c, e->slot); }
    else if (op == OP_WRITE) { arm_write(c, e->slot); }
    else if (op == OP_ACCEPT) { arm_accept(); }
    if (ring.sq_pending >= (int)ring.sq_ring_entries) break;   /* SQ full again: rest next round */
    armed++;
  }
  if (g_accept_deferred && g_dq_head == g_dq_tail) {
    /* accept has no slot; retry it last, once SQ has room */
    g_accept_deferred = 0;
    arm_accept();
    armed++;
  }
  return armed;
}

static void arm_accept(void) {
  struct io_uring_sqe *s = uring_next_sqe(&ring);
  if (!s) { g_accept_deferred = 1; return; }
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
  if (!s) { defer_arm(OP_READ, slot); return; }
  s->opcode = UOP_READ;
  s->fd = c->fd;
  s->addr = (uint64_t)(c->rbuf + c->rlen);
  s->len = (uint32_t)(c->rcap - c->rlen - 1);
  s->user_data = ud(OP_READ, slot);
}

static void arm_write(struct conn *c, int slot) {
  struct io_uring_sqe *s = uring_next_sqe(&ring);
  if (!s) { defer_arm(OP_WRITE, slot); return; }
  s->opcode = UOP_WRITE;
  s->fd = c->fd;
  s->addr = (uint64_t)(c->wbuf + c->woff);
  s->len = (uint32_t)(c->wlen - c->woff);
  s->user_data = ud(OP_WRITE, slot);
}

static void conn_close(struct conn *c) {
  if (c->fd > 0) {
    /* a pending ring read pins the fd: shutdown unblocks it so close reclaims */
    shutdown(c->fd, SHUT_RDWR);
    close(c->fd);
  }
  free(c->rbuf); free(c->wbuf);
  int slot = (int)(c - conns);
  uint32_t gen = c->gen + 1;      /* stale in-flight cqes for this slot */
  memset(c, 0, sizeof *c);
  c->gen = gen;
  free_slots[++free_top] = slot;
}

int main(void) {
  signal(SIGPIPE, SIG_IGN);
  setvbuf(stdout, NULL, _IOLBF, 0);

  /* fd headroom for ~15k connections */
  struct rlimit rl;
  if (getrlimit(RLIMIT_NOFILE, &rl) == 0 && rl.rlim_cur < rl.rlim_max) {
    rl.rlim_cur = rl.rlim_max;
    setrlimit(RLIMIT_NOFILE, &rl);
  }
  {
    const char *ts = getenv("FEED_TICK_SECS");
    const char *mt = getenv("FEED_IDLE_TICKS");
    if (ts) g_tick_secs = atoi(ts);
    if (mt) g_idle_max_ticks = atoi(mt);
  }

  {
    struct sigaction sa = {0};
    sa.sa_handler = on_alarm;
    sigaction(SIGALRM, &sa, NULL);
    struct itimerval it = {0};
    it.it_interval.tv_sec = (time_t)g_tick_secs;
    it.it_value.tv_sec = (time_t)g_tick_secs;
    setitimer(ITIMER_REAL, &it, NULL);
  }

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

  if (uring_open(&ring, 2048) < 0) { perror("io_uring_setup"); return 1; }
  fprintf(stderr, "feed-asm serving %s:%d\n", host, port);

  for (int i = 1; i < MAXCONN; i++) free_slots[++free_top] = i;

  arm_accept();
  uring_submit(&ring);

  for (;;) {
    if (g_sweep) {
      g_sweep = 0;
      g_tick++;
      for (int i = 1; i < MAXCONN; i++) {
        struct conn *c = &conns[i];
        if (c->fd && g_tick - c->last_tick >= (uint32_t)g_idle_max_ticks)
          conn_close(c);
      }
    }
    struct io_uring_cqe cqe;
    {
      int w = uring_wait(&ring, &cqe);
      if (w < 0) { perror("enter"); break; }
      if (w == 1) continue;               /* signal: re-run the sweep check */
    }
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
            c->last_tick = g_tick;
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
        if (!c->fd || c->gen != ud_gen(cqe.user_data)) {
          /* stale cqe for a closed/reused slot: drop */
        } else if (op == OP_READ) {
          c->last_tick = g_tick;
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
          c->last_tick = g_tick;
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
    flush_deferred();                    /* re-arm what SQ-full had deferred */
    if (ring.sq_pending) uring_submit(&ring);   /* everything out before the wait */
  }
  return 0;
}
