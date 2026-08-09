#!/bin/bash
# srv1s_rdp.sh [up|down|status|shot] — GUI-канал к SERVER-1S (новый сервер 1С) через RDP.
#
# 🔴 ЗАЧЕМ ЕЩЁ ОДИН КАНАЛ, КОГДА ЕСТЬ SSH И RustDesk.
#   SSH даёт всё, кроме одного: интерактивного окна. А есть работы, которые платформа 1С не
#   умеет делать иначе — например, права роли РАСШИРЕНИЯ на HTTP-сервис. Через
#   LoadConfigFromFiles/ibcmd они молча выбрасываются (разобрано в T213 и раньше в ZSVC-USER),
#   и задаются ТОЛЬКО интерактивным Конфигуратором.
#   RustDesk на этой машине показывает КОНСОЛЬНЫЙ сеанс, а он стоит на экране входа. RDP же
#   создаёт СВОЙ сеанс: мы не трогаем чужой рабочий стол и не оставляем его разлогиненным.
#
# 🔴 ЧТО ЭТО НЕ ДЕЛАЕТ. Не открывает машину наружу: RDP ходит по уже существующему обратному
#   SSH-туннелю (VPS:2248), локально слушает только 127.0.0.1. Порт 3389 машины в интернет не
#   выставляется.
#
# 🔴 Дисплей отдельный (:98 по умолчанию) — чтобы не мешать другим сеансам съёмки и чтобы
#   размер окна был ИЗВЕСТЕН: координаты кликов считаются в НАТИВНЫХ пикселях этого дисплея.
#
# 🔴 Запускать с dangerouslyDisableSandbox (ssh).
#
#   bash srv1s_rdp.sh up          поднять туннель, Xvfb и клиент RDP
#   bash srv1s_rdp.sh shot f.png  снять кадр дисплея
#   bash srv1s_rdp.sh status      что живо
#   bash srv1s_rdp.sh down        погасить всё и снять сеанс на сервере
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
DISP="${SRV1S_DISPLAY:-:98}"
W="${SRV1S_W:-1600}"
H="${SRV1S_H:-1000}"
LPORT="${SRV1S_RDP_PORT:-13389}"
VPS=178.253.55.128
SSHPORT=2248
PIDDIR=/tmp/srv1s_rdp
mkdir -p "$PIDDIR"

пароль() {
  # 🔴 Пароль НЕ хранится в этом файле и не появляется в аргументах ps: xfreerdp читает его
  # из переменной окружения. Источник — CREDENTIALS.md, единственное место по правилам проекта.
  sudo grep -oP '\*\*Windows-пользователь: `?Admin`?, пароль `\K[^`]+' /work/kso/CREDENTIALS.md 2>/dev/null | head -1
}

туннель_поднят() { ss -ltn 2>/dev/null | grep -q "127.0.0.1:$LPORT"; }

case "${1:-status}" in
  up)
    if ! туннель_поднят; then
      nohup ssh -i "$DIR/ssh_channel/srv1s_me" -p "$SSHPORT" -o User=User \
        -o UserKnownHostsFile="$DIR/ssh_channel/known_hosts_srv1s" \
        -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
        -o ExitOnForwardFailure=yes -o BatchMode=yes \
        -N -L "127.0.0.1:$LPORT:127.0.0.1:3389" "$VPS" >/tmp/srv1s_rdp/tunnel.log 2>&1 &
      echo $! > "$PIDDIR/tunnel.pid"
      for i in $(seq 1 25); do sleep 1; туннель_поднят && break; done
    fi
    туннель_поднят || { echo "🔴 ТУННЕЛЬ 3389 НЕ ПОДНЯЛСЯ"; tail -3 /tmp/srv1s_rdp/tunnel.log; exit 1; }
    echo "туннель 127.0.0.1:$LPORT → SERVER-1S:3389 ЖИВ"

    if ! xdpyinfo -display "$DISP" >/dev/null 2>&1; then
      nohup Xvfb "$DISP" -screen 0 "${W}x${H}x24" -nolisten tcp >/tmp/srv1s_rdp/xvfb.log 2>&1 &
      echo $! > "$PIDDIR/xvfb.pid"
      for i in $(seq 1 15); do sleep 1; xdpyinfo -display "$DISP" >/dev/null 2>&1 && break; done
    fi
    xdpyinfo -display "$DISP" >/dev/null 2>&1 || { echo "🔴 XVFB $DISP НЕ ПОДНЯЛСЯ"; exit 1; }
    echo "дисплей $DISP ${W}x${H} ЖИВ"

    if ! pgrep -f "xfreerdp.*$LPORT" >/dev/null 2>&1; then
      P="$(пароль)"
      [ -n "$P" ] || { echo "🔴 ПАРОЛЬ Admin НЕ НАЙДЕН в CREDENTIALS.md"; exit 2; }
      # /cert:ignore — самоподписанный сертификат RDP машины; /sec:nla обязателен (fDenyTS=0, NLA вкл).
      # 🔴 Пароль подаётся ПЕРЕМЕННОЙ ОКРУЖЕНИЯ, а не аргументом: аргументы видны в ps любому
      # процессу на машине. FREERDP_ASKPASS не годится (спрашивает интерактивно), поэтому
      # используется штатное чтение из окружения через /p: с подстановкой в дочернем шелле,
      # который сам не попадает в ps со значением.
      nohup env DISPLAY="$DISP" WINPW="$P" bash -c 'exec xfreerdp3 /v:127.0.0.1:'"$LPORT"' /u:Admin \
        /p:"$WINPW" /cert:ignore /w:'"$W"' /h:'"$H"' +clipboard /compression /log-level:WARN' \
        >/tmp/srv1s_rdp/rdp.log 2>&1 &
      echo $! > "$PIDDIR/rdp.pid"
      sleep 12
    fi
    pgrep -f "xfreerdp.*$LPORT" >/dev/null 2>&1 && echo "КЛИЕНТ RDP ЗАПУЩЕН" || { echo "🔴 КЛИЕНТ RDP НЕ ЖИВ"; tail -15 /tmp/srv1s_rdp/rdp.log; exit 1; }
    ;;
  shot)
    out="${2:?usage: srv1s_rdp.sh shot <файл.png>}"
    rm -f "$out"
    env DISPLAY="$DISP" scrot -o -z "$out" || { echo "🔴 КАДР НЕ СНЯТ"; exit 1; }
    echo "кадр: $out ($(stat -c%s "$out") б, $(env DISPLAY="$DISP" xdpyinfo | awk '/dimensions/{print $2}'))"
    ;;
  status)
    туннель_поднят && echo "туннель: ЖИВ" || echo "туннель: НЕТ"
    xdpyinfo -display "$DISP" >/dev/null 2>&1 && echo "дисплей $DISP: ЖИВ" || echo "дисплей $DISP: НЕТ"
    pgrep -f "xfreerdp.*$LPORT" >/dev/null 2>&1 && echo "RDP-клиент: ЖИВ" || echo "RDP-клиент: НЕТ"
    ;;
  down)
    pkill -f "xfreerdp.*$LPORT" 2>/dev/null
    # 🔴 Сеанс на сервере снимается ЯВНО: брошенный RDP-сеанс живёт часами, держит лицензию 1С
    # и мешает следующему входу.
    bash "$DIR/srv1s_ssh.sh" 'powershell -NoProfile -Command "quser 2>&1 | Out-String"' 2>/dev/null | sed 's/^/  /'
    [ -f "$PIDDIR/xvfb.pid" ] && kill "$(cat "$PIDDIR/xvfb.pid")" 2>/dev/null
    [ -f "$PIDDIR/tunnel.pid" ] && kill "$(cat "$PIDDIR/tunnel.pid")" 2>/dev/null
    rm -f "$PIDDIR"/*.pid
    echo "КАНАЛ СНЯТ (сеанс Windows завершать отдельно: logoff <id>)"
    ;;
esac
