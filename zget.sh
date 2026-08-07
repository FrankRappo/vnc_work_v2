#!/bin/bash
# zget.sh <remote_win_path> [local_out] — pull a file FROM the cash (RustDesk :99) via clipboard sync.
# The cash base64-encodes the file to its clipboard (behind a NONCE); we read it back on :99 and decode.
# For large/binary files fine up to the clipboard cap (~150KB base64). Default local_out = stdout.
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
REMOTE="$1"; OUT="${2:-/dev/stdout}"; PSX="${PSX:-850}"; PSY="${PSY:-250}"; WAIT="${WAIT:-24}"
N="ZG${$}$(date +%N | tail -c 5)"
xdotool mousemove "$PSX" "$PSY" click 1; sleep 0.35
xdotool key Escape; sleep 0.2
xdotool type --delay ${TDELAY:-55} "Set-Clipboard ('$N'+[Convert]::ToBase64String([IO.File]::ReadAllBytes('$REMOTE')))"; sleep 0.3
xdotool key Return
deadline=$(( $(date +%s) + WAIT )); b64=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  cur="$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0')"
  case "$cur" in *"$N"*) b64="${cur#*$N}"; break;; esac
  sleep 0.4
done
printf '%s' "$b64" | tr -d ' \n\r\t' | base64 -d > "$OUT" 2>/dev/null
[ "$OUT" != "/dev/stdout" ] && echo "[zget] $REMOTE -> $OUT ($(stat -c%s "$OUT" 2>/dev/null) bytes)"
