#!/bin/bash
# Template login flow for 1C web UI via VNC.
#
# Required env:
#   IC_USERNAME
#   IC_PASSWORD

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib_1c.sh"

IC_USERNAME="${IC_USERNAME:-}"
IC_PASSWORD="${IC_PASSWORD:-}"

if [ -z "$IC_USERNAME" ] || [ -z "$IC_PASSWORD" ]; then
  echo "[X] set IC_USERNAME and IC_PASSWORD before running"
  exit 1
fi

ic_require_resolution || exit 1
ic_liveness || exit 1

if ! bash "$HERE/socks_keepalive.sh" status 2>/dev/null | grep -q alive; then
  echo "[*] starting socks_keepalive in background..."
  nohup bash "$HERE/socks_keepalive.sh" start >/tmp/socks_keepalive.log 2>&1 &
  sleep 5
fi

ic_focus
ic_shot login_before >/dev/null

# Replace these coordinates with values from your calibration notes.
IC_USER_X="${IC_USER_X:-945}"
IC_USER_Y="${IC_USER_Y:-559}"
IC_PASS_X="${IC_PASS_X:-945}"
IC_PASS_Y="${IC_PASS_Y:-615}"
IC_LOGIN_X="${IC_LOGIN_X:-958}"
IC_LOGIN_Y="${IC_LOGIN_Y:-671}"

ic_click "$IC_USER_X" "$IC_USER_Y" 0.4
ic_clear_field
ic_paste "$IC_USERNAME"
ic_click "$IC_PASS_X" "$IC_PASS_Y" 0.4
ic_clear_field
ic_paste "$IC_PASSWORD"
ic_click "$IC_LOGIN_X" "$IC_LOGIN_Y" 1.0

echo "[*] login submitted, waiting for UI to load..."
sleep 20
ic_shot login_after >/dev/null
echo "[ok] login flow finished; verify screenshot in $IC_SHOTS_DIR"
