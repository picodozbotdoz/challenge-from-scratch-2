#!/usr/bin/env bash
# Verify the challenge seed DB (and rebuild it via the challenge's own script if broken/--rebuild).
# The seed lives in the challenge repo; this script NEVER writes there except by running the
# challenge's own make-seed.sh (allowed and expected).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CHAL="$HERE/../repo/twelve-dollar-server-challenge"
DB="$CHAL/seed/feed.db"

if [ "${1:-}" = "--rebuild" ]; then
  echo "rebuilding seed via the challenge's make-seed.sh (~1 min)..."
  ( cd "$CHAL/seed" && PATH="$HOME/.nvm/versions/node/v24.21.0/bin:$PATH" bash make-seed.sh )
fi

[ -f "$DB" ] || { echo "seed DB missing: $DB (run with --rebuild)"; exit 1; }
echo "-- integrity"
sqlite3 "$DB" "PRAGMA quick_check;"
echo "-- counts"
sqlite3 "$DB" "SELECT 'users',count(*) FROM users UNION ALL SELECT 'posts',count(*) FROM posts UNION ALL SELECT 'likes',count(*) FROM likes;"
echo "-- journal mode (expect wal)"
sqlite3 "$DB" "PRAGMA journal_mode;"
echo "-- tokens.json"
python3 -c "import json,sys; t=json.load(open('$CHAL/seed/tokens.json')); print('tokens:', len(t), 'first:', t[0]['username'] if t else None)"
echo "seed OK"
