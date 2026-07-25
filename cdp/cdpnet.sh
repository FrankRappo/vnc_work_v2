#!/bin/bash
# cdpnet.sh <local-out> [seconds] [url-filter] — record the remote browser's NETWORK traffic and
# bring it back as TEXT (requests + optional response bodies). Companion to cdpq.sh (DOM text).
#
# Use it when the data you want is in an XHR/JSON response rather than in the rendered DOM:
# LK/SPA grids, iframe payloads, "показать JSON" blocks that never open headlessly.
#
#   bash cdpnet.sh /tmp/net.txt 12 uidl                       # capture, bodies of matching URLs
#   CDP_CLICK="76,123" bash cdpnet.sh /tmp/net.txt 12          # click, then capture what it fired
#   CDP_JS=./js/trigger.js bash cdpnet.sh /tmp/net.txt 15 api  # run JS, then capture
#   CDP_NOBODY=1 bash cdpnet.sh /tmp/all.txt 20               # index only (URLs), no bodies
#
# Channel is parameterised exactly like cdpq.sh: SSH= SCP= RHOST= RDIR= CDP_PORT=
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="${SSH:-/work/vnc_work/ofd_ssh.sh}"
SCP="${SCP:-/work/vnc_work/ofd_scp.sh}"
RHOST="${RHOST:-ofd}"
RDIR="${RDIR:-C:/Users/User}"
PORT="${CDP_PORT:-9222}"

OUT="${1:?usage: cdpnet.sh <local-out> [seconds] [url-filter]}"
SECS="${2:-12}"
FILTER="${3:-}"

TAG="n$(date +%H%M%S)$$"
REMOTE_OUT="$RDIR/t71_$TAG.out"
WIN_OUT="${REMOTE_OUT//\//\\}"
WIN_DRV="${RDIR//\//\\}\\cdp_net.ps1"

bash "$SCP" "$DIR/cdp_net.ps1" "$RHOST:$RDIR/cdp_net.ps1" >/dev/null 2>&1 || { echo "SCP_FAIL driver"; exit 1; }

EXTRA=""
[ -n "${CDP_CLICK:-}" ] && EXTRA="$EXTRA -Click \"$CDP_CLICK\" -ClickBtn ${CDP_BTN:-left} -ClickCount ${CDP_CLICKS:-1}"
[ -n "${CDP_NAV:-}"   ] && EXTRA="$EXTRA -Nav \"$CDP_NAV\""
[ -n "$FILTER"        ] && EXTRA="$EXTRA -UrlFilter \"$FILTER\""
[ -z "${CDP_NOBODY:-}" ] && EXTRA="$EXTRA -Bodies"
[ -n "${CDP_MAXBODY:-}" ] && EXTRA="$EXTRA -MaxBody ${CDP_MAXBODY}"
# CDP_REMOTE_JS=<windows path>: expression file already ON the box (never uploaded, never deleted).
# Use it when the expression carries a secret that must not enter the orchestrator's context.
if [ -n "${CDP_REMOTE_JS:-}" ]; then
  EXTRA="$EXTRA -ExprFile ${CDP_REMOTE_JS}"
elif [ -n "${CDP_JS:-}" ]; then
  bash "$SCP" "$CDP_JS" "$RHOST:$RDIR/t71_$TAG.js" >/dev/null 2>&1 || { echo "SCP_FAIL js"; exit 1; }
  EXTRA="$EXTRA -ExprFile ${RDIR//\//\\}\\t71_$TAG.js"
fi

bash "$SSH" "powershell -NoProfile -ExecutionPolicy Bypass -File $WIN_DRV -Out \"$WIN_OUT\" -Port $PORT -Seconds $SECS $EXTRA" 2>&1 | tail -4
bash "$SCP" "$RHOST:$REMOTE_OUT" "$OUT" >/dev/null 2>&1 || { echo "SCP_FAIL pull"; exit 1; }
bash "$SSH" "cmd /c del \"$WIN_OUT\"" >/dev/null 2>&1
[ -n "${CDP_JS:-}" ] && bash "$SSH" "cmd /c del \"${RDIR//\//\\}\\t71_$TAG.js\"" >/dev/null 2>&1
echo "LOCAL=$OUT BYTES=$(wc -c < "$OUT")"
