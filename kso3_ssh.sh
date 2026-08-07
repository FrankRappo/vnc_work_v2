#!/bin/bash
# kso3_ssh.sh [ssh opts] "<remote command>" — run a command on KSO #3 (the third self-checkout,
# RustDesk 288860680, AnyDesk 1689199399) over the reverse-SSH tunnel.
#
# Path:  /work  --ssh-->  jump VPS 178.253.55.128 : 2247  --(reverse tunnel)-->  machine sshd :22
#        login = M210 (Windows admin) authenticated by key ssh_channel/kso3_me.
# The machine (behind NAT) initiates the tunnel outbound; the KSO3Tunnel scheduled task
# (SYSTEM, at boot+logon) keeps it alive. See orch/live/reports/report_T138_kso3_ssh_tunnel.md.
#
# 🔴 KSO #3 was imaged from KSO #2, so hostname (DESKTOP-89HR2JF) and Windows user (M210) are
#    IDENTICAL on both machines. `hostname` can NEVER tell them apart. Identify by HARDWARE:
#      KSO #3  UUID 454041C2-4453-11F1-83FA-C69B2E81F931  MAC 40-62-31-37-AA-08  IP 192.168.0.133
#      KSO #2  UUID C851863E-439A-11F1-97ED-D25D125A2000  MAC 40-62-31-37-A9-56  IP 192.168.0.164
#    Check with:  bash kso3_ssh.sh 'powershell -NoProfile -Command "(Get-CimInstance Win32_ComputerSystemProduct).UUID"'
# NOTE: cash KSO #1 uses port 2243, 1C-server DESKTOP-VGVHEOU 2244, OFD box 2245, KSO #2 2246 — KSO #3 is 2247.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
#
# Examples:
#   bash kso3_ssh.sh 'hostname && whoami'
#   bash kso3_ssh.sh 'powershell -NoProfile -Command "Get-Service sshd"'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
KSO3USER='M210'
VPS=178.253.55.128
PORT=2247
# login is the interactive Windows admin account 'M210'; passed via -o User= (target = VPS host only),
# same form as kso2_ssh.sh / srv_ssh.sh so a rename later needs no edit here.
exec ssh -i "$DIR/ssh_channel/kso3_me" -p "$PORT" \
  -o User="$KSO3USER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_kso3" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes \
  "$VPS" "$@"
