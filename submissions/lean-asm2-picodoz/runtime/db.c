/* db.c — SQLite glue: open with the challenge pragmas, prepared-statement cache,
 * and the x_db_* wrappers the emitted asm calls. */
#include "abi.h"

#include <sqlite3.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

sqlite3 *g_db = NULL;
int64_t g_start_sec = 0;

/* ---- checkpoint worker (M10) ----------------------------------------------
 * Inline wal_autocheckpoint fdatasyncs the main db ON THE EVENT LOOP inside
 * sqlite3_step (measured: median 7.45ms, max 106ms per sync, every ~2.4s under
 * load — and rare jbd2 stalls froze all connections for 4-8s). Fix: the writer
 * runs with wal_autocheckpoint=0 (synchronous=NORMAL => WAL commits never
 * sync), and this worker's own connection runs periodic PASSIVE checkpoints,
 * absorbing every main-db fdatasync. PASSIVE never blocks readers/writers. */
static pthread_t g_ckpt_thread;
static volatile int g_ckpt_run = 0;
static sqlite3 *g_ckpt_db = NULL;

static void *ckpt_main(void *arg) {
  (void)arg;
  while (g_ckpt_run) {
    struct timespec ts = { 0, 200 * 1000 * 1000 };   /* 200 ms */
    nanosleep(&ts, NULL);
    if (g_ckpt_db)
      (void)sqlite3_wal_checkpoint_v2(g_ckpt_db, NULL, SQLITE_CHECKPOINT_PASSIVE, NULL, NULL);
  }
  return NULL;
}

static int ckpt_start(const char *path) {
  char *err = NULL;
  if (sqlite3_open_v2(path, &g_ckpt_db, SQLITE_OPEN_READWRITE, NULL) != SQLITE_OK)
    goto fail;
  (void)sqlite3_exec(g_ckpt_db, "PRAGMA journal_mode=WAL;", NULL, NULL, &err);
  if (err) { sqlite3_free(err); err = NULL; }
  sqlite3_busy_timeout(g_ckpt_db, 100);            /* give up fast, retry next tick */
  (void)sqlite3_exec(g_ckpt_db, "PRAGMA cache_size=-2000;", NULL, NULL, &err);
  if (err) { sqlite3_free(err); err = NULL; }
  g_ckpt_run = 1;
  if (pthread_create(&g_ckpt_thread, NULL, ckpt_main, NULL) != 0) {
    g_ckpt_run = 0;
    goto fail;
  }
  return 0;
fail:
  if (g_ckpt_db) { sqlite3_close(g_ckpt_db); g_ckpt_db = NULL; }
  return -1;
}

/* prepared-statement cache: keyed by SQL text (prepared-statement reuse is
 * explicitly allowed by the rules — they cache the plan, not the data) */
#define STMT_CACHE_MAX 32
struct stmt_entry {
  char *sql;
  sqlite3_stmt *stmt;
};
static struct stmt_entry g_stmts[STMT_CACHE_MAX];
static int g_stmt_count = 0;

static sqlite3_stmt *stmt_lookup(const char *sql, int64_t len) {
  for (int i = 0; i < g_stmt_count; i++) {
    if ((int64_t)strlen(g_stmts[i].sql) == len && memcmp(g_stmts[i].sql, sql, len) == 0)
      return g_stmts[i].stmt;
  }
  return NULL;
}

int db_open(const char *path) {
  if (sqlite3_open_v2(path, &g_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) != SQLITE_OK)
    return -1;
  sqlite3_busy_timeout(g_db, 2000);
  /* rules: WAL + synchronous=NORMAL or stronger; no caching of data across
   * requests (page cache/mmap are the database itself — allowed) */
  char *err = NULL;
  (void)sqlite3_exec(g_db, "PRAGMA journal_mode=WAL;", NULL, NULL, &err);
  (void)sqlite3_exec(g_db, "PRAGMA synchronous=NORMAL;", NULL, NULL, &err);
  (void)sqlite3_exec(g_db, "PRAGMA foreign_keys=OFF;", NULL, NULL, &err);
  /* RSS budget on the 2 GB box: cap the page cache, allow a modest mmap */
  (void)sqlite3_exec(g_db, "PRAGMA cache_size=-16384;", NULL, NULL, &err);  /* 16 MiB */
  (void)sqlite3_exec(g_db, "PRAGMA mmap_size=268435456;", NULL, NULL, &err); /* 256 MiB */
  if (err) sqlite3_free(err);

  /* M10: move checkpoint fdatasyncs off the event loop. If the worker cannot
   * start (or sqlite is not threadsafe), fall back to inline autocheckpoint. */
  if (sqlite3_threadsafe() > 0 && ckpt_start(path) == 0) {
    err = NULL;
    (void)sqlite3_exec(g_db, "PRAGMA wal_autocheckpoint=0;", NULL, NULL, &err);
    if (err) sqlite3_free(err);
  } else {
    err = NULL;
    (void)sqlite3_exec(g_db, "PRAGMA wal_autocheckpoint=1000;", NULL, NULL, &err);
    if (err) sqlite3_free(err);
  }
  g_start_sec = (int64_t)time(NULL);
  return 0;
}

void db_close(void) {
  if (g_ckpt_run) {
    g_ckpt_run = 0;
    pthread_join(g_ckpt_thread, NULL);
  }
  if (g_ckpt_db) { sqlite3_close(g_ckpt_db); g_ckpt_db = NULL; }
  for (int i = 0; i < g_stmt_count; i++) {
    sqlite3_finalize(g_stmts[i].stmt);
    free(g_stmts[i].sql);
  }
  g_stmt_count = 0;
  if (g_db) { sqlite3_close(g_db); g_db = NULL; }
}

int64_t x_db_prepare(const char *sql, int64_t len) {
  sqlite3_stmt *st = stmt_lookup(sql, len);
  if (st) {
    sqlite3_reset(st);
    sqlite3_clear_bindings(st);
    return (int64_t)(uintptr_t)st;   /* opaque handle = the pointer itself */
  }
  if (g_stmt_count >= STMT_CACHE_MAX) return 0;   /* should never happen: fixed SQL set */
  sqlite3_stmt *n = NULL;
  if (sqlite3_prepare_v2(g_db, sql, (int)len, &n, NULL) != SQLITE_OK) return 0;
  char *copy = malloc((size_t)len + 1);
  memcpy(copy, sql, (size_t)len);
  copy[len] = 0;
  g_stmts[g_stmt_count].sql = copy;
  g_stmts[g_stmt_count].stmt = n;
  g_stmt_count++;
  return (int64_t)(uintptr_t)n;
}

static sqlite3_stmt *h(int64_t stmt) { return (sqlite3_stmt *)(uintptr_t)stmt; }

int x_db_bind_int(int64_t stmt, int32_t idx, int64_t v) {
  return sqlite3_bind_int64(h(stmt), idx, v);
}

int x_db_bind_text(int64_t stmt, int32_t idx, const char *p, int64_t len) {
  return sqlite3_bind_text(h(stmt), idx, p, (int)len, SQLITE_TRANSIENT);
}

int x_db_step(int64_t stmt) {
  int rc = sqlite3_step(h(stmt));
  if (rc == SQLITE_ROW) return 1;
  if (rc == SQLITE_DONE) return 0;
  return -1;
}

int64_t x_db_column_int(int64_t stmt, int32_t idx) {
  return sqlite3_column_int64(h(stmt), idx);
}

const char *x_db_column_text(int64_t stmt, int32_t idx) {
  return (const char *)sqlite3_column_text(h(stmt), idx);
}

int64_t x_db_column_bytes(int64_t stmt, int32_t idx) {
  return sqlite3_column_bytes(h(stmt), idx);
}

int64_t x_db_changes(void) { return (int64_t)sqlite3_changes64(g_db); }

int x_db_reset(int64_t stmt) {
  sqlite3_reset(h(stmt));
  sqlite3_clear_bindings(h(stmt));
  return 0;
}

const char *x_db_errmsg(void) { return sqlite3_errmsg(g_db); }
