#!/bin/bash
# rd_health.sh — здоровье RustDesk-канала к кассе с НАШЕЙ стороны (дисплей :99).
#
# Зачем (T110, 28.07.2026): канал «отвалился» 26→28.07 при полностью живой кассе.
# Причина была НЕ на кассе: наш локальный клиент на :99 провисел ~1 д 20 ч и ушёл в
# несвежее состояние (петля heartbeat/NAT) → `rustdesk --connect <ID>` молча не
# открывал сессию, а RustDesk рисовал «Remote desktop is offline» — сообщение,
# которое врёт: оно значит «мой клиент не смог договориться», а не «касса мертва».
# Лечится перезапуском НАШЕГО клиента. Этот скрипт делает это одной командой.
#
# 🔴 Запускать с dangerouslyDisableSandbox — песочница рубит долгие процессы сигналом 16.
# 🔴 Нужен root (runuser на дисплей hgff); без root скрипт сам перезапустится под sudo.
#
#   bash rd_health.sh check   [ID]   # жива ли сессия? exit 0/1, печатает заголовок окна
#   bash rd_health.sh up      [ID]   # ГЛАВНАЯ: проверить, при необходимости пересобрать и подключиться
#   bash rd_health.sh refresh        # перезапустить только локальный демон (лечит «несвежесть», без сессии)
#   bash rd_health.sh down           # снять наш клиент (дисплей :99 НЕ трогает)
#   bash rd_health.sh status         # процессы + дисплей + доступность hbbs
#   bash rd_health.sh prune  [N]   # выкинуть наши логи RustDesk старше N дней (по умолчанию 7)
#
# Что НЕ трогает никогда: Xvfb :99 / fluxbox / x11vnc (их поднимает root, на них держится
# канал), кассу (туда идёт только диагностика), другие машины на нашем сервере.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
DISP="${RD_DISPLAY:-:99}"
RT="${XDG_RUNTIME_DIR_99:-/tmp/xrt99}"
DEFAULT_ID="${RD_ID:-243540605}"
SERVER=178.253.55.128
LOCK=/tmp/rd_health.lock
LOG=/tmp/rustdesk_kso.log

[ "$(id -u)" = "0" ] || exec sudo -n bash "$0" "$@"

# защита от второго экземпляра: параллельные up/refresh перебивали бы друг другу процессы
exec 9>"$LOCK"
flock -w 120 9 || { echo "rd_health: другой экземпляр держит блокировку $LOCK — выходим"; exit 4; }

U(){ runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" "$@"; }
RD(){ setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin \
        DISPLAY="$DISP" XDG_RUNTIME_DIR="$RT" "$@" >>"$LOG" 2>&1 </dev/null & }

# Заголовок окна сессии. RustDesk дописывает hostname ТОЛЬКО после успешной
# аутентификации → «<ID>@<hostname>» и есть доказательство живого канала.
session_title(){
  local id="$1" w
  for w in $(U xdotool search --name "${id}@" 2>/dev/null); do
    U xdotool getwindowname "$w" 2>/dev/null && return 0
  done
  return 1
}

display_ok(){ U xdpyinfo >/dev/null 2>&1; }

# Снять ТОЛЬКО наш клиент. pkill -x = точное имя процесса: не заденет ни runuser-обёртки,
# ни собственный шелл. Обёртки connect.sh глушим по явному шаблону, который не может
# совпасть с командной строкой самого rd_health.sh (self-match гоча из README).
kill_client(){
  local p
  for p in $(pgrep -f 'rustdesk/connect\.sh' 2>/dev/null); do
    [ "$p" = "$$" ] && continue
    kill -9 "$p" 2>/dev/null && echo "  снял зависший connect.sh pid=$p"
  done
  pkill -x rustdesk 2>/dev/null && echo "  послал TERM клиентам rustdesk"
  sleep 3
  pkill -9 -x rustdesk 2>/dev/null && echo "  добил KILL"
  sleep 1
}

case "${1:-status}" in

  check)
    ID="${2:-$DEFAULT_ID}"
    if T=$(session_title "$ID"); then echo "LIVE: $T"; exit 0
    else echo "DEAD: окна сессии '${ID}@…' на $DISP нет"; exit 1; fi
    ;;

  prune)
    # RustDesk на нашей стороне пишет логи без ротации по размеру: на 28.07.2026 в
    # ~/.local/share/logs/RustDesk накопилось 2.7 ГБ (один файл 664 МБ, flutter_ffi 2.1 ГБ)
    # из-за петли heartbeat к несуществующему API-порту 21114. Само по себе это не рвёт
    # канал, но однажды забьёт диск. Чистим всё, что старше N дней (по умолчанию 7).
    # Одного «старше N дней» мало: flutter_ffi пишет ~0.5–1 ГБ В СУТКИ, так что после
    # возрастной чистки остаётся ещё несколько ГБ. Поэтому второй проход — по размеру:
    # сносим самые старые файлы, пока каталог не влезет в CAP МБ. rCURRENT.log не трогаем
    # никогда — в него пишет живой клиент.
    DAYS="${2:-7}"; CAP_MB="${3:-500}"
    L=/home/hgff/.local/share/logs/RustDesk
    [ -d "$L" ] || { echo "нет $L"; exit 0; }
    echo "== prune: логи RustDesk в $L (старше ${DAYS} дн., затем потолок ${CAP_MB} МБ) =="
    echo "  до:    $(du -sh "$L" 2>/dev/null | cut -f1)"
    find "$L" -type f -name '*.log' ! -name 'rustdesk_rCURRENT.log' -mtime "+$DAYS" -delete 2>/dev/null
    while [ "$(du -sm "$L" 2>/dev/null | cut -f1)" -gt "$CAP_MB" ]; do
      OLDEST=$(find "$L" -type f -name '*.log' ! -name 'rustdesk_rCURRENT.log' -printf '%T@ %p\n' 2>/dev/null \
               | sort -n | head -1 | cut -d' ' -f2-)
      [ -n "$OLDEST" ] || break
      rm -f "$OLDEST" && echo "  снят по потолку: $(basename "$OLDEST")"
    done
    find "$L" -type d -empty -delete 2>/dev/null
    echo "  после: $(du -sh "$L" 2>/dev/null | cut -f1)"
    ;;

  down)
    echo "== снимаем наш клиент RustDesk (дисплей $DISP остаётся) =="
    kill_client
    pgrep -x rustdesk >/dev/null && echo "ОСТАЛИСЬ процессы rustdesk!" || echo "чисто"
    ;;

  refresh)
    # Профилактика «несвежести»: перезапустить демон БЕЗ открытия сессии на кассе.
    # Именно это ставится в cron — постоянную сессию к торгующей кассе не держим.
    ID="${2:-$DEFAULT_ID}"
    echo "== refresh: перезапуск локального демона RustDesk =="
    display_ok || { echo "дисплей $DISP не отвечает — refresh пропущен (его поднимает connect.sh)"; exit 3; }
    # Живая сессия = клиент заведомо не «несвежий». Не рвём чужую работу по каналу.
    if [ "${RD_FORCE:-0}" != "1" ] && T=$(session_title "$ID"); then
      echo "пропуск: идёт живая сессия ($T). RD_FORCE=1 чтобы всё равно перезапустить."
      exit 0
    fi
    kill_client
    RD rustdesk --service
    sleep 5
    if pgrep -x rustdesk >/dev/null; then
      echo "демон поднят: $(pgrep -x rustdesk | tr '\n' ' ')"
    else
      echo "демон НЕ поднялся — см. $LOG"; exit 2
    fi
    ;;

  up)
    ID="${2:-$DEFAULT_ID}"
    if T=$(session_title "$ID"); then echo "уже LIVE: $T"; exit 0; fi
    echo "== сессии к $ID нет — пересобираем канал с нуля =="
    for try in 1 2; do
      echo "-- попытка $try --"
      kill_client
      bash "$DIR/connect.sh" "$ID" >>"$LOG" 2>&1
      for _ in $(seq 1 12); do
        if T=$(session_title "$ID"); then echo "LIVE: $T"; exit 0; fi
        sleep 5
      done
      echo "  попытка $try не дала окна сессии"
    done
    echo "FAIL: канал к $ID не поднялся за 2 попытки."
    echo "Дальше проверять КАССУ — см. INSTRUCTION_rustdesk_kassa.md, раздел"
    echo "«Касса офлайн или лёг только канал»."
    exit 2
    ;;

  status)
    ID="${2:-$DEFAULT_ID}"
    echo "== дисплей $DISP =="
    display_ok && echo "  OK" || echo "  НЕ ОТВЕЧАЕТ"
    ps -eo pid,etime,cmd | grep -E 'Xvfb :99|fluxbox|x11vnc' | grep -v grep | sed 's/^/  /'
    echo "== наши процессы rustdesk =="
    if pgrep -x rustdesk >/dev/null; then
      ps -o pid,etime,cmd -p "$(pgrep -x rustdesk | tr '\n' ',' | sed 's/,$//')" | tail -n +2 | sed 's/^/  /'
    else
      echo "  (нет — клиент не запущен)"
    fi
    echo "== сессия к $ID =="
    if T=$(session_title "$ID"); then echo "  LIVE: $T"; else echo "  нет окна сессии"; fi
    echo "== hbbs $SERVER =="
    for p in 21115 21116 21117; do
      timeout 5 bash -c "</dev/tcp/$SERVER/$p" 2>/dev/null && echo "  tcp/$p открыт" || echo "  tcp/$p НЕ открыт"
    done
    ;;

  *) sed -n '1,30p' "$0"; exit 1;;
esac
