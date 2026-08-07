#!/bin/bash
# zput.sh <local_file> <remote_win_path> — push a file to the cash (RustDesk :99) PRIVATELY via the
# bidirectional clipboard sync + C:\kso\c2f.ps1 reader (base64 rides the clipboard; we TYPE a short reader
# invocation, never paste). Verifies sha256+len. For files >~100KB use gzip (ZP_GZ=1). ASCII-safe.
# Prereq: C:\kso\c2f.ps1 on the cash. Export PSX,PSY = PS window body click point (default 850,250).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${AD_DISPLAY:-:99}"
LOCAL="$1"; REMOTE="$2"; PSX="${PSX:-850}"; PSY="${PSY:-250}"
LEN=$(stat -c%s "$LOCAL"); SHA=$(sha256sum "$LOCAL" | cut -d' ' -f1 | tr 'a-f' 'A-F')
B64=$(base64 -w0 "$LOCAL"); NB=${#B64}
SYNC=$(( 3 + NB/6000 )); [ "$SYNC" -lt 3 ] && SYNC=3
printf '%s' "$B64" | xclip -selection clipboard 2>/dev/null; sleep "$SYNC"
xdotool mousemove "$PSX" "$PSY" click 1; sleep 0.35
xdotool key Escape; sleep 0.2
xdotool type --delay ${TDELAY:-55} "powershell -nop -ep bypass -f C:\\kso\\c2f.ps1 '$REMOTE'"; sleep 0.3
xdotool key Return
sleep $(( 2 + NB/30000 ))
verdict=$(WAIT=12 bash $DIR/ztx.sh "Get-Content C:\\kso\\c2f.out -Raw" | tr -d '\r\n ')
echo "[zput] $LOCAL -> $REMOTE  len=$LEN sha=${SHA:0:16}"
echo "[zput] remote verdict: $verdict"
case "$verdict" in *"$SHA"*|*"${SHA,,}"*) echo "[zput] OK (sha match)";; *) echo "[zput] !! sha MISMATCH — retry or use gzip";; esac
