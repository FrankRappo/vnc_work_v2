#!/bin/bash
# zd.sh '<powershell>' — run a command on the cash via the ksod clipboard daemon. Focus-independent,
# Cyrillic-capable (clipboard carries Unicode). Requires ksod.ps1 running on the cash.
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
CMD="$1"; WAIT="${WAIT:-25}"
ID="D${$}$(date +%N | tail -c 6)"
marker="KSORES::$ID::"
printf 'KSOCMD::%s::%s' "$ID" "$CMD" | xclip -selection clipboard 2>/dev/null
deadline=$(( $(date +%s) + WAIT )); out=""; got=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  cur="$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0')"
  case "$cur" in *"$marker"*) out="${cur#*$marker}"; got=1; break;; esac
  sleep 0.3
done
if [ "$got" = 1 ]; then printf '%s\n' "$out"; else echo "[zd TIMEOUT ${WAIT}s — daemon down?]"; fi
