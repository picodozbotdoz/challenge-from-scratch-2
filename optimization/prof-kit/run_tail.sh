#!/usr/bin/env bash
# run_tail.sh VUS RAMP DURATION — clean, uninstrumented high-VU run with
# per-second server telemetry (CPU ticks, established conns) for tail analysis.
# Tick stays at default 10s — that is what we are testing.
set -euo pipefail
ROOT="/home/doz/zcode-workdir/twelve-d-workdir/challenge-from-scratch-2"
PROF="$ROOT/work/prof"
SUB="$ROOT/submissions/lean-asm2-picodoz"
CHAL="$ROOT/../repo/twelve-dollar-server-challenge"
VUS="${1:-4000}"
RAMP="${2:-60s}"
DUR="${3:-120s}"
PORT=3457
OUT="$PROF/out-tail$VUS"
K6="$ROOT/work/k6/k6-v1.1.0-linux-amd64/k6"

mkdir -p "$OUT"
# fresh DB each tail run (honest state)
rm -f "$PROF/tail.db" "$PROF/tail.db-wal" "$PROF/tail.db-shm"
cp "$CHAL/seed/feed.db" "$PROF/tail.db"

export SQLITE_PATH="$PROF/tail.db" JWT_SECRET=twelve-dollar-challenge HOST=127.0.0.1 PORT=$PORT
export FEED_TICK_SECS=10   # explicit: default tick — the thing under test

if ss -tln "( sport = :$PORT )" | grep -q LISTEN; then echo "!! port $PORT busy"; exit 1; fi

STRACE_BIN="$PROF/debs/root/usr/bin/strace"
if [ "${STRACE:-0}" = "1" ]; then
  "$STRACE_BIN" -f -T -o "$OUT/strace_full.txt" "$SUB/bin/server" >"$OUT/server.log" 2>&1 &
  SERVER_PID=$!
  sleep 0.3
  SERVER_PID=$(pgrep -P "$SERVER_PID" || echo "$SERVER_PID")
  echo "strace-wrapped server pid: $SERVER_PID"
else
  "$SUB/bin/server" >"$OUT/server.log" 2>&1 &
  SERVER_PID=$!
fi
echo "$SERVER_PID" > "$OUT/pid"
cleanup() { kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 60); do curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break; sleep 0.5; done
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || { echo "!! not healthy"; exit 1; }
echo "== healthy, starting k6 (VUS=$VUS RAMP=$RAMP DUR=$DUR) + 1Hz telemetry"

# 1 Hz telemetry: ms, minflt+maxflt, utime+stime, conns, rss, io bytes, wal size
(
  T0=$(date +%s%3N)
  while kill -0 "$SERVER_PID" 2>/dev/null; do
    NOW=$(date +%s%3N)
    ST=$(cat "/proc/$SERVER_PID/stat" 2>/dev/null || echo "")
    if [ -n "$ST" ]; then
      FLT=$(awk '{print $10+$11}' <<<"$ST")
      TICKS=$(awk '{print $14+$15}' <<<"$ST")
    else FLT=0; TICKS=0; fi
    CONNS=$(ss -tn state established "( sport = :$PORT )" 2>/dev/null | tail -n +2 | wc -l)
    RSS=$(awk '/VmRSS/{print $2}' "/proc/$SERVER_PID/status" 2>/dev/null || echo 0)
    RCHAR=$(awk '/^rchar/{print $2}' "/proc/$SERVER_PID/io" 2>/dev/null || echo 0)
    WBYTES=$(awk '/^write_bytes/{print $2}' "/proc/$SERVER_PID/io" 2>/dev/null || echo 0)
    SYSRW=$(awk '/^syscr|^syscw/{s+=$2} END{print s}' "/proc/$SERVER_PID/io" 2>/dev/null || echo 0)
    WALSZ=$(stat -c %s "$PROF/tail.db-wal" 2>/dev/null || echo 0)
    echo "$((NOW - T0)),$FLT,$TICKS,$CONNS,$RSS,$RCHAR,$WBYTES,$SYSRW,$WALSZ" >> "$OUT/telemetry.csv"
    # 5 Hz kernel-side probe: wchan + syscall number (catches rare stalls)
    for _ in 1 2 3 4; do
      sleep 0.2
      P5=$(date +%s%3N)
      WC=$(cat "/proc/$SERVER_PID/wchan" 2>/dev/null || echo DEAD)
      SC=$(awk '{print $1}' "/proc/$SERVER_PID/syscall" 2>/dev/null || echo DEAD)
      echo "$((P5 - T0)),$WC,$SC" >> "$OUT/wchan.csv"
    done
  done
) &
MON_PID=$!

cd "$CHAL"
VUS=$VUS RAMP_UP=$RAMP DURATION=$DUR BASE_URL="http://127.0.0.1:$PORT" \
  TOKENS="$CHAL/seed/tokens.json" \
  "$K6" run --out "json=$OUT/k6events.json" bench/load.js >"$OUT/k6.txt" 2>&1 || true

kill "$MON_PID" 2>/dev/null || true
echo "== k6 done, telemetry lines: $(wc -l < "$OUT/telemetry.csv")"
grep -E 'p\(95\)|p\(99\)|http_reqs\.\.|checks' "$OUT/k6.txt" | head -8
