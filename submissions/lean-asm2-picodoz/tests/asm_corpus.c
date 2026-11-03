/* asm_corpus.c — differential harness (asm side): run the corpus against the
 * EMITTED asm helpers and print results, one line per case, in the exact
 * format Feed.SpecDump prints for the Lean spec side.
 *
 *   cc -O2 -no-pie -o asmcorpus ../gen/app_gen.s tests/asm_corpus.c \
 *      runtime/abi.c runtime/db.c -lsqlite3...
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

void sha256_asm(unsigned char *out32, unsigned char *buf, uint64_t len);
void hmac_asm(unsigned char *out32, const unsigned char *key, uint64_t keylen,
              const unsigned char *msg, uint64_t msglen);
int64_t b64dec_asm(const char *src, uint64_t len, char *dst, uint64_t cap);
int64_t b64enc_asm(const unsigned char *src, uint64_t len, char *dst);
int json_valid_asm(const char *p, uint64_t len);
int64_t json_unescape_asm(char *dst, uint64_t cap, const char *src, uint64_t len);
int64_t parseid_c_asm(const char *p, uint64_t len, int *ok);
int64_t parseexp_c_asm(const char *p, uint64_t len, int *ok);

static int unhex(const char *s, unsigned char *out, int max) {
  int n = 0;
  while (s[0] && s[1]) {
    if (n >= max) return -1;
    int hi = s[0] <= '9' ? s[0] - '0' : (s[0] | 32) - 'a' + 10;
    int lo = s[1] <= '9' ? s[1] - '0' : (s[1] | 32) - 'a' + 10;
    if (hi < 0 || hi > 15 || lo < 0 || lo > 15) return -1;
    out[n++] = (unsigned char)(hi * 16 + lo);
    s += 2;
  }
  return s[0] ? -1 : n;
}

static void phex(const unsigned char *b, size_t n) {
  for (size_t i = 0; i < n; i++) printf("%02x", b[i]);
}

#define CASE_MAX 8192

int main(int argc, char **argv) {
  FILE *f = argc > 1 ? fopen(argv[1], "r") : stdin;
  if (!f) { perror("open"); return 1; }
  static char line[65536];
  static unsigned char buf1[CASE_MAX], buf2[CASE_MAX], buf3[CASE_MAX];
  static char txt[CASE_MAX * 2];
  static unsigned char scratch[CASE_MAX + 256];
  int idx = 0;
  while (fgets(line, sizeof line, f)) {
    size_t L = strlen(line);
    while (L && (line[L - 1] == '\n' || line[L - 1] == '\r')) line[--L] = 0;
    idx++;
    char kind = line[0];
    char *rest = line + 2;
    if (kind == 'J') {
      int n = unhex(rest, buf1, CASE_MAX);
      if (n < 0) { printf("J%d hexerr\n", idx); continue; }
      /* sha256 pads in place: writable copy */
      memcpy(scratch, buf1, n);
      printf("J%d %s\n", idx, json_valid_asm((const char *)scratch, n) ? "ok" : "bad");
    } else if (kind == 'U') {
      int n = unhex(rest, buf1, CASE_MAX);
      if (n < 0) { printf("U%d hexerr\n", idx); continue; }
      int64_t m = json_unescape_asm((char *)buf2, CASE_MAX, (const char *)buf1, n);
      printf("U%d ", idx);
      if (m < 0) printf("ERR");
      else phex(buf2, m);
      printf("\n");
    } else if (kind == 'B') {
      int n = unhex(rest, buf1, CASE_MAX);
      if (n < 0) { printf("B%d hexerr\n", idx); continue; }
      int64_t e = b64enc_asm(buf1, n, txt);
      int64_t d = b64dec_asm(txt, e, (char *)buf2, CASE_MAX);
      printf("B%d ", idx);
      if (e < 0 || d != n || (n && memcmp(buf1, buf2, n))) printf("MISMATCH");
      else { fwrite(txt, 1, e, stdout); printf(" "); phex(buf2, d); }
      printf("\n");
    } else if (kind == 'S') {
      int n = unhex(rest, buf1, CASE_MAX);
      if (n < 0) { printf("S%d hexerr\n", idx); continue; }
      memcpy(scratch, buf1, n);
      sha256_asm(buf2, scratch, n);
      printf("S%d ", idx);
      phex(buf2, 32);
      printf("\n");
    } else if (kind == 'H') {
      char *sp = strchr(rest, ' ');
      if (!sp) { printf("H%d fmt\n", idx); continue; }
      *sp = 0;
      int nk = unhex(rest, buf1, CASE_MAX);
      int nm = unhex(sp + 1, buf2, CASE_MAX);
      if (nk < 0 || nm < 0) { printf("H%d hexerr\n", idx); continue; }
      hmac_asm(buf3, buf1, nk, buf2, nm);
      printf("H%d ", idx);
      phex(buf3, 32);
      printf("\n");
    } else if (kind == 'I') {
      int ok = 0;
      long long v = parseid_c_asm(rest, strlen(rest), &ok);
      printf("I%d %s%lld\n", idx, ok ? "" : "none", ok ? v : 0);
    } else if (kind == 'E') {
      int ok = 0;
      long long v = parseexp_c_asm(rest, strlen(rest), &ok);
      printf("E%d %s%lld\n", idx, ok ? "" : "bad", ok ? v : 0);
    } else {
      printf("?%d unknown\n", idx);
    }
  }
  return 0;
}
