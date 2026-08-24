#!/bin/bash
# statkassa_lan_ssh.sh "<команда>" — стационарная касса РМК DESKTOP-6NTV2D5 ЧЕРЕЗ ЛОКАЛЬНУЮ СЕТЬ.
#
# 🔴 T299 (24.08.2026). Внешний путь `loyalty/ops/statkassa_ssh.sh` (VPS-порт 2250) для КОМАНД
#    работает, но крупный файл через него рвётся: 81 МБ установщика оборвались на 74 МБ
#    («lost connection»), и на кассе остался огрызок с чужим sha256. Тот же файл по локальной
#    сети магазина уехал целиком за 1 минуту 57 секунд.
#    Путь: /work --ssh--> VPS:2247 --(туннель)--> КСО №3 --(LAN)--> 192.168.0.187:22.
#
# 🔴 LAN-адрес кассы НЕ фиксирован (DHCP): 11.08 — .147, 23.08 и 24.08 — .187.
#    Проверять разрешением имени с сервера, переопределять через STATKASSA_LAN_IP.
# 🔴 Запускать с dangerouslyDisableSandbox.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
IP="${STATKASSA_LAN_IP:-192.168.0.187}"
LPORT="${STATKASSA_LAN_PORT:-12250}"
VPS=178.253.55.128
up() {
  ss -tln 2>/dev/null | grep -q "127.0.0.1:$LPORT " && return 0
  setsid nohup ssh -i "$DIR/ssh_channel/kso3_me" -p 2247 \
    -o User=M210 -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_kso3" \
    -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15 \
    -o ExitOnForwardFailure=yes -o ConnectTimeout=25 -o BatchMode=yes \
    -N -L "127.0.0.1:$LPORT:$IP:22" "$VPS" </dev/null >/tmp/statkassa_lan_fwd.log 2>&1 &
  disown
  for _ in $(seq 1 15); do ss -tln 2>/dev/null | grep -q "127.0.0.1:$LPORT " && return 0; sleep 1; done
  echo "statkassa_lan_ssh: форвард через КСО №3 не поднялся (/tmp/statkassa_lan_fwd.log)" >&2
  return 1
}
up || exit 1
exec ssh -i "$DIR/ssh_channel/statkassa_me" -p "$LPORT" \
  -o User=днс -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
  -o ConnectTimeout=25 -o BatchMode=yes 127.0.0.1 "$@"
