#!/bin/bash
# anydesk_kso.sh — AnyDesk-руль для проекта КСО, ИЗОЛИРОВАН на отдельном дисплее.
#
# 🔴 ВАЖНО: оркестратор ведёт другой проект (shop) на ДЕФОЛТНОМ дисплее :98 через vnc.sh.
#   Поэтому AnyDesk-сессия КСО жёстко прибита к :99 / VNC-порт 5902 — не трогаем :98.
#
# AnyDesk показывает удалённый рабочий стол как ПИКСЕЛИ (не DOM) → CDP здесь не применим.
#   Глаза:  scrot по :99 → jpg → Read.
#   Руки:   xdotool по координатам (click/key/type) + xclip (paste, кириллица). Из bbox координат нет —
#           целимся по нативным пикселям скрина 1920x1080, КАЖДЫЙ клик проверяем скрином (см. 1C_CALIBRATION.md).
#
# Запускать из агентского Bash с dangerouslyDisableSandbox (песочница режет долгие процессы сигналом 16).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/shotlib.sh"          # защита от залежавшегося кадра (грабля kso-anydesk-stale-frame)
DISP="${AD_DISPLAY:-:99}"; PORT="${AD_PORT:-5902}"
SCREENS="${AD_SCREENS:-$DIR/screens}"
SCREEN="${AD_SCREEN:-1920x1080x24}"
# AnyDesk на старте дёргает PulseAudio и без аудиосервера падает (core dumped). В WSL берём готовый
# сокет WSLg. Можно переопределить AD_PULSE='' чтобы не задавать (если поднят свой pulse).
PULSE="${AD_PULSE-unix:/mnt/wslg/PulseServer}"
U(){ if [ "$(id -un)" = hgff ]; then env DISPLAY="$DISP" "$@"; else runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" "$@"; fi; }
xup(){ U xdpyinfo >/dev/null 2>&1; }
# Убить процессы СТРОГО по их DISPLAY в окружении (безопасно: :98 оркестратора не заденет).
# $1 — regex имени процесса (comm/cmdline), $2 — ожидаемый DISPLAY (напр. :99).
kill_on_display(){
  local pat="$1" want="DISPLAY=$2" pid env
  for pid in $(pgrep -f "$pat" 2>/dev/null); do
    [ -r "/proc/$pid/environ" ] || continue
    env=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -m1 '^DISPLAY=')
    [ "$env" = "$want" ] && { kill "$pid" 2>/dev/null && echo "  killed $pid ($pat @ $2)"; }
  done
}

case "${1:-}" in
  up)
    # служба AnyDesk (один системный инстанс, от root, не привязана к дисплею)
    pgrep -f 'anydesk --service' >/dev/null || { anydesk --service >/tmp/adesk_service.log 2>&1 & sleep 3; }
    if xup && pgrep -f "anydesk" | grep -q . && ss -ltn 2>/dev/null | grep -q ":$PORT "; then
      echo "[=] AnyDesk-стек уже поднят на $DISP / VNC localhost:$PORT"; exit 0; fi
    rm -f "/tmp/.X${DISP#:}-lock" "/tmp/.X11-unix/X${DISP#:}" 2>/dev/null
    pkill -f "Xvfb $DISP" 2>/dev/null; sleep 1
    mkdir -p "$SCREENS"
    runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin Xvfb "$DISP" -screen 0 "$SCREEN" -nolisten tcp >>/tmp/adesk_kso.log 2>&1 &
    sleep 2; xup || { echo "[X] Xvfb $DISP не встал"; exit 1; }
    U fluxbox >>/tmp/adesk_kso.log 2>&1 & sleep 2
    setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" ${PULSE:+PULSE_SERVER="$PULSE"} anydesk >>/tmp/adesk_kso_gui.log 2>&1 </dev/null &
    sleep 6
    # слушаем все интерфейсы — чтобы из Windows зайти по IP WSL, если localhost не пробрасывается
    U x11vnc -display "$DISP" -rfbport "$PORT" -nopw -forever -shared -quiet >>/tmp/adesk_kso.log 2>&1 &
    sleep 1
    echo "[OK] AnyDesk поднят. DISPLAY=$DISP  VNC=localhost:$PORT  (человек: TigerVNC → localhost:$PORT)"
    # 🔴 Каталог кадров печатаем ЯВНО: AD_SCREENS легко задать при up и забыть при shot — тогда кадры
    # расходятся по двум каталогам, и в «другом» остаётся залежь, которую потом читают как свежую.
    echo "[i] кадры этого стека: $SCREENS  (проверить: $0 where; убрать залежь: $0 clean)"
    _shot_warn_old "$SCREENS" "__none__"
    ;;
  shot)     # печатает ВРЕМЯ съёмки; путь — последняя строка; провал = SHOT_FAIL + код 1 (см. shotlib.sh)
    shot_guarded "${2:-shot}" "$SCREENS" "$DISP" U || exit 1 ;;
  where)    shot_where "$DISP" "$SCREENS" ;;
  clean)    shot_clean "$SCREENS" "${2:-1}" ;;
  click)    U xdotool mousemove "$2" "$3" click 1; echo "click $2 $3" ;;
  dblclick) U xdotool mousemove "$2" "$3" click --repeat 2 --delay 90 1; echo "dblclick $2 $3" ;;
  move)     U xdotool mousemove "$2" "$3"; echo "move $2 $3" ;;
  key)      shift; U xdotool key "$@"; echo "key $*" ;;
  type)     U xdotool type --delay 60 -- "$2"; echo "typed (ascii)" ;;          # только латиница/цифры
  paste)    printf '%s' "$2" | U xclip -selection clipboard; U xdotool key ctrl+v; echo "pasted" ;;  # кириллица — сюда
  id)       # ввести AnyDesk-ID удалённой КСО в активное поле "New Session" и подключиться (Enter)
    printf '%s' "$2" | U xclip -selection clipboard; U xdotool key ctrl+a; U xdotool key ctrl+v; sleep 0.3; U xdotool key Return; echo "connect → $2" ;;
  pos)      U xdotool getmouselocation 2>/dev/null ;;   # калибровка координат
  wins)     U xdotool search --name . 2>/dev/null | while read w; do echo "$(U xdotool getwindowname "$w" 2>/dev/null)"; done | sort -u ;;
  status)
    xup && echo "Xvfb $DISP: OK" || echo "Xvfb $DISP: нет"
    pgrep -f 'anydesk --service' >/dev/null && echo "anydesk service: OK" || echo "anydesk service: нет"
    ss -ltn 2>/dev/null | grep -q ":$PORT " && echo "x11vnc $PORT: слушает" || echo "x11vnc $PORT: нет" ;;
  viewer)
    echo "Windows TigerVNC → localhost:$PORT  (или: ssh-туннель на этот порт)" ;;
  down)     # гасит ТОЛЬКО :99-стек КСО; :98 оркестратора и службу AnyDesk не трогает
    pkill -f "x11vnc.*-rfbport $PORT" 2>/dev/null
    kill_on_display 'anydesk'  "$DISP"
    kill_on_display 'fluxbox'  "$DISP"
    pkill -f "Xvfb $DISP" 2>/dev/null   # Xvfb argv содержит сам ':99' — однозначно
    echo "[OK] AnyDesk-стек КСО ($DISP/$PORT) погашен. Служба AnyDesk и дисплей :98 не тронуты." ;;
  *)
    sed -n '2,12p' "$0"
    echo "Команды: up | shot <label> | where | clean [сут] | click x y | dblclick x y | move x y | key <seq> | type <ascii> | paste <text> | id <anydesk-id> | pos | wins | status | viewer | down" ;;
esac
