#!/bin/bash
# zx.sh '<ascii PowerShell>' — hardened remote PS exec over the RustDesk :99 clipboard channel.
# Improves on ztx.sh: DRAINS the console input backlog before typing (ctrl+c + Enter), types with a
# safe delay, waits a FIXED settle for RustDesk keystroke-lag + command exec + clipboard sync-back,
# then polls for a per-call NONCE, and RETRIES the whole cycle on empty/mismatch. Keep commands ASCII
# and short (<~120 chars); for complex logic use zput.sh (file push) + a short trigger here.
# Env: PSX,PSY = click point in PS body (default 850,250). WAIT poll timeout (default 22). TRIES (default 2).
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
CMD="$1"; WAIT="${WAIT:-22}"; PSX="${PSX:-850}"; PSY="${PSY:-250}"; TRIES="${TRIES:-2}"; TDELAY="${TDELAY:-70}"
SETTLE="${SETTLE:-2.5}"
drain(){ xdotool mousemove "$PSX" "$PSY" click 1; sleep 0.3
         xdotool key ctrl+c; sleep 0.5; xdotool key ctrl+c; sleep 0.5
         xdotool key Escape; sleep 0.2; xdotool key Return; sleep 0.7; }
for t in $(seq 1 "$TRIES"); do
  N="ZX${$}$(date +%N | tail -c 6)_${t}"
  WRAPPED="Set-Clipboard (\"$N\" + [Environment]::NewLine + ((& { $CMD } 2>&1 | Out-String)))"
  drain
  xdotool type --delay "$TDELAY" -- "$WRAPPED"; sleep 0.3
  xdotool key Return
  sleep "$SETTLE"
  deadline=$(( $(date +%s) + WAIT )); out=""
  while [ "$(date +%s)" -lt "$deadline" ]; do
    cur="$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0')"
    case "$cur" in *"$N"*) out="${cur#*$N}"; break;; esac
    sleep 0.4
  done
  if [ -n "$out" ]; then printf '%s\n' "$out"; exit 0; fi
done
echo "[zx] NO OUTPUT after $TRIES tries" >&2
exit 1
