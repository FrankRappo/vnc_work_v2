#!/bin/bash
# srv_scp.sh <src> <dst> — copy files to/from machine 239677631 (desktop-vgvheou, 1C-server-admin box)
# over the reverse-SSH tunnel (port 2244). Use the alias  srv:  for the machine side; it expands
# to  Админ@178.253.55.128: .
#
#   bash srv_scp.sh ./file            srv:C:/tmp/file      # /work -> machine
#   bash srv_scp.sh srv:C:/tmp/out    ./out                # machine -> /work
#
# Windows paths: use forward slashes after the drive (C:/...) so scp's ':' parsing is unambiguous.
# NOTE: cash KSO uses port 2243 — this machine is a SEPARATE box on port 2244.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SRVUSER='Админ'
VPS=178.253.55.128
PORT=2244
# NB: login is a Cyrillic account ('Админ'). scp rejects non-ASCII in user@host ("invalid user
# name"), so the user is passed via -o User= and the  srv:  alias expands to just the VPS host.
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    srv:*) args[$i]="$VPS:${args[$i]#srv:}";;
  esac
done
exec scp -i "$DIR/ssh_channel/srv_me" -P "$PORT" \
  -o User="$SRVUSER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srv" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -o BatchMode=yes \
  "${args[@]}"
