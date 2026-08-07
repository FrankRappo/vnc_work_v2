#!/bin/bash
# srv1s_scp.sh <local> <remote>  — copy a file to the NEW 1C server SERVER-1S (VPS port 2248).
#   bash srv1s_scp.sh ./x.ps1 'C:/srv1s/x.ps1'
# Reverse direction (pull): pass the remote path first with the ':' form handled below.
#   bash srv1s_scp.sh --from 'C:/srv1s/ssh/setup.log' ./setup.log
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SRVUSER='User'
VPS=178.253.55.128
PORT=2248
OPTS=(-i "$DIR/ssh_channel/srv1s_me" -P "$PORT"
      -o User="$SRVUSER"
      -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srv1s"
      -o StrictHostKeyChecking=accept-new
      -o ConnectTimeout=25 -o BatchMode=yes)
if [ "${1:-}" = "--from" ]; then
  exec scp "${OPTS[@]}" "$VPS:$2" "$3"
else
  exec scp "${OPTS[@]}" "$1" "$VPS:$2"
fi
