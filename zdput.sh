#!/bin/bash
# zdput.sh <local> <remote> — push a file to the cash via the ksod clipboard daemon (base64 in command,
# no typing). Robust vs RustDesk keystroke corruption. Fine up to clipboard capacity (~hundreds of KB).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL="$1"; REMOTE="$2"; WAIT="${WAIT:-45}"
B64=$(base64 -w0 "$LOCAL")
LSHA=$(sha256sum "$LOCAL"|cut -d' ' -f1|tr a-f A-F)
CMD="try{[IO.File]::WriteAllBytes('$REMOTE',[Convert]::FromBase64String('$B64'));(Get-FileHash '$REMOTE' -Algorithm SHA256).Hash}catch{'ERR '+\$_.Exception.Message}"
R=$(WAIT="$WAIT" bash $DIR/zd.sh "$CMD" 2>&1 | tr -d '\r\n ')
echo "[zdput] $LOCAL -> $REMOTE"
echo "[zdput] local=$LSHA"
echo "[zdput] remote=$R"
case "$R" in *"$LSHA"*) echo "[zdput] OK";; *) echo "[zdput] MISMATCH";; esac
