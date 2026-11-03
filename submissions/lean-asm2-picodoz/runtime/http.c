/* http.c — HTTP/1.1 framing: request parsing (request line + headers we care
 * about + body by Content-Length) and response writing with keep-alive.
 *
 * Per-connection read buffer: header cap 8 KiB, body cap 20 KiB (spec: bodies
 * over 16 KiB are out of scope). Pipelined bytes stay in the read buffer.
 */
#include "http.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HDR_CAP  (8 * 1024)
#define BODY_CAP (20 * 1024)

static int ci_eq(const char *a, const char *b, size_t n) {
  for (size_t i = 0; i < n; i++) {
    if (tolower((unsigned char)a[i]) != tolower((unsigned char)b[i])) return 0;
  }
  return 1;
}

/* find CRLFCRLF starting at from; returns offset of the byte AFTER it, or -1 */
static long find_head_end(const char *buf, size_t len, size_t from) {
  if (len < 4) return -1;
  for (size_t i = from; i + 3 < len; i++) {
    if (buf[i] == '\r' && buf[i + 1] == '\n' && buf[i + 2] == '\r' && buf[i + 3] == '\n')
      return (long)(i + 4);
  }
  return -1;
}

/* parse one complete request from conn->rbuf[0..rlen).
 * returns: 1 = complete (req filled, *consumed set), 0 = need more, -1 = error/close */
int http_parse_request(struct conn *c, struct AppReq *req, size_t *consumed) {
  size_t len = c->rlen;
  long head_end = find_head_end(c->rbuf, len, 0);
  if (head_end < 0) {
    return (len > HDR_CAP) ? -1 : 0;
  }
  size_t head_len = (size_t)head_end;

  /* request line: METHOD SP TARGET SP VERSION CRLF */
  const char *p = c->rbuf;
  const char *pe = c->rbuf + head_len;
  const char *sp1 = memchr(p, ' ', head_len);
  if (!sp1) return -1;
  size_t method_len = (size_t)(sp1 - p);
  if (method_len == 0 || method_len > 8) return -1;
  int method;
  if (method_len == 3 && memcmp(p, "GET", 3) == 0) method = 0;
  else if (method_len == 4 && memcmp(p, "POST", 4) == 0) method = 1;
  else method = 2;   /* other verbs: routed -> 404 per spec edge decision */

  const char *sp2 = memchr(sp1 + 1, ' ', (size_t)(pe - sp1 - 1));
  if (!sp2) return -1;
  const char *target = sp1 + 1;
  size_t target_len = (size_t)(sp2 - target);
  if (target_len == 0 || target[0] != '/') return -1;

  /* strip query */
  const char *q = memchr(target, '?', target_len);
  size_t path_len = q ? (size_t)(q - target) : target_len;

  /* headers */
  const char *h = sp2;
  const char *auth = NULL;
  size_t auth_len = 0;
  long content_length = 0;
  int conn_close = 0;
  while (h < pe) {
    const char *eol = memchr(h, '\n', (size_t)(pe - h));
    if (!eol) break;
    size_t line_len = (size_t)(eol - h);
    if (line_len && h[line_len - 1] == '\r') line_len--;
    if (line_len == 0) break;   /* end of headers */
    const char *colon = memchr(h, ':', line_len);
    if (colon) {
      size_t name_len = (size_t)(colon - h);
      const char *val = colon + 1;
      size_t val_len = line_len - name_len - 1;
      while (val_len && (*val == ' ' || *val == '\t')) { val++; val_len--; }
      while (val_len && (val[val_len - 1] == ' ' || val[val_len - 1] == '\t')) val_len--;
      if (name_len == 14 && ci_eq(h, "Content-Length", 14))
        content_length = strtol(val, NULL, 10);
      else if (name_len == 13 && ci_eq(h, "Authorization", 13)) {
        auth = val; auth_len = val_len;
      } else if (name_len == 10 && ci_eq(h, "Connection", 10)) {
        if (val_len == 5 && ci_eq(val, "close", 5)) conn_close = 1;
      }
    }
    h = eol + 1;
  }

  if (content_length < 0 || content_length > BODY_CAP) return -1;
  if (len < head_len + (size_t)content_length) {
    /* head fits the cap?  body will too (BODY_CAP covers it) */
    return 0;
  }
  const char *body = c->rbuf + head_len;

  req->method = method;
  req->path = target;
  req->path_len = (int32_t)path_len;
  if (auth) { req->auth = auth; req->auth_len = (int32_t)auth_len; }
  else { req->auth = NULL; req->auth_len = -1; }
  req->body = body;
  req->body_len = (int32_t)content_length;
  *consumed = head_len + (size_t)content_length;
  c->keep_alive = !conn_close;
  return 1;
}

static const char *reason(int status) {
  switch (status) {
  case 200: return "OK";
  case 201: return "Created";
  case 400: return "Bad Request";
  case 401: return "Unauthorized";
  case 404: return "Not Found";
  case 500: return "Internal Server Error";
  case 503: return "Service Unavailable";
  default:  return "OK";
  }
}

/* frame status + body into wbuf; returns bytes to write */
size_t http_frame_response(struct conn *c, int status, const char *body, size_t body_len) {
  size_t need = 128 + body_len;
  if (c->wcap < need) {
    size_t ncap = c->wcap ? c->wcap : 512;
    while (ncap < need) ncap *= 2;
    free(c->wbuf);
    c->wbuf = malloc(ncap);
    c->wcap = ncap;
  }
  int n = snprintf(c->wbuf, c->wcap,
                   "HTTP/1.1 %d %s\r\n"
                   "Content-Type: application/json\r\n"
                   "Content-Length: %zu\r\n"
                   "Connection: %s\r\n"
                   "\r\n",
                   status, reason(status), body_len, c->keep_alive ? "keep-alive" : "close");
  memcpy(c->wbuf + n, body, body_len);
  c->woff = 0;
  c->wlen = (size_t)n + body_len;
  return c->wlen;
}
