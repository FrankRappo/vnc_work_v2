#!/bin/bash
# cdp_up.sh — ship cdp_start.ps1 to the remote machine and bring the headless CDP browser up.
# Idempotent: prints CDP=ALREADY if it is already listening.
#   bash cdp_up.sh            # default channel (ofd)
#   SSH=... SCP=... RHOST=... bash cdp_up.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="${SSH:-$DIR/../ofd_ssh.sh}"
SCP="${SCP:-$DIR/../ofd_scp.sh}"
RHOST="${RHOST:-ofd}"
RDIR="${RDIR:-C:/Users/User}"
bash "$SCP" "$DIR/cdp_start.ps1" "$RHOST:$RDIR/cdp_start.ps1" >/dev/null 2>&1 || { echo "SCP_FAIL"; exit 1; }
bash "$SSH" "powershell -NoProfile -ExecutionPolicy Bypass -File ${RDIR//\//\\}\\cdp_start.ps1" 2>&1 | grep -E "^CDP=|Browser"
