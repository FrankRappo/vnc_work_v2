#!/bin/bash
# zrun.sh <local.ps1> — push a (possibly Cyrillic) PowerShell script to the cash and run it,
# returning its stdout via the clipboard. Only an ASCII path is ever typed → Cyrillic-safe.
# Local .ps1 should be UTF-8 WITH BOM so the cash reads Cyrillic correctly. Export WAIT for read timeout.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL="$1"; WAIT="${WAIT:-30}"
bash $DIR/zput.sh "$LOCAL" 'C:\kso\_zrun.ps1' >/dev/null 2>&1
WAIT="$WAIT" bash $DIR/ztx.sh 'powershell -nop -ep bypass -f C:\kso\_zrun.ps1'
