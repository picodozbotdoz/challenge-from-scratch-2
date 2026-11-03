#!/usr/bin/env bash
# Append-only journal + state discipline. flock-guarded via state/.lock.
#
#   tools/journal.sh begin  "M0: bootstrap repo"       # start a step
#   tools/journal.sh ok     "M0: sanity build green"   # step succeeded
#   tools/journal.sh fail   "M2: link error: ..."      # step failed
#   tools/journal.sh note   "observation ..."          # informational
#   tools/journal.sh milestone M0 done                 # milestone status (updates progress.json)
#
# Optional: JOURNAL_NEXT="literal next command" sets state/next-step.txt alongside the entry.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
JOURNAL="$HERE/JOURNAL.md"
STATE="$HERE/state"
LOCK="$STATE/.lock"
mkdir -p "$STATE"
: >> "$LOCK"

[ $# -ge 1 ] || { echo "usage: journal.sh begin|ok|fail|note|milestone <text...>" >&2; exit 1; }
kind="$1"; shift

( flock 9
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  case "$kind" in
    begin|ok|fail|note)
      [ $# -ge 1 ] || { echo "journal.sh $kind needs text" >&2; exit 1; }
      printf '%s %-5s %s\n' "$ts" "${kind^^}" "$*" >> "$JOURNAL"
      ;;
    milestone)
      id="$1"; status="${2:-done}"
      printf '%s MILE %s %s\n' "$ts" "$id" "$status" >> "$JOURNAL"
      # keep state/progress.json in sync (idempotent rewrite from JOURNAL.md tail)
      python3 - "$JOURNAL" "$STATE/progress.json" <<'EOF'
import json, re, sys
journal, out = sys.argv[1], sys.argv[2]
status = {}
with open(journal) as f:
    for line in f:
        m = re.match(r'^\S+ MILE (\S+) (\S+)\s*$', line)
        if m:
            status[m.group(1)] = m.group(2)  # last mention wins
with open(out, 'w') as f:
    json.dump({'milestones': status}, f, indent=2, sort_keys=True)
    f.write('\n')
EOF
      ;;
    *)
      echo "journal.sh: unknown kind '$kind'" >&2; exit 1;;
  esac
  if [ -n "${JOURNAL_NEXT:-}" ]; then
    printf '%s\n' "$JOURNAL_NEXT" > "$STATE/next-step.txt"
  fi
) 9>>"$LOCK"
