#ifndef FEED_HTTP_H
#define FEED_HTTP_H

#include "abi.h"
#include <stddef.h>
#include <stdint.h>

struct conn {
  int fd;
  uint32_t gen;       /* stale-cqe guard (bumped on close/reuse) */
  uint32_t last_tick; /* idle sweep stamp */
  char *rbuf;         /* request bytes */
  size_t rlen, rcap;
  char *wbuf;         /* pending response bytes */
  size_t wlen, woff, wcap;
  int keep_alive;
  int closing;        /* close after flush */
};

int http_parse_request(struct conn *c, struct AppReq *req, size_t *consumed);
size_t http_frame_response(struct conn *c, int status, const char *body, size_t body_len);

#endif
