#!/usr/bin/env bash
# Promotion gate for gen/app_gen.s.
#
#   tools/promote.sh work/derived/app_gen.s     # gate + promote a candidate
#   tools/promote.sh                            # derive candidate from spec/ first (Lean cap), then gate
#
# Gate = assemble + link + boot + challenge test suite with >= state/promote_min.txt passing
# checks (raise that number as milestones complete; after M5 it must be 42). On success the
# candidate replaces submissions/lean-asm2-picodoz/gen/app_gen.s. On failure gen/ is untouched.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SUB="$HERE/submissions/lean-asm2-picodoz"
SPEC="$SUB/spec"
GEN="$SUB/gen/app_gen.s"
MIN="$(cat "$HERE/state/promote_min.txt" 2>/dev/null || echo 1)"

CAND="${1:-}"
if [ -z "$CAND" ]; then
  CAND="$HERE/work/derived/app_gen.s"
  mkdir -p "$(dirname "$CAND")"
  echo "== deriving candidate from spec/ (Lean under 2G cap)"
  ( cd "$SPEC" && "$HERE/tools/lean_cap.sh" exe derive >"$CAND" )
fi
[ -f "$CAND" ] || { echo "candidate not found: $CAND"; exit 1; }

echo "== gate: assemble + link + boot + suite (min $MIN passing checks)"
PASS_RE='passed=([0-9]+)'
( cd "$SUB" && CAND_ASM="$CAND" bash "$SUB/build.sh" )   # build.sh uses CAND_ASM when set

# boot on a scratch port + run the suite, count passing checks
PORT_FREE=3458
WORK="$(mktemp -d "$HERE/work/promote.XXXXXX")"
export SQLITE_PATH="$WORK/feed.db" JWT_SECRET=twelve-dollar-challenge HOST=127.0.0.1 PORT=$PORT_FREE
cp "$HERE/../repo/twelve-dollar-server-challenge/seed/feed.db" "$SQLITE_PATH"
( cd "$SUB" && bash start.sh ) >"$WORK/server.log" 2>&1 &
PID=$!
cleanup() { pkill -P "$PID" 2>/dev/null || true; kill "$PID" 2>/dev/null || true; wait "$PID" 2>/dev/null || true; rm -rf "$WORK"; }
trap cleanup EXIT
for _ in $(seq 60); do curl -sf "http://127.0.0.1:$PORT_FREE/health" >/dev/null && break; sleep 1; done
curl -sf "http://127.0.0.1:$PORT_FREE/health" >/dev/null || { echo "!! gate failed: no healthy server"; tail -30 "$WORK/server.log"; exit 1; }
OUT="$(bash "$HERE/../repo/twelve-dollar-server-challenge/test/test.sh" "http://127.0.0.1:$PORT_FREE")" || true
echo "$OUT" | tail -3
PASSED="$(echo "$OUT" | grep -oE 'passed=[0-9]+' | head -1 | cut -d= -f2)"
[ -n "$PASSED" ] || PASSED=0
if [ "$PASSED" -lt "$MIN" ]; then
  echo "!! gate failed: $PASSED passing checks < required $MIN — gen/ left untouched"
  exit 1
fi

mkdir -p "$SUB/gen"
cp "$CAND" "$GEN"
echo "== promoted: $GEN ($PASSED checks green, min $MIN)"
