#!/bin/bash
# kso_put.sh <local_file> <remote_win_path> — write a local file to the cash via the ksod clipboard
# daemon (base64 in a single WriteAllBytes command). Verifies sha256+length echoed back. No typing.
# Good for files up to ~90KB (base64 rides the RustDesk clipboard). For bigger, gzip first.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${AD_DISPLAY:-:99}"
LOCAL="$1"; REMOTE="$2"; WAIT="${WAIT:-35}"
B64=$(base64 -w0 "$LOCAL")
LSHA=$(sha256sum "$LOCAL" | cut -d' ' -f1); LLEN=$(stat -c%s "$LOCAL")
CMD="[IO.File]::WriteAllBytes('${REMOTE}',[Convert]::FromBase64String('${B64}'));(Get-FileHash '${REMOTE}' -Algorithm SHA256).Hash+' '+(Get-Item '${REMOTE}').Length"
RES=$(WAIT="$WAIT" bash $DIR/kso.sh "$CMD" 2>&1)
RSHA=$(printf '%s' "$RES" | tr -d '\r\n ' | cut -c1-64)
echo "[kso_put] $LOCAL -> $REMOTE  len=$LLEN sha=${LSHA:0:16}"
echo "[kso_put] remote: $(printf '%s' "$RES" | tr -d '\r\n')"
if [ "${RSHA,,}" = "${LSHA,,}" ]; then echo "[kso_put] OK (sha match)"; exit 0; else echo "[kso_put] !! MISMATCH"; exit 1; fi
