#!/bin/bash
# srv1s_ssh.sh [ssh opts] "<remote command>" — run a command on the NEW 1C server SERVER-1S
# (192.168.0.149, AnyDesk 1397277972) over the reverse-SSH tunnel.
#
# Path:  /work  --ssh-->  jump VPS 178.253.55.128 : 2248  --(reverse tunnel)-->  SERVER-1S sshd :22
#        login = User (local admin on SERVER-1S) authenticated by key ssh_channel/srv1s_me.
# The machine (behind NAT) initiates the tunnel outbound; the SRV1STunnel scheduled task
# (SYSTEM, at boot+logon) keeps it alive.  Set up in T199 (2026-08-07).
#
# 🔴 Порты линейки VPS: 2243 касса №1, 2244 СТАРЫЙ сервер 1С (DESKTOP-VGVHEOU), 2245 ОФД/ЭЦП,
#    2246 КСО №2, 2247 КСО №3, **2248 НОВЫЙ сервер SERVER-1S**.
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
#
# Examples:
#   bash srv1s_ssh.sh 'hostname && whoami'
#   bash srv1s_ssh.sh 'powershell -NoProfile -Command "Get-Service sshd"'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SRVUSER='User'
VPS=178.253.55.128
PORT=2248
exec ssh -i "$DIR/ssh_channel/srv1s_me" -p "$PORT" \
  -o User="$SRVUSER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srv1s" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes \
  "$VPS" "$@"
