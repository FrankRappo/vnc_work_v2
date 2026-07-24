#!/bin/bash
# srvshot.sh <local-out.png> — screenshot the REMOTE machine's own screen over SSH and fetch it.
#
# Why: it does not need a RustDesk/AnyDesk viewer at all. The viewer can silently die and leave a
# FROZEN last frame on :99 — rc.sh classify still calls that "live", so a stale picture gets read
# as the current screen (this cost a wrong conclusion once). A server-side capture is always now.
#
# Channel is parameterised like cdpq.sh: SSH= SCP= RHOST= RDIR=
#   bash srvshot.sh /tmp/screen.png
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="${SSH:-/work/vnc_work/ofd_ssh.sh}"
SCP="${SCP:-/work/vnc_work/ofd_scp.sh}"
RHOST="${RHOST:-ofd}"
RDIR="${RDIR:-C:/Users/User}"
OUT="${1:?usage: srvshot.sh <local-out.png>}"
WIN_PNG="${RDIR//\//\\}\\srvshot.png"

bash "$SCP" "$DIR/shot_inner.ps1" "$RHOST:$RDIR/srvshot_inner.ps1" >/dev/null 2>&1 || { echo "SCP_FAIL inner"; exit 1; }
bash "$SCP" "$DIR/shot_run.ps1"   "$RHOST:$RDIR/srvshot_run.ps1"   >/dev/null 2>&1 || { echo "SCP_FAIL run"; exit 1; }
bash "$SSH" "powershell -NoProfile -ExecutionPolicy Bypass -File ${RDIR//\//\\}\\srvshot_run.ps1 -Png $WIN_PNG -Inner ${RDIR//\//\\}\\srvshot_inner.ps1" 2>&1 | grep -E "^SHOT=" 
bash "$SCP" "$RHOST:$RDIR/srvshot.png" "$OUT" >/dev/null 2>&1 || { echo "SCP_FAIL pull"; exit 1; }
echo "LOCAL=$OUT BYTES=$(wc -c < "$OUT")"
