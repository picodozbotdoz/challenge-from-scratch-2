#!/usr/bin/env bash
# Local end-to-end validation: build the submission, start it on a FRESH copy of the seed DB on
# PORT (default 3457 — 3000 is occupied on this box), run the challenge's 42-check suite.
# Exit 0 <=> 42/42.
#
#   tools/test_local.sh [port]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SUB="$HERE/submissions/lean-asm2-picodoz"
CHAL="$HERE/../repo/twelve-dollar-server-challenge"
PORT="${1:-${PORT:-3457}}"

mkdir -p "$HERE/work"
WORK="$(mktemp -d "$HERE/work/testrun.XXXXXX")"

echo "== build"
bash "$SUB/build.sh"

echo "== fresh DB + start (port $PORT, log: $WORK/server.log)"
export SQLITE_PATH="$WORK/feed.db" JWT_SECRET=twelve-dollar-challenge HOST=127.0.0.1 PORT="$PORT"
cp "$CHAL/seed/feed.db" "$SQLITE_PATH"
bash "$SUB/start.sh" >"$WORK/server.log" 2>&1 &
PID=$!
cleanup() {
  pkill -P "$PID" 2>/dev/null || true
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
}
trap cleanup EXIT

for _ in $(seq 60); do curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break; sleep 1; done
curl -sf "http://127.0.0.1:$PORT/health" >/dev/null || {
  echo "!! server did not become healthy on port $PORT"; tail -30 "$WORK/server.log"; exit 1; }

echo "== suite"
rc=0
bash "$CHAL/test/test.sh" "http://127.0.0.1:$PORT" || rc=$?

echo "== server log tail"
tail -5 "$WORK/server.log" || true
exit $rc
