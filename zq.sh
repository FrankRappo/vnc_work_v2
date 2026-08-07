#!/bin/bash
# zq.sh <local_script> — submit a job to the cash file-queue executor (cash_runner.ps1) and read its
# output back from the RustDesk :99 clipboard. The script is a PowerShell body; we append the '#EOJ'
# sentinel, push it to C:\kso\q\<id>.job via zput (clipboard-base64, not typed), then poll :99 clipboard
# for "JDONE_<id>". Reliable because nothing is typed for the read and the payload rides clipboard-base64.
# Env: WAIT = read timeout seconds (default 40).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${AD_DISPLAY:-:99}"
SRC="$1"; WAIT="${WAIT:-40}"
ID="j$$_$(date +%N | tail -c 5)"
TMP="$(mktemp /tmp/zq_${ID}.ps1)"
cat "$SRC" > "$TMP"; printf '\n#EOJ\n' >> "$TMP"
# push job file (payload via clipboard-base64; short fixed reader trigger). Retry push up to 3x on failure.
pushed=""
for a in 1 2 3; do
  vout="$(bash $DIR/zput.sh "$TMP" "C:\\kso\\q\\${ID}.job" 2>&1)"
  case "$vout" in *"OK (sha match)"*) pushed=1; break;; esac
  sleep 1
done
[ -z "$pushed" ] && echo "[zq] push unverified (continuing; runner uses #EOJ sentinel)" >&2
# poll :99 clipboard for JDONE_<id>
tag="JDONE_${ID}"
deadline=$(( $(date +%s) + WAIT )); out=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  cur="$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0')"
  case "$cur" in *"$tag"*) out="${cur#*$tag}"; break;; esac
  sleep 0.5
done
rm -f "$TMP"
if [ -n "$out" ]; then printf '%s\n' "$out"; exit 0; fi
echo "[zq] NO RESULT for $ID after ${WAIT}s (runner running? focus?)" >&2
exit 1
