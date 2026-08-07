#!/bin/bash
# kso3_scp.sh <src> <dst> — copy files to/from KSO #3 (the third self-checkout, RustDesk 288860680)
# over the reverse-SSH tunnel (port 2247). Use the alias  kso3:  for the machine side; it expands to
# M210@178.253.55.128:  (M210 passed via -o User=, target = VPS host).
#
#   bash kso3_scp.sh ./file             kso3:C:/tmp/file     # /work -> machine
#   bash kso3_scp.sh kso3:C:/tmp/out    ./out                # machine -> /work
#
# Windows paths: use forward slashes after the drive (C:/...) so scp's ':' parsing is unambiguous.
#
# 🔴 KSO #3 shares hostname DESKTOP-89HR2JF and user M210 with KSO #2 (imaged from it). Tell them
#    apart by hardware only — UUID 454041C2-4453-11F1-83FA-C69B2E81F931 / MAC 40-62-31-37-AA-08 = KSO #3.
# NOTE: cash KSO #1 uses port 2243, 1C-server DESKTOP-VGVHEOU 2244, OFD box 2245, KSO #2 2246 — KSO #3 is 2247.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
KSO3USER='M210'
VPS=178.253.55.128
PORT=2247
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    kso3:*) args[$i]="$VPS:${args[$i]#kso3:}";;
  esac
done
exec scp -i "$DIR/ssh_channel/kso3_me" -P "$PORT" \
  -o User="$KSO3USER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_kso3" \
  -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -o BatchMode=yes \
  "${args[@]}"
