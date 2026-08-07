#!/bin/bash
# srv_ssh.sh [ssh opts] "<remote command>" — run a command on machine 239677631
# (desktop-vgvheou, the 1C-server-admin box) over the reverse-SSH tunnel.
#
# Path:  /work  --ssh-->  jump VPS 178.253.55.128 : 2244  --(reverse tunnel)-->  machine sshd :22
#        login = Админ (Windows admin) authenticated by key ssh_channel/srv_me.
# The machine (behind NAT) initiates the tunnel outbound; the SRVTunnel scheduled task
# (SYSTEM, at boot+logon) keeps it alive. See chat/report_ZSSH-SRV.md for the full setup.
# NOTE: cash KSO uses port 2243 — this machine is a SEPARATE box on port 2244.
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
#
# Examples:
#   bash srv_ssh.sh 'hostname && whoami'
#   bash srv_ssh.sh 'powershell -NoProfile -Command "Get-Service sshd"'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SRVUSER='Админ'
VPS=178.253.55.128
PORT=2244
# NB: login is a Cyrillic account ('Админ') — scp/ssh reject non-ASCII in the user@host form
# ("invalid user name"), so the user is passed via -o User= and the target is just the VPS host.
exec ssh -i "$DIR/ssh_channel/srv_me" -p "$PORT" \
  -o User="$SRVUSER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srv" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes \
  "$VPS" "$@"
