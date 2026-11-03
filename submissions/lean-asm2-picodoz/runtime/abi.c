/* abi.c — x_* wrapper implementations (out-buffer, env, time, fail). */
#include "abi.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern int64_t g_start_sec;   /* db.c owns it */

static void grow(struct OutBuf *o, uint64_t need) {
  if (o->len + need <= o->cap) return;
  uint64_t ncap = o->cap ? o->cap * 2 : 256;
  while (ncap < o->len + need) ncap *= 2;
  char *nb = realloc(o->base, ncap);
  if (!nb) { perror("outbuf grow"); abort(); }
  o->base = nb;
  o->cap = ncap;
}

void x_out_byte(struct OutBuf *o, int c) {
  grow(o, 1);
  o->base[o->len++] = (char)c;
}

void x_out_mem(struct OutBuf *o, const char *p, int64_t len) {
  if (len <= 0) return;
  grow(o, (uint64_t)len);
  memcpy(o->base + o->len, p, (size_t)len);
  o->len += (uint64_t)len;
}

void x_out_str(struct OutBuf *o, const char *p, int64_t len) { x_out_mem(o, p, len); }

void x_out_int(struct OutBuf *o, int64_t v) {
  char tmp[24];
  int n = snprintf(tmp, sizeof tmp, "%lld", (long long)v);
  x_out_mem(o, tmp, n);
}

/* JSON string escaping, exactly the spec serializer's contract:
   " \ and the C0 controls escaped (\b \f \n \r \t, else \u00xx); every other
   byte — including UTF-8 payload — passes through verbatim. */
void x_out_json_escaped_str(struct OutBuf *o, const char *p, int64_t len) {
  for (int64_t i = 0; i < len; i++) {
    unsigned char c = (unsigned char)p[i];
    switch (c) {
    case '"':  x_out_mem(o, "\\\"", 2); break;
    case '\\': x_out_mem(o, "\\\\", 2); break;
    case '\n': x_out_mem(o, "\\n", 2); break;
    case '\r': x_out_mem(o, "\\r", 2); break;
    case '\t': x_out_mem(o, "\\t", 2); break;
    case 0x08: x_out_mem(o, "\\b", 2); break;
    case 0x0c: x_out_mem(o, "\\f", 2); break;
    default:
      if (c < 0x20) {
        char tmp[6] = {'\\', 'u', '0', '0', "0123456789abcdef"[c >> 4],
                       "0123456789abcdef"[c & 15]};
        x_out_mem(o, tmp, 6);
      } else {
        x_out_byte(o, c);
      }
    }
  }
}

const char *x_env_secret(int64_t *len_out) {
  const char *s = getenv("JWT_SECRET");
  if (!s) s = "";
  *len_out = (int64_t)strlen(s);
  return s;
}

int64_t x_now(void) { return (int64_t)time(NULL); }

int64_t x_uptime(void) { return (int64_t)time(NULL) - g_start_sec; }

int x_fail(struct OutBuf *o) {
  o->len = 0;
  x_out_mem(o, "{\"error\":\"internal server error\"}", 32);
  return 500;
}
