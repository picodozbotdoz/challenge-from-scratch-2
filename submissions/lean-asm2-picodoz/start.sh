#!/usr/bin/env bash
# start.sh — run the server in the FOREGROUND, configured only by env vars
# (SQLITE_PATH, JWT_SECRET, HOST, PORT).
set -euo pipefail
cd "$(dirname "$0")"
exec ./bin/server
