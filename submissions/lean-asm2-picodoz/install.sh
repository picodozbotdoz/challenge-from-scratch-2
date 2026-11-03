#!/usr/bin/env bash
# install.sh — run once as root on a clean Ubuntu 24.04.
# Toolchain needed to build: gcc + make + sqlite3 dev headers. Nothing else:
# the application layer is pre-generated x86-64 assembly (no Lean at deploy).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends build-essential libsqlite3-dev
