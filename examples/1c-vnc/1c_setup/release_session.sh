#!/bin/bash
# Template logout flow for 1C web UI via VNC.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib_1c.sh"
KEEP_SOCKS=0
[ "${1:-}" = "--keep-socks" ] && KEEP_SOCKS=1

ic_focus

# Replace with calibrated coordinates for your UI.
IC_MENU_X="${IC_MENU_X:-1899}"
IC_MENU_Y="${IC_MENU_Y:-136}"
IC_FILE_X="${IC_FILE_X:-1703}"
IC_FILE_Y="${IC_FILE_Y:-335}"
IC_EXIT_X="${IC_EXIT_X:-1474}"
IC_EXIT_Y="${IC_EXIT_Y:-404}"
IC_CONFIRM_X="${IC_CONFIRM_X:-1003}"
IC_CONFIRM_Y="${IC_CONFIRM_Y:-641}"

ic_click "$IC_MENU_X" "$IC_MENU_Y" 1.0
ic_click "$IC_FILE_X" "$IC_FILE_Y" 1.0
ic_click "$IC_EXIT_X" "$IC_EXIT_Y" 2.0
ic_click "$IC_CONFIRM_X" "$IC_CONFIRM_Y" 3.0
ic_shot logout_result >/dev/null

echo "[*] logout submitted; verify screenshot in $IC_SHOTS_DIR"
bash "$HERE/socks_keepalive.sh" stop 2>&1 || true

if [ "$KEEP_SOCKS" -eq 0 ]; then
  echo "[*] stop your SOCKS tunnel if it is no longer needed"
else
  echo "[=] SOCKS left running (--keep-socks)"
fi
