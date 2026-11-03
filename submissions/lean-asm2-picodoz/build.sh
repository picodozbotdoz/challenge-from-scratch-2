#!/usr/bin/env bash
# build.sh — assemble the emitted application layer and link the server.
# NO Lean at deploy time: gen/app_gen.s is checked in (regenerated only through
# the promotion gate, tools/promote.sh, on the dev box).
#
# CAND_ASM env var (used by tools/promote.sh): assemble a candidate .s instead.
set -euo pipefail
cd "$(dirname "$0")"

ASM="${CAND_ASM:-gen/app_gen.s}"
[ -f "$ASM" ] || { echo "missing $ASM (derive+promote it first)"; exit 1; }

mkdir -p bin
# self-contained sqlite3 dev files (third_party/sqlite3); used when the system
# has no libsqlite3-dev (the CI box installs it via install.sh instead)
SQLINC="-Ithird_party/sqlite3/usr/include"
SQLLIB="-Lthird_party/sqlite3/usr/lib/x86_64-linux-gnu"
if [ -f /usr/include/sqlite3.h ]; then SQLINC=""; SQLLIB=""; fi
cc -O2 -Wall $SQLINC -c -o bin/app_gen.o "$ASM"
for f in runtime/main.c runtime/http.c runtime/db.c runtime/abi.c runtime/uring.c; do
  o="bin/$(basename "${f%.c}").o"
  cc -O2 -Wall $SQLINC -c -o "$o" "$f"
done
cc -no-pie -o bin/server bin/app_gen.o bin/main.o bin/http.o bin/db.o bin/abi.o bin/uring.o $SQLLIB -lsqlite3
echo "built bin/server ($(stat -c%s bin/server) bytes)"
