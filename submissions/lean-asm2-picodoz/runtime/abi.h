/* abi.h — the C↔asm interface.
 *
 * RULES (do not break):
 *  - C calls ONLY `app_init` / `app_request`.
 *  - Emitted asm calls ONLY the `x_*` wrappers below (SysV AMD64).
 *  - Struct layouts are OWNED by the Lean emitter (`.set` equates at the top of
 *    gen/app_gen.s). This header's _Static_asserts PIN those same numbers —
 *    never hand-duplicate offsets anywhere else in C.
 *
 * The assert numbers below must match the equates emitted by spec/EmitAsm.lean.
 * If the emitter's layout changes, change these pins in the same commit (the
 * build fails loudly on drift).
 */
#ifndef FEED_ABI_H
#define FEED_ABI_H

#include <stdint.h>
#include <stddef.h>

/* ---- AppReq: one parsed request, filled by the HTTP layer, read by asm ---- */
struct AppReq {
  int32_t  method;      /* 0 = GET, 1 = POST                          */
  int32_t  path_len;
  const char *path;     /* query-stripped target                      */
  int32_t  auth_len;    /* -1 = no Authorization header               */
  const char *auth;
  int32_t  body_len;
  const char *body;
};

/* ---- OutBuf: response body accumulator, grown by the x_out_* wrappers ---- */
struct OutBuf {
  char    *base;
  uint64_t len;
  uint64_t cap;
};

/* pins — MUST equal the `.set APPREQ_*` / `.set OUTBUF_*` equates in gen/app_gen.s */
#define APPREQ_METHOD_OFF   0
#define APPREQ_PATH_LEN_OFF 4
#define APPREQ_PATH_OFF     8
#define APPREQ_AUTH_LEN_OFF 16
#define APPREQ_AUTH_OFF     24
#define APPREQ_BODY_LEN_OFF 32
#define APPREQ_BODY_OFF     40
#define OUTBUF_BASE_OFF     0
#define OUTBUF_LEN_OFF      8
#define OUTBUF_CAP_OFF      16

_Static_assert(offsetof(struct AppReq, method)   == APPREQ_METHOD_OFF,   "AppReq.method");
_Static_assert(offsetof(struct AppReq, path_len) == APPREQ_PATH_LEN_OFF, "AppReq.path_len");
_Static_assert(offsetof(struct AppReq, path)     == APPREQ_PATH_OFF,     "AppReq.path");
_Static_assert(offsetof(struct AppReq, auth_len) == APPREQ_AUTH_LEN_OFF, "AppReq.auth_len");
_Static_assert(offsetof(struct AppReq, auth)     == APPREQ_AUTH_OFF,     "AppReq.auth");
_Static_assert(offsetof(struct AppReq, body_len) == APPREQ_BODY_LEN_OFF, "AppReq.body_len");
_Static_assert(offsetof(struct AppReq, body)     == APPREQ_BODY_OFF,     "AppReq.body");
_Static_assert(sizeof(struct AppReq) == 48, "AppReq size");
_Static_assert(offsetof(struct OutBuf, base) == OUTBUF_BASE_OFF, "OutBuf.base");
_Static_assert(offsetof(struct OutBuf, len)  == OUTBUF_LEN_OFF,  "OutBuf.len");
_Static_assert(offsetof(struct OutBuf, cap)  == OUTBUF_CAP_OFF,  "OutBuf.cap");
_Static_assert(sizeof(struct OutBuf) == 24, "OutBuf size");

/* ---- implemented in asm (gen/app_gen.s), called only from main.c ---- */
int app_init(void);
/* returns the HTTP status code; writes the response body into `out` */
int app_request(struct AppReq *req, struct OutBuf *out);

/* ---- x_* wrappers implemented in C, called only from emitted asm ---- */

/* out-buffer appends (OutBuf grows as needed) */
void x_out_byte(struct OutBuf *o, int c);
void x_out_mem(struct OutBuf *o, const char *p, int64_t len);
void x_out_int(struct OutBuf *o, int64_t v);                  /* decimal */
void x_out_str(struct OutBuf *o, const char *p, int64_t len); /* raw */
void x_out_json_escaped_str(struct OutBuf *o, const char *p, int64_t len);

/* db: prepared-statement cache keyed by SQL text (reuse is allowed) */
int64_t x_db_prepare(const char *sql, int64_t len);           /* stmt id, 0 = error */
int     x_db_bind_int(int64_t stmt, int32_t idx, int64_t v);
int     x_db_bind_text(int64_t stmt, int32_t idx, const char *p, int64_t len);
int     x_db_step(int64_t stmt);                              /* 1=row 0=done -1=err */
int64_t x_db_column_int(int64_t stmt, int32_t idx);
const char *x_db_column_text(int64_t stmt, int32_t idx);      /* till next step/reset */
int64_t x_db_column_bytes(int64_t stmt, int32_t idx);
int64_t x_db_changes(void);
int     x_db_reset(int64_t stmt);
const char *x_db_errmsg(void);                                /* NUL-terminated */

/* environment / time */
const char *x_env_secret(int64_t *len_out);                   /* JWT_SECRET bytes */
int64_t x_now(void);                                          /* unix seconds */
int64_t x_uptime(void);                                       /* seconds since start */

/* mark the response as 500 internal server error (body reset to the error body) */
int x_fail(struct OutBuf *o);

#endif
