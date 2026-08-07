#!/bin/bash
# kso.sh '<single-line PowerShell>' — run a command on the cash via the ksod.ps1 clipboard daemon.
# Sets the :99 clipboard to KSOCMD::<id>::<cmd> (RustDesk syncs it to the cash); ksod runs it and puts
# KSORES::<id>::<output> back on the clipboard (synced back to :99). Focus-INDEPENDENT, no typing,
# Cyrillic-safe (clipboard is Unicode). For multi-line logic, pass a one-liner that dot-sources/base64-decodes.
# Env: WAIT = result timeout seconds (default 30).
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
CMD="$1"; WAIT="${WAIT:-30}"
ID="k$(date +%s)$(date +%N | tail -c 4)"
printf 'KSOCMD::%s::%s' "$ID" "$CMD" | xclip -selection clipboard 2>/dev/null
tag="KSORES::${ID}::"
deadline=$(( $(date +%s) + WAIT )); out=""; got=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  cur="$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0')"
  case "$cur" in *"$tag"*) got=1; out="${cur#*$tag}"; break;; esac
  sleep 0.4
done
if [ -n "$got" ]; then printf '%s\n' "$out"; exit 0; fi
echo "[kso] NO RESULT for $ID after ${WAIT}s (ksod alive? RustDesk clipboard sync on?)" >&2
exit 1
