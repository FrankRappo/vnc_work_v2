#!/bin/bash
# kso_ssh.sh [ssh opts] "<remote command>" — run a command on the KSO cash over the reverse-SSH tunnel.
#
# Path:  /work  --ssh-->  jump VPS 178.253.55.128 : 2243  --(reverse tunnel)-->  cash sshd :22
#        login = sco_m210 (Windows filtered-token admin) authenticated by key ssh_channel/kso_me.
# The cash (DESKTOP-E8FF2LU, behind NAT) initiates the tunnel outbound; the KSOTunnel scheduled
# task (SYSTEM, at boot+logon) keeps it alive. See report_ZFISCAL-SSH.md for the full setup.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
#
# Examples:
#   bash kso_ssh.sh 'hostname && whoami'
#   bash kso_ssh.sh 'cmd /c dir C:\kso'
#   bash kso_ssh.sh 'powershell -NoProfile -Command "Get-Service sshd"'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CASHUSER=sco_m210
VPS=178.253.55.128
PORT=2243
exec ssh -i "$DIR/ssh_channel/kso_me" -p "$PORT" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_cash" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes \
  "$CASHUSER@$VPS" "$@"
