#!/usr/bin/env bash
# The ONLY sanctioned way to run lean/lake in this repo: hard 2 GiB memory cap, no swap.
# Usage: tools/lean_cap.sh lake build   (from spec/)   — or any lean/lake subcommand.
set -euo pipefail

# Resolve lake to an absolute path (systemd-run may not inherit the user PATH).
LAKE="$(command -v lake || true)"
[ -n "$LAKE" ] || LAKE="$HOME/.elan/bin/lake"
[ -x "$LAKE" ] || { echo "lean_cap.sh: lake not found" >&2; exit 1; }

# Accept an optional leading "lake" (usage: lean_cap.sh lake build == lean_cap.sh build).
[ "${1:-}" = "lake" ] && shift

exec systemd-run --user --scope --quiet \
  -p MemoryMax=2G -p MemorySwapMax=0 \
  "$LAKE" "$@"
