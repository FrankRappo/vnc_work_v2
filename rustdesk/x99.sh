#!/bin/bash
# Примитивы управления дисплеем :99 (RustDesk-сессия). Скрины полноразмерные (реальные коорд 1920x1080).
#
# 🔴 shot/zoom защищены от ЗАЛЕЖАВШЕГОСЯ КАДРА (грабля kso-anydesk-stale-frame, 05.08.2026): раньше
# `scrot ... 2>/dev/null && convert ... && echo` при неудаче МОЛЧАЛА, а /tmp/x99.jpg от прошлого раза
# оставался лежать — и его читали как текущий экран. Теперь: артефакты сносятся ДО съёмки, провал
# кричит SHOT_FAIL и возвращает 1, на успехе печатается ВРЕМЯ съёмки (путь — последняя строка).
#
# DISP и каталог переопределяются (X99_DISPLAY/X99_SCREENS) — чтобы драйвер можно было ПРОВЕРИТЬ на
# свободном дисплее, не трогая живую RustDesk-сессию кассы на :99.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/shotlib.sh"
DISP="${X99_DISPLAY:-:99}"
SD="${X99_SCREENS:-/tmp}"
# root -> runuser как hgff; сам hgff -> напрямую (runuser доступен только root).
U(){ if [ "$(id -u)" = "0" ]; then runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" "$@"; else env DISPLAY="$DISP" "$@"; fi; }
case "${1:-}" in
  click) U xdotool mousemove "$2" "$3" click 1; echo "click $2 $3";;
  dbl)   U xdotool mousemove "$2" "$3" click --repeat 2 --delay 90 1; echo "dbl $2 $3";;
  type)  U xdotool type --delay 60 -- "$2"; echo "typed";;
  key)   shift; U xdotool key "$@"; echo "key $*";;
  shot)  shot_guarded x99 "$SD" "$DISP" U || exit 1;;
  zoom)  # zoom <WxH+X+Y> [scale%] — свежий кадр + вырезка; без кадра старый не подсовываем
         shot_guarded x99 "$SD" "$DISP" U >/dev/null || exit 1
         rm -f "$SD/x99z.jpg"
         convert "$SD/x99.png" -crop "$2" +repage -resize "${3:-250%}" -quality 88 "$SD/x99z.jpg" 2>/dev/null \
           || { echo "ZOOM_FAIL: convert не вырезал $2 из $SD/x99.png" >&2; exit 1; }
         echo "снят $(date '+%Y-%m-%d %H:%M:%S') DISPLAY=$DISP crop=$2"
         echo "$SD/x99z.jpg";;
  where) shot_where "$DISP" "$SD";;
  wins)  for w in $(U xdotool search --name . 2>/dev/null); do echo "$w: $(U xdotool getwindowname $w 2>/dev/null)"; done;;
  *)     echo "usage: click x y | dbl x y | type <s> | key <seq> | shot | zoom <WxH+X+Y> [scale%] | where | wins";;
esac
