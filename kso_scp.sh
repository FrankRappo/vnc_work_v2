#!/bin/bash
# kso_scp.sh <src> <dst> — copy files to/from the KSO cash over the reverse-SSH tunnel (port 2243).
# Use the alias  kso:  for the cash side; it expands to  sco_m210@178.253.55.128: .
#
#   bash kso_scp.sh ./agent.epf         kso:C:/kso/agent.epf     # /work -> cash
#   bash kso_scp.sh kso:C:/kso/out.txt  ./out.txt                # cash -> /work
#
# Windows paths: use forward slashes after the drive (C:/kso/...) so scp's ':' parsing is unambiguous.
# Relative remote paths land in C:\Users\sco_m210 .
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CASHUSER=sco_m210
VPS=178.253.55.128
PORT=2243
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    kso:*) args[$i]="$CASHUSER@$VPS:${args[$i]#kso:}";;
  esac
done
exec scp -i "$DIR/ssh_channel/kso_me" -P "$PORT" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_cash" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -o BatchMode=yes \
  "${args[@]}"
