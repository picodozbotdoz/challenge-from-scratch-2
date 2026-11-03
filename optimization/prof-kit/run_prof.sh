#!/usr/bin/env bash
# run_prof.sh MODE — instrumented k6 runs against the iteration-2 server.
# MODE=plain  : official load.js, server plain, rip-sampler attached (realistic profile)
# MODE=strace : official load.js, server under strace -c (syscall census)
# MODE=hot    : no-think hot.js at -e VUS, sampler attached (saturation profile)
set -euo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"       # iteration root (challenge-from-scratch-2)
PROF="$HERE/work/prof"
SUB="$HERE/submissions/lean-asm2-picodoz"
CHAL="$HERE/../repo/twelve-dollar-server-challenge"
PORT="${PORT:-3457}"
DB="$PROF/prof.db"
K6="$HERE/work/k6/k6-v1.1.0-linux-amd64/k6"
STRACE="$PROF/debs/root/usr/bin/strace"
MODE="${1:?usage: run_prof.sh plain|strace|hot [k6_extra_env]}"
WIN="${2:-}"   # sampler window seconds (defaults below)

mkdir -p "$PROF/out-$MODE"
OUT="$PROF/out-$MODE"

# one fresh DB copy shared by all modes
if [ ! -f "$DB" ]; then cp "$CHAL/seed/feed.db" "$DB"; fi

export SQLITE_PATH="$DB" JWT_SECRET=twelve-dollar-challenge HOST=127.0.0.1 PORT="$PORT"
# profiling hygiene: disarm the 10s SIGALRM idle-sweep tick — its delivery
# interacts with ptrace stops and pollutes the rip histogram
export FEED_TICK_SECS=3600

# port must be free
if ss -tln "( sport = :$PORT )" | grep -q LISTEN; then echo "!! port $PORT busy"; exit 1; fi

case "$MODE" in
  plain)
    WIN="${WIN:-100}"
    "$PROF/sampler" -T "$WIN" -o "$OUT/samples.txt" -P "$OUT/maps.txt" -p "$OUT/pid" -S "$OUT" -- \
      "$SUB/bin/server" 2>"$OUT/sampler.log" &
    SPID=$!
    ;;
  strace)
    "$STRACE" -c -f -o "$OUT/syscalls.txt" "$SUB/bin/server" 2>"$OUT/strace.log" &
    SPID=$!
    sleep 0.2
    SERVER_PID="$(pgrep -P "$SPID" || true)"
    echo "$SERVER_PID" > "$OUT/pid"
    ;;
  hot)
    WIN="${WIN:-70}"
    "$PROF/sampler" -T "$WIN" -o "$OUT/samples.txt" -P "$OUT/maps.txt" -p "$OUT/pid" -S "$OUT" -- \
      "$SUB/bin/server" 2>"$OUT/sampler.log" &
    SPID=$!
    ;;
  *) echo "bad mode"; exit 1;;
esac

cleanup() {
  if [ -f "$OUT/pid" ]; then kill "$(cat "$OUT/pid")" 2>/dev/null || true; fi
  kill "$SPID" 2>/dev/null || true
  wait "$SPID" 2>/dev/null || true
}
trap cleanup EXIT

# health wait
ok=""
for _ in $(seq 60); do curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && { ok=1; break; }; sleep 0.5; done
[ -n "$ok" ] || { echo "!! server not healthy"; cat "$OUT/sampler.log" "$OUT/strace.log" 2>/dev/null; exit 1; }
echo "== server healthy (mode=$MODE)"

cd "$CHAL"
case "$MODE" in
  plain)
    VUS=1000 RAMP_UP=30s DURATION=60s BASE_URL="http://127.0.0.1:$PORT" \
      TOKENS="$CHAL/seed/tokens.json" \
      "$K6" run bench/load.js >"$OUT/k6.txt" 2>&1 || true
    ;;
  strace)
    VUS=1000 RAMP_UP=30s DURATION=60s BASE_URL="http://127.0.0.1:$PORT" \
      TOKENS="$CHAL/seed/tokens.json" \
      "$K6" run bench/load.js >"$OUT/k6.txt" 2>&1 || true
    ;;
  hot)
    VUS="${VUS:-300}" DURATION="${DURATION:-60s}" BASE_URL="http://127.0.0.1:$PORT" \
      TOKENS="$CHAL/seed/tokens.json" \
      "$K6" run "$PROF/hot.js" >"$OUT/k6.txt" 2>&1 || true
    ;;
esac
echo "== k6 done; waiting for sampler/strace to flush"

# sampler flushes on its -T deadline; strace flushes when server dies.
if [ -f "$OUT/pid" ] && [ -s "$OUT/pid" ]; then
  kill "$(cat "$OUT/pid")" 2>/dev/null || true
fi
sleep 2
kill "$SPID" 2>/dev/null || true
wait "$SPID" 2>/dev/null || true

cp /proc/self/stat "$OUT/shell.stat" 2>/dev/null || true
echo "== artifacts:"
ls -la "$OUT"
