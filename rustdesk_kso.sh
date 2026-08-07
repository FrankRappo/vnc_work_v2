#!/bin/bash
# rustdesk_kso.sh — RustDesk-руль КСО на дисплее :99 (замена AnyDesk: стабильный канал, буфер, без 5-мин лимита).
# Всё от hgff на :99 (как anydesk_kso.sh) → агентский драйвер anydesk_kso_hgff.sh (scrot/xdotool на :99) работает без изменений.
#   up <ID> <PASSWORD>  — поднять Xvfb :99 (если нет) + rustdesk --connect <ID>, ввести пароль, развернуть окно сессии
#   verify <ID>         — подтвердить коннект (есть окно сессии + движение экрана кассы) → exit 0/1
#   down | shot <l> | status
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/shotlib.sh"          # защита от залежавшегося кадра (грабля kso-anydesk-stale-frame)
DISP="${AD_DISPLAY:-:99}"; PORT="${AD_PORT:-5902}"
SCREENS="${AD_SCREENS:-$DIR/screens}"
SCREEN="${AD_SCREEN:-1920x1080x24}"
PULSE="${AD_PULSE-unix:/mnt/wslg/PulseServer}"
RT=/tmp/xrt99; mkdir -p "$RT" 2>/dev/null; chown hgff:hgff "$RT" 2>/dev/null
# U(): выполнить как hgff на :99. Если скрипт УЖЕ запущен от hgff (verify/shot/status зовёт сам агент),
# runuser недоступен (только root) → запускаем напрямую (hgff владеет :99). Только root уходит в runuser.
U(){ if [ "$(id -u)" = "0" ]; then runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" "$@"; else env DISPLAY="$DISP" "$@"; fi; }
RD(){ setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" XDG_RUNTIME_DIR="$RT" ${PULSE:+PULSE_SERVER="$PULSE"} "$@" >>/tmp/rustdesk_kso.log 2>&1 </dev/null & }
xup(){ U xdpyinfo >/dev/null 2>&1; }
kill_on_display(){ local pat="$1" want="DISPLAY=$2" pid env; for pid in $(pgrep -f "$pat" 2>/dev/null); do [ -r "/proc/$pid/environ" ] || continue; env=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -m1 '^DISPLAY='); [ "$env" = "$want" ] && { kill "$pid" 2>/dev/null && echo "  killed $pid ($pat @ $2)"; }; done; }

case "${1:-}" in
  up)
    ID="${2:?нужен RustDesk ID кассы}"; PW="${3:?нужен пароль}"
    # 1. убрать AnyDesk-клиент с :99 (службу/:98 не трогаем)
    kill_on_display 'anydesk' "$DISP"; sleep 1
    # 2. гарантировать Xvfb :99 (+ fluxbox)
    if ! xup; then
      rm -f "/tmp/.X${DISP#:}-lock" "/tmp/.X11-unix/X${DISP#:}" 2>/dev/null; pkill -f "Xvfb $DISP" 2>/dev/null; sleep 1
      mkdir -p "$SCREENS"
      runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin Xvfb "$DISP" -screen 0 "$SCREEN" -nolisten tcp >>/tmp/rustdesk_kso.log 2>&1 &
      sleep 2; xup || { echo "[X] Xvfb $DISP не встал"; exit 1; }
      U fluxbox >>/tmp/rustdesk_kso.log 2>&1 & sleep 2
    fi
    # 3. старый rustdesk на :99 — снять
    kill_on_display 'rustdesk' "$DISP"; sleep 1
    # 4. фоновый сервис rustdesk (нужен для коннекта) + сам коннект
    RD rustdesk --service; sleep 3
    RD rustdesk --connect "$ID"; sleep 12
    # 5. ввести пароль в сфокусированное поле диалога + Enter (+ отметить "запомнить" не обязательно)
    U xdotool type --delay 60 -- "$PW"; sleep 0.5; U xdotool key Return; sleep 8
    # 6. развернуть окно сессии на весь :99 (ищем по ID в заголовке)
    W=$(U xdotool search --name "$ID" 2>/dev/null | head -1)
    [ -n "$W" ] && { U xdotool windowactivate "$W" 2>/dev/null; U xdotool windowsize "$W" 1920 1080 2>/dev/null; U xdotool windowmove "$W" 0 0 2>/dev/null; }
    # 7. x11vnc для просмотра человеком (порт свободен после AnyDesk down)
    pgrep -f "x11vnc.*-rfbport $PORT" >/dev/null || U x11vnc -display "$DISP" -rfbport "$PORT" -nopw -forever -shared -quiet >>/tmp/rustdesk_kso.log 2>&1 &
    echo "[OK] RustDesk --connect $ID на $DISP (окно=$W). VNC localhost:$PORT"
    ;;
  verify)
    ID="${2:?нужен ID}"
    # окно сессии RustDesk: заголовок вида "<ID>@host - Remote Desktop - RustDesk".
    # Ищем по ID; фоллбэк — по "Remote Desktop" (если хост-часть заголовка сместила ID).
    W=$(U xdotool search --name "$ID" 2>/dev/null | head -1)
    [ -z "$W" ] && W=$(U xdotool search --name "Remote Desktop - RustDesk" 2>/dev/null | head -1)
    # 🔴 Кадры сравнения сносим ДО съёмки: иначе при неудачном scrot сравнивались бы кадры ПРОШЛОГО
    # запуска (движение 0, содержимое старое) и вердикт был бы про давно закрытую сессию.
    rm -f /tmp/rdv1.png /tmp/rdv2.png 2>/dev/null
    U scrot -o /tmp/rdv1.png 2>/dev/null; sleep 5; U scrot -o /tmp/rdv2.png 2>/dev/null
    if [ ! -s /tmp/rdv1.png ] || [ ! -s /tmp/rdv2.png ]; then
      echo "SHOT_FAIL: не сняты кадры с DISPLAY=$DISP — подтвердить/опровергнуть коннект НЕЧЕМ" >&2
      echo "NOT_VERIFIED"; exit 1
    fi
    D=$(compare -metric AE /tmp/rdv1.png /tmp/rdv2.png /dev/null 2>&1 | grep -oE '^[0-9]+' | head -1); [ -z "$D" ] && D=0
    # содержимое кадра: живой удалённый экран (киоск/десктоп) имеет высокую дисперсию яркости;
    # чёрное/замороженное окно RustDesk ~0. Это надёжнее движения (idle-экран статичен → motion=0, но коннект жив).
    SD=$(convert /tmp/rdv2.png -colorspace Gray -format "%[fx:standard_deviation]" info: 2>/dev/null); [ -z "$SD" ] && SD=0
    HAS_CONTENT=$(awk -v s="$SD" 'BEGIN{print (s>0.03)?1:0}')
    echo "session_window=${W:-нет} motion=${D}px content_sd=${SD}"
    # коннект подтверждён: есть окно сессии И (движение ИЛИ ненулевое содержимое кадра = не чёрный экран)
    if [ -n "$W" ] && { [ "$D" -gt 2000 ] || [ "$HAS_CONTENT" = "1" ]; }; then echo "VERIFIED"; exit 0; else echo "NOT_VERIFIED"; exit 1; fi
    ;;
  shot)  shot_guarded "${2:-shot}" "$SCREENS" "$DISP" U || exit 1 ;;   # время съёмки + путь последней строкой
  where) shot_where "$DISP" "$SCREENS" ;;
  clean) shot_clean "$SCREENS" "${2:-1}" ;;
  status)
    xup && echo "Xvfb $DISP: OK" || echo "Xvfb $DISP: нет"
    pgrep -f 'rustdesk' >/dev/null && echo "rustdesk: процессы есть" || echo "rustdesk: нет"
    ss -ltn 2>/dev/null | grep -q ":$PORT " && echo "x11vnc $PORT: слушает" || echo "x11vnc $PORT: нет" ;;
  down)
    pkill -f "x11vnc.*-rfbport $PORT" 2>/dev/null
    kill_on_display 'rustdesk' "$DISP"; kill_on_display 'fluxbox' "$DISP"
    pkill -f "Xvfb $DISP" 2>/dev/null
    echo "[OK] RustDesk-стек КСО ($DISP/$PORT) погашен (:98 и служба не тронуты)." ;;
  *) echo "usage: up <ID> <PASS> | verify <ID> | shot <l> | where | clean [сут] | status | down" ;;
esac
