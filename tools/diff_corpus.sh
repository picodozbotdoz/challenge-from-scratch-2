#!/usr/bin/env bash
# Differential conformance: Lean spec vs emitted asm on the corpus.
# Any diff line = a divergence to investigate (and either fix or document).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SUB="$HERE/submissions/lean-asm2-picodoz"
WORK="$HERE/work/corpus"
mkdir -p "$WORK"

python3 "$HERE/tools/gen_corpus.py" "$WORK/corpus.txt"

# asm side
cc -g -O1 -no-pie -o "$WORK/asmcorpus" \
  "$SUB/gen/app_gen.s" "$SUB/tests/asm_corpus.c" "$SUB/runtime/abi.c" "$SUB/runtime/db.c" \
  -I"$SUB/third_party/sqlite3/usr/include" -L"$SUB/third_party/sqlite3/usr/lib/x86_64-linux-gnu" -lsqlite3
"$WORK/asmcorpus" "$WORK/corpus.txt" > "$WORK/asm.out"

# spec side (under the Lean cap)
( cd "$SUB/spec" && "$HERE/tools/lean_cap.sh" exe specdump < "$WORK/corpus.txt" > "$WORK/spec.out" )

if diff -u "$WORK/spec.out" "$WORK/asm.out" > "$WORK/diff.txt"; then
  echo "diff_corpus: IDENTICAL ($(wc -l < "$WORK/corpus.txt") cases)"
else
  echo "diff_corpus: DIVERGENCES:"
  head -40 "$WORK/diff.txt"
  echo "... (full: $WORK/diff.txt)"
  exit 1
fi
