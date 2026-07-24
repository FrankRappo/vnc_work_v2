#!/bin/bash
# cdpq.sh <url> <local-out> [settle_ms] [local-js-file]
#
# Local wrapper: drive the REAL browser on the remote box over the reverse-SSH tunnel and bring
# the page back as TEXT. No screenshots, no GUI, no vision tokens -- the answer arrives greppable.
#
# Default expression = full outerHTML. Give a JS file to extract just what you need, e.g.
#   [...document.querySelectorAll('a')].map(a=>a.textContent.trim()+' | '+a.href).join('\n')
#
# Channel is parameterised: SSH=<ssh helper> SCP=<scp helper> RHOST=<scp alias> RDIR=<remote dir>
# so the same tool works against any box that has a tunnel helper pair.
#
#   bash cdpq.sh https://fs.atol.ru/ /tmp/fs.html
#   bash cdpq.sh https://www.atol.ru/ /tmp/links.txt 12000 ./js/links.js
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="${SSH:-/work/vnc_work/ofd_ssh.sh}"
SCP="${SCP:-/work/vnc_work/ofd_scp.sh}"
RHOST="${RHOST:-ofd}"
RDIR="${RDIR:-C:/Users/User}"
PORT="${CDP_PORT:-9222}"

# CDP_NONAV=1 -> evaluate on the page that is ALREADY open (needed for postback/click flows)
NONAV="${CDP_NONAV:-0}"
URL="${1:?usage: cdpq.sh <url|-> <local-out> [settle_ms] [js-file]}"
OUT="${2:?usage: cdpq.sh <url> <local-out> [settle_ms] [js-file]}"
SETTLE="${3:-9000}"
JSFILE="${4:-}"

TAG="q$(date +%H%M%S)$$"
REMOTE_OUT="$RDIR/t67_$TAG.out"
EXPR_ARG=""

# ship the driver scripts (idempotent, cheap)
bash "$SCP" "$DIR/cdp_get.ps1" "$RHOST:$RDIR/cdp_get.ps1" >/dev/null 2>&1 || { echo "SCP_FAIL driver"; exit 1; }

if [ -n "$JSFILE" ]; then
  bash "$SCP" "$JSFILE" "$RHOST:$RDIR/t67_$TAG.js" >/dev/null 2>&1 || { echo "SCP_FAIL js"; exit 1; }
  EXPR_ARG="-ExprFile ${RDIR//\//\\}\\t67_$TAG.js"
fi

WIN_OUT="${REMOTE_OUT//\//\\}"
WIN_DRV="${RDIR//\//\\}\\cdp_get.ps1"

# NOTE: with -NoNav the -Url argument is OMITTED entirely. Passing -Url "-" makes the PowerShell
# binder treat "-" as a stray positional and the whole invocation mis-binds (silent EVAL failure).
URL_ARG="-Url \"$URL\""
NAV_ARG=""
if [ "$NONAV" = "1" ]; then URL_ARG=""; NAV_ARG="-NoNav"; fi
bash "$SSH" "powershell -NoProfile -ExecutionPolicy Bypass -File $WIN_DRV $URL_ARG -Out \"$WIN_OUT\" -Port $PORT -SettleMs $SETTLE $EXPR_ARG $NAV_ARG" 2>&1 | tail -3

bash "$SCP" "$RHOST:$REMOTE_OUT" "$OUT" >/dev/null 2>&1 || { echo "SCP_FAIL pull"; exit 1; }
bash "$SSH" "cmd /c del \"$WIN_OUT\"" >/dev/null 2>&1
[ -n "$JSFILE" ] && bash "$SSH" "cmd /c del \"${RDIR//\//\\}\\t67_$TAG.js\"" >/dev/null 2>&1
echo "LOCAL=$OUT BYTES=$(wc -c < "$OUT")"
