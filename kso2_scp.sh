#!/bin/bash
# kso2_scp.sh <src> <dst> — copy files to/from KSO #2 (the second self-checkout, RustDesk 288860502,
# hostname desktop-89hr2jf) over the reverse-SSH tunnel (port 2246). Use the alias  kso2:  for the
# machine side; it expands to  M210@178.253.55.128:  (M210 passed via -o User=, target = VPS host).
#
#   bash kso2_scp.sh ./file             kso2:C:/tmp/file     # /work -> machine
#   bash kso2_scp.sh kso2:C:/tmp/out    ./out                # machine -> /work
#
# Windows paths: use forward slashes after the drive (C:/...) so scp's ':' parsing is unambiguous.
# NOTE: cash KSO #1 uses port 2243, 1C-server DESKTOP-VGVHEOU 2244, OFD box 2245 — KSO #2 is 2246.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
KSO2USER='M210'
VPS=178.253.55.128
PORT=2246
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    kso2:*) args[$i]="$VPS:${args[$i]#kso2:}";;
  esac
done
exec scp -i "$DIR/ssh_channel/kso2_me" -P "$PORT" \
  -o User="$KSO2USER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_kso2" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -o BatchMode=yes \
  "${args[@]}"
