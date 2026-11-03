/* sampler.c — minimal ptrace rip-sampling profiler for the prof run.
 * Parent forks CMD, SEIZEs it, interrupts at ~500 Hz, records %rip each sample.
 * Usage: sampler [-T seconds] [-o samples.txt] [-P maps.txt] [-p pidfile] [-S snapdir] -- CMD ARGS...
 * Samples are hex rips, one per line; resolved offline by resolve.py.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/types.h>

static volatile sig_atomic_t g_stop = 0;
static void on_sig(int) { g_stop = 1; }

static uint64_t *g_samples = NULL;
static size_t g_n = 0, g_cap = 0;

static void add_sample(uint64_t rip) {
  if (g_n == g_cap) {
    g_cap = g_cap ? g_cap * 2 : 65536;
    if (g_cap > 8000000) return; /* cap ~8M samples */
    g_samples = realloc(g_samples, g_cap * sizeof(uint64_t));
    if (!g_samples) { perror("realloc"); exit(2); }
  }
  g_samples[g_n++] = rip;
}

static int cp_file(const char *src, const char *dst) {
  FILE *a = fopen(src, "r");
  if (!a) return -1;               /* do NOT truncate dst when src is unreadable */
  FILE *b = fopen(dst, "w");
  if (!b) { fclose(a); return -1; }
  char buf[65536]; size_t r;
  while ((r = fread(buf, 1, sizeof buf, a)) > 0) fwrite(buf, 1, r, b);
  fclose(a); fclose(b); return 0;
}

static long now_ms(void) {
  struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char **argv) {
  double seconds = -1;
  const char *out = "samples.txt", *mapsout = "maps.txt", *pidfile = "pidfile", *snapdir = NULL;
  int i = 1;
  for (; i < argc; i++) {
    if (!strcmp(argv[i], "-T") && i + 1 < argc) seconds = atof(argv[++i]);
    else if (!strcmp(argv[i], "-o") && i + 1 < argc) out = argv[++i];
    else if (!strcmp(argv[i], "-P") && i + 1 < argc) mapsout = argv[++i];
    else if (!strcmp(argv[i], "-p") && i + 1 < argc) pidfile = argv[++i];
    else if (!strcmp(argv[i], "-S") && i + 1 < argc) snapdir = argv[++i];
    else if (!strcmp(argv[i], "--")) { i++; break; }
    else { fprintf(stderr, "bad arg %s\n", argv[i]); return 1; }
  }
  if (i >= argc) { fprintf(stderr, "no command\n"); return 1; }

  signal(SIGINT, on_sig);
  signal(SIGTERM, on_sig);

  pid_t pid = fork();
  if (pid < 0) { perror("fork"); return 2; }
  if (pid == 0) {
    execvp(argv[i], &argv[i]);
    perror("execvp"); _exit(127);
  }

  /* Give the child a moment to exec, then SEIZE it while running.
   * (No raise(SIGSTOP) handshake: a job-control stop of an untraced child
   * leaks into the sampling loop as group-stops that swallow samples.) */
  struct timespec settle = { 0, 20 * 1000 * 1000 }; /* 20 ms */
  nanosleep(&settle, NULL);
  if (ptrace(PTRACE_SEIZE, pid, 0, 0) < 0) {
    if (errno == ESRCH) { fprintf(stderr, "[sampler] child already exited before SEIZE\n"); return 3; }
    perror("PTRACE_SEIZE"); return 2;
  }

  FILE *pf = fopen(pidfile, "w");
  if (pf) { fprintf(pf, "%d\n", pid); fclose(pf); }
  if (snapdir) {
    char src[128], p[512];
    snprintf(src, sizeof src, "/proc/%d/stat", pid);
    snprintf(p, sizeof p, "%s/stat.start", snapdir); cp_file(src, p);
  }
  int st;
  long t0 = now_ms(), last_report = t0;
  long deadline = seconds > 0 ? t0 + (long)(seconds * 1000) : -1;
  long waits = 0;

  while (!g_stop) {
    if (deadline > 0 && now_ms() >= deadline) break;
    if (ptrace(PTRACE_INTERRUPT, pid, 0, 0) < 0) {
      if (errno == ESRCH) break; /* child gone */
      perror("INTERRUPT"); break;
    }
    if (waitpid(pid, &st, 0) < 0) { perror("waitpid"); break; }
    if (WIFEXITED(st) || WIFSIGNALED(st)) break;
    if (WIFSTOPPED(st)) {
      int sig = WSTOPSIG(st);
      if (sig == SIGTRAP) {
        struct user_regs_struct regs;
        if (ptrace(PTRACE_GETREGS, pid, 0, &regs) == 0) add_sample(regs.rip);
        waits = 0;
      } else if (sig == SIGSTOP) {
        /* group-stop under SEIZE: restart without re-injecting SIGSTOP */
        ptrace(PTRACE_CONT, pid, 0, 0);
        struct timespec ts = { 0, 2 * 1000 * 1000 }; nanosleep(&ts, NULL);
        continue;
      } else {
        /* unexpected signal: deliver it and keep going */
        ptrace(PTRACE_CONT, pid, 0, sig);
        struct timespec ts = { 0, 2 * 1000 * 1000 }; nanosleep(&ts, NULL);
        continue;
      }
    }
    ptrace(PTRACE_CONT, pid, 0, 0);
    struct timespec ts = { 0, 2 * 1000 * 1000 }; /* 2 ms -> ~500 Hz */
    nanosleep(&ts, NULL);
    if (now_ms() - last_report > 5000) {
      fprintf(stderr, "[sampler] %lds %zu samples\n", (now_ms() - t0) / 1000, g_n);
      last_report = now_ms();
      /* refresh snapshots while the tracee is definitely alive: maps for
       * module bases (ASLR), stat.end for CPU-time accounting */
      {
        char src[128], dst[512];
        snprintf(src, sizeof src, "/proc/%d/maps", pid);
        snprintf(dst, sizeof dst, "%s", mapsout);
        cp_file(src, dst);
        snprintf(src, sizeof src, "/proc/%d/stat", pid);
        if (snapdir) { snprintf(dst, sizeof dst, "%s/stat.end", snapdir); cp_file(src, dst); }
      }
    }
    (void)waits;
  }

  /* snapshot while still alive */
  char snapmaps[512]; snprintf(snapmaps, sizeof snapmaps, "%s", mapsout);
  {
    char src[128]; snprintf(src, sizeof src, "/proc/%d/maps", pid);
    if (cp_file(src, snapmaps) < 0) perror("maps snapshot");
  }
  if (snapdir) {
    char src[128], p[512];
    snprintf(src, sizeof src, "/proc/%d/stat", pid);
    snprintf(p, sizeof p, "%s/stat.end", snapdir); cp_file(src, p);
  }

  /* final interrupt so we can DETACH cleanly from a running tracee */
  ptrace(PTRACE_INTERRUPT, pid, 0, 0);
  waitpid(pid, &st, 0);
  ptrace(PTRACE_DETACH, pid, 0, 0);

  FILE *f = fopen(out, "w");
  if (!f) { perror("open out"); return 2; }
  for (size_t k = 0; k < g_n; k++) fprintf(f, "%llx\n", (unsigned long long)g_samples[k]);
  fclose(f);
  fprintf(stderr, "[sampler] done: %zu samples in %ld.%03lds -> %s\n",
          g_n, (now_ms() - t0) / 1000, (now_ms() - t0) % 1000, out);
  return 0;
}
