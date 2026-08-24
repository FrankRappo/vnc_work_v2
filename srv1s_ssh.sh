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
# 🔴 T292, ночь 23→24.08. ЗАПАСНОЙ ПУТЬ, КОГДА ВНЕШНИЙ ПОРТ VPS НЕ ПРИНИМАЕТ.
#    В эту ночь 2248 (и 2250) перестали открываться С НАШЕЙ СТОРОНЫ: `/dev/tcp` не соединяется,
#    хотя на самом VPS порт СЛУШАЕТ, а порт 22 туда открыт. То есть режется путь снаружи, а не
#    туннель. Тогда идём на VPS по 22 и прыгаем на 127.0.0.1:2248 — тот же самый туннель, только
#    с той стороны. Прямой путь пробуем первым: он дешевле и не требует пароля root.
if ! timeout 8 bash -c "cat < /dev/null > /dev/tcp/$VPS/$PORT" 2>/dev/null; then
  PW=$(sudo grep -oP 'root-пароль `\K[^`]+' /work/kso/CREDENTIALS.md 2>/dev/null | head -1)
  if [ -n "${PW:-}" ]; then
    exec ssh -i "$DIR/ssh_channel/srv1s_me" \
      -o User="$SRVUSER" \
      -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srv1s" \
      -o StrictHostKeyChecking=no \
      -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
      -o ConnectTimeout=25 -o BatchMode=yes \
      -o ProxyCommand="sshpass -p '$PW' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20 root@$VPS -W 127.0.0.1:$PORT" \
      srv1s-via-vps22 "$@"
  fi
fi
exec ssh -i "$DIR/ssh_channel/srv1s_me" -p "$PORT" \
  -o User="$SRVUSER" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srv1s" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes \
  "$VPS" "$@"
