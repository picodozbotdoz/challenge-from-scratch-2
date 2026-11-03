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
  /* manual decimal: snprintf cost dominated this call on the hot path */
  char tmp[24];
  int n = 0;
  uint64_t u = (v < 0) ? (uint64_t)(-(v + 1)) + 1 : (uint64_t)v;
  do { tmp[23 - n++] = (char)('0' + (u % 10)); u /= 10; } while (u);
  if (v < 0) tmp[23 - n++] = '-';
  x_out_mem(o, tmp + 24 - n, n);
}

/* JSON string escaping, exactly the spec serializer's contract:
   " \ and the C0 controls escaped (\b \f \n \r \t, else \u00xx); every other
   byte — including UTF-8 payload — passes through verbatim.
   Fast path (M12): bulk-copy the run of plain bytes with one memcpy, only
   dropping to the per-byte switch on ", \ or a control byte. */
void x_out_json_escaped_str(struct OutBuf *o, const char *p, int64_t len) {
  int64_t i = 0;
  while (i < len) {
    int64_t j = i;
    while (j < len) {
      unsigned char c = (unsigned char)p[j];
      if (c < 0x20 || c == '"' || c == '\\') break;
      j++;
    }
    if (j > i) {
      grow(o, (uint64_t)(j - i));
      memcpy(o->base + o->len, p + i, (size_t)(j - i));
      o->len += (uint64_t)(j - i);
      i = j;
    }
    if (i >= len) break;
    unsigned char c = (unsigned char)p[i];
    grow(o, 6);                              /* worst case: \u00xx */
    char *d = o->base + o->len;
    switch (c) {
    case '"':  *d++ = '\\'; *d++ = '"';  o->len += 2; break;
    case '\\': *d++ = '\\'; *d++ = '\\'; o->len += 2; break;
    case '\n': *d++ = '\\'; *d++ = 'n';  o->len += 2; break;
    case '\r': *d++ = '\\'; *d++ = 'r';  o->len += 2; break;
    case '\t': *d++ = '\\'; *d++ = 't';  o->len += 2; break;
    case 0x08: *d++ = '\\'; *d++ = 'b';  o->len += 2; break;
    case 0x0c: *d++ = '\\'; *d++ = 'f';  o->len += 2; break;
    default:   /* c < 0x20 */
      *d++ = '\\'; *d++ = 'u'; *d++ = '0'; *d++ = '0';
      *d++ = "0123456789abcdef"[c >> 4];
      *d++ = "0123456789abcdef"[c & 15];
      o->len += 6;
      break;
    }
    i++;
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
