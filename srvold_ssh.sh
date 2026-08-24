#!/bin/bash
# srvold_ssh.sh "<remote command>" — run a command on the OLD 1C server DESKTOP-VGVHEOU
# (192.168.0.10, RustDesk 239677631) *через джамп* SERVER-1S, когда её собственный
# обратный туннель (VPS:2244) лежит.
#
# Path:  /work --ssh--> VPS 178.253.55.128:2248 --(reverse)--> SERVER-1S sshd
#              --(direct-tcpip -W)--> 192.168.0.10:22 (DESKTOP-VGVHEOU sshd)
#        login = Админ, ключ ssh_channel/srv_me (тот же, что у srv_ssh.sh).
#
# 🔴 Ключ НЕ копируется на SERVER-1S: аутентификация к старой машине выполняется
#    НАШИМ локальным ssh-клиентом, SERVER-1S работает только как TCP-релей (-W).
# 🔴 Запускать с dangerouslyDisableSandbox — песочница рубит ssh сигналом 16.
#
# Введён в T241 (11.08.2026), когда `srv_ssh.sh` отвечал
# «Connection closed by 178.253.55.128 port 2244» (вотчдог туннеля на старой машине умер).
#
# Примеры:
#   bash srvold_ssh.sh 'hostname && whoami'
#   bash srvold_ssh.sh 'powershell -NoProfile -Command "Get-ScheduledTask | ft"'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
OLDHOST=192.168.0.10
OLDUSER='Админ'
JUMPVPS=178.253.55.128
JUMPPORT=2248
JUMPUSER='User'

PROXY="ssh -i $DIR/ssh_channel/srv1s_me -p $JUMPPORT -o User=$JUMPUSER \
 -o UserKnownHostsFile=$DIR/ssh_channel/known_hosts_srv1s \
 -o StrictHostKeyChecking=accept-new -o ConnectTimeout=25 -o BatchMode=yes \
 $JUMPVPS -W %h:%p"

exec ssh -i "$DIR/ssh_channel/srv_me" \
  -o User="$OLDUSER" \
  -o ProxyCommand="$PROXY" \
  -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srvold" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=30 -o BatchMode=yes \
  "$OLDHOST" "$@"
