#!/bin/bash
# kso2_ssh.sh [ssh opts] "<remote command>" — run a command on KSO #2 (the second self-checkout,
# RustDesk 288860502, hostname desktop-89hr2jf, Windows user M210) over the reverse-SSH tunnel.
#
# Path:  /work  --ssh-->  jump VPS 178.253.55.128 : 2246  --(reverse tunnel)-->  machine sshd :22
#        login = M210 (Windows admin) authenticated by key ssh_channel/kso2_me.
# The machine (behind NAT) initiates the tunnel outbound; the KSO2Tunnel scheduled task
# (SYSTEM, at boot+logon) keeps it alive. See orch/live/reports/report_T117_kso2_ssh_tunnel.md.
# NOTE: cash KSO #1 uses port 2243, 1C-server DESKTOP-VGVHEOU 2244, OFD box 2245 — KSO #2 is 2246.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
#
# Examples:
#   bash kso2_ssh.sh 'hostname && whoami'
#   bash kso2_ssh.sh 'powershell -NoProfile -Command "Get-Service sshd"'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
KSO2USER='M210'
VPS=178.253.55.128
PORT=2246
# login is the interactive Windows admin account 'M210'; passed via -o User= (target = VPS host only),
# same form as srv_ssh.sh / ofd_ssh.sh so a rename later needs no edit here.
exec ssh -i "$DIR/ssh_channel/kso2_me" -p "$PORT" \
  -o User="$KSO2USER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_kso2" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes \
  "$VPS" "$@"
