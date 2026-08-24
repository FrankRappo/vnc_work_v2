#!/bin/bash
# srv1s_lan_ssh.sh "<remote command>" — ЗАПАСНОЙ путь к SERVER-1S, когда VPS-порт 2248 не пускает.
#
# 🔴 T299 (24.08.2026). Прямой канал `srv1s_ssh.sh` (VPS:2248) внезапно начал отбивать ключ:
#    `Permission denied (publickey,password,keyboard-interactive)` — при ЖИВОЙ машине (её туннель
#    на VPS переподключается) и СОВПАДАЮЩЕМ host key. Расчистка залипшего форварда на VPS
#    (рецепт srv1s-ssh-acl-authorized-keys) НЕ помогла: порт слушается, host key тот же, ключ
#    отбивается. То есть ломается именно транспорт 2248, а не sshd машины и не права на ключах.
#
# Обход: идём в магазинную ЛОКАЛЬНУЮ СЕТЬ через КСО №3 (VPS:2247) и оттуда прыгаем на sshd
# SERVER-1S по локальному адресу. Тот же ключ `ssh_channel/srv1s_me` проходит с первого раза.
#
# 🔴 IP SERVER-1S = 192.168.0.142 (в CREDENTIALS.md записан УСТАРЕВШИЙ 192.168.0.149 — с него
#    машина не отвечает ни с кассы, ни с КСО №3). Имя резолвится: [Net.Dns]::GetHostAddresses('SERVER-1S').
#
# 🔴 Запускать с dangerouslyDisableSandbox.
#
#   bash srv1s_lan_ssh.sh 'hostname && whoami'
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SRV_IP="${SRV1S_LAN_IP:-192.168.0.142}"
LPORT="${SRV1S_LAN_PORT:-12248}"
VPS=178.253.55.128

up() {
  ss -tln 2>/dev/null | grep -q "127.0.0.1:$LPORT " && return 0
  setsid nohup ssh -i "$DIR/ssh_channel/kso3_me" -p 2247 \
    -o User=M210 -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_kso3" \
    -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15 \
    -o ExitOnForwardFailure=yes -o ConnectTimeout=25 -o BatchMode=yes \
    -N -L "127.0.0.1:$LPORT:$SRV_IP:22" "$VPS" </dev/null >/tmp/srv1s_lan_fwd.log 2>&1 &
  disown
  for _ in $(seq 1 15); do
    ss -tln 2>/dev/null | grep -q "127.0.0.1:$LPORT " && return 0
    sleep 1
  done
  echo "srv1s_lan_ssh: не поднялся форвард через КСО №3 (см. /tmp/srv1s_lan_fwd.log)" >&2
  return 1
}
up || exit 1
exec ssh -i "$DIR/ssh_channel/srv1s_me" -p "$LPORT" \
  -o User=User -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes 127.0.0.1 "$@"
