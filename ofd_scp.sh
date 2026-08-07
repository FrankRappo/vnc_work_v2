#!/bin/bash
# ofd_scp.sh <src> <dst> — copy files to/from the OFD / Chestny-Znak machine (RustDesk 474932946,
# hostname desktop-i7oe05b) over the reverse-SSH tunnel (port 2245). Use the alias  ofd:  for the
# machine side; it expands to  User@178.253.55.128:  (User passed via -o User=, target = VPS host).
#
#   bash ofd_scp.sh ./file            ofd:C:/tmp/file      # /work -> machine
#   bash ofd_scp.sh ofd:C:/tmp/out    ./out                # machine -> /work
#
# Windows paths: use forward slashes after the drive (C:/...) so scp's ':' parsing is unambiguous.
# NOTE: cash KSO uses port 2243, 1C-server 239677631 uses 2244 — this OFD box is 2245.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
OFDUSER='User'
VPS=178.253.55.128
PORT=2245
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    ofd:*) args[$i]="$VPS:${args[$i]#ofd:}";;
  esac
done
exec scp -i "$DIR/ssh_channel/ofd_me" -P "$PORT" \
  -o User="$OFDUSER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_ofd" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -o BatchMode=yes \
  "${args[@]}"
