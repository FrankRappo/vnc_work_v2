#!/bin/bash
# ztx.sh '<ascii PowerShell>' — TYPE an ASCII PowerShell command into the focused PS window on the cash
# (RustDesk :99) and read its stdout back via the clipboard. Robust because:
#  - we TYPE (never paste) the command → immune to the flaky console ctrl+v path (clipboard SYNC works,
#    but pasting INTO the console did not register). US layout on the cash → special chars type correctly.
#  - output is captured with Set-Clipboard behind a per-call NONCE → we never read a stale buffer.
# Cyrillic can NOT be typed → keep commands ASCII; for Cyrillic/large payloads use zput.sh (file transfer).
# Export PSX,PSY = click point in the PS window BODY (default 850,250). WAIT = read timeout (default 14s).
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
CMD="$1"; WAIT="${WAIT:-14}"; PSX="${PSX:-850}"; PSY="${PSY:-250}"
N="ZN${$}$(date +%N | tail -c 6)"
WRAPPED="Set-Clipboard (\"$N\" + [Environment]::NewLine + ((& { $CMD } 2>&1 | Out-String)))"
xdotool mousemove "$PSX" "$PSY" click 1; sleep 0.3
xdotool key Escape; sleep 0.25
xdotool type --delay ${TDELAY:-55} -- "$WRAPPED"; sleep 0.3
xdotool key Return
deadline=$(( $(date +%s) + WAIT )); out=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  cur="$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0')"
  case "$cur" in *"$N"*) out="${cur#*$N}"; break;; esac
  sleep 0.4
done
printf '%s\n' "$out"
