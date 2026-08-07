#!/bin/bash
# ofd_ssh.sh [ssh opts] "<remote command>" — run a command on the OFD / Chestny-Znak machine
# (RustDesk 474932946, AnyDesk 121019169, hostname desktop-i7oe05b) over the reverse-SSH tunnel.
#
# Path:  /work  --ssh-->  jump VPS 178.253.55.128 : 2245  --(reverse tunnel)-->  machine sshd :22
#        login = User (Windows admin) authenticated by key ssh_channel/ofd_me.
# The machine (behind NAT) initiates the tunnel outbound; the OFDTunnel scheduled task
# (SYSTEM, at boot+logon) keeps it alive. See orch/live/reports/report_T01_ofd_tunnel.md.
# NOTE: cash KSO uses port 2243, 1C-server 239677631 uses 2244 — this OFD box is 2245.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
#
# Examples:
#   bash ofd_ssh.sh 'hostname && whoami'
#   bash ofd_ssh.sh 'powershell -NoProfile -Command "Get-Service sshd"'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
OFDUSER='User'
VPS=178.253.55.128
PORT=2245
# login is the interactive Windows admin account 'User'; passed via -o User= (target = VPS host only),
# same form as srv_ssh.sh so a Cyrillic rename later needs no edit here.
exec ssh -i "$DIR/ssh_channel/ofd_me" -p "$PORT" \
  -o User="$OFDUSER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_ofd" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes \
  "$VPS" "$@"
