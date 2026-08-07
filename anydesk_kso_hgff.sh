#!/bin/bash
# anydesk_kso_hgff.sh — драйвер AnyDesk-экрана :99 ДЛЯ АГЕНТА ОТ hgff (БЕЗ runuser!).
#
# 🔴 Агент-обследователь работает от hgff. anydesk_kso.sh использует `runuser -u hgff`
#    (нужны права root) → у hgff упадёт. Этот скрипт работает на :99 НАПРЯМУЮ (DISPLAY=:99
#    scrot/xdotool/xclip), т.к. сам hgff владеет дисплеем :99 (его поднял root через runuser-hgff).
#
# Поднимать/гасить сам X-стек (:99) hgff НЕ может (это делает root: anydesk_kso.sh up/down).
# Этот скрипт — только ГЛАЗА (scrot) и РУКИ (xdotool/xclip) внутри уже поднятого :99.
#
# AnyDesk = удалённый рабочий стол как ПИКСЕЛИ → координаты в НАТИВНЫХ 1920x1080.
# ВСЕГДА: shot → (при необходимости convert -crop -resize для зума) → Read jpg →
#         вычислить координаты по нативному кадру → click → ПРОВЕРИТЬ новым shot.
#
# 🔴 БУФЕР ОБМЕНА RustDesk СИНКАЕТСЯ МЕДЛЕННО (и двунаправленно — может вернуть старое значение).
#    Для вставки текста в кассу (paste/paste2), ОСОБЕННО КИРИЛЛИЦЫ, нужна бОльшая задержка синка,
#    иначе вставится пусто или обрежется (реально наблюдали: «Магазин Мацеста» → «Мацеста»).
#    По умолчанию ждём RD_CLIP_SYNC=3с; при сбоях увеличивай (RD_CLIP_SYNC=5..8) и/или проверяй
#    зумом, что текст дошёл. Многословную кириллицу лучше слать ПО ОДНОМУ СЛОВУ. ASCII/цифры
#    надёжнее печатать через `type`; кириллицу через `type` НЕ слать (ломается раскладкой) — только paste.
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
SCREENS="${AD_SCREENS:-/work/kso/chat/obsled_screens}"
mkdir -p "$SCREENS" 2>/dev/null

# Восстановить клавиатурный фокус окна RustDesk-сессии на :99. После клика мышью фокус
# клавиатуры часто уходит с окна сессии → xdotool type/key не доходят до кассы (грабля
# kso-rustdesk-cmd-focus). Активируем окно сессии ПЕРЕД любым вводом (type/paste/paste2/key).
RD_ID="${AD_RUSTDESK_ID:-243540605}"
# Задержка синка буфера RustDesk перед Ctrl+V (см. заметку в шапке). Дольше = надёжнее для кириллицы.
RD_CLIP_SYNC="${RD_CLIP_SYNC:-3}"
_focus(){
  local w
  w=$(xdotool search --name "$RD_ID" 2>/dev/null | head -1)
  [ -z "$w" ] && w=$(xdotool search --name "Remote Desktop - RustDesk" 2>/dev/null | head -1)
  [ -z "$w" ] && w=$(xdotool search --name "RustDesk" 2>/dev/null | head -1)
  [ -n "$w" ] && { xdotool windowactivate "$w" 2>/dev/null; sleep 0.2; }
}

case "${1:-}" in
  shot)     # 🔴 Кадр НИКОГДА не должен «наследоваться» от прошлого запуска (грабля kso-anydesk-stale-frame,
            # 05.08.2026): раньше при неудачном scrot команда молча ничего не печатала, а старые
            # $L.png/$L.jpg оставались лежать — и вызывающий, взявший файл по маске из каталога, читал
            # кадр НЕДЕЛЬНОЙ давности как текущий. Стоило неверного вывода про живую сессию.
            # Теперь: сносим прошлые артефакты ДО съёмки, при провале кричим и выходим ненулевым кодом,
            # при успехе печатаем ВРЕМЯ СЪЁМКИ, а путь оставляем последней строкой (для `| tail -1`).
            L="${2:-shot}"
            rm -f "$SCREENS/$L.png" "$SCREENS/$L.jpg" 2>/dev/null
            if ! scrot -o "$SCREENS/$L.png" 2>/dev/null; then
              echo "SHOT_FAIL: scrot не снял кадр с DISPLAY=$DISPLAY (стек поднят? нужен root: anydesk_kso.sh up)" >&2
              exit 1
            fi
            if ! convert "$SCREENS/$L.png" -quality 88 "$SCREENS/$L.jpg" 2>/dev/null; then
              echo "SHOT_FAIL: convert не собрал JPG из $SCREENS/$L.png" >&2
              exit 1
            fi
            # предупредить о залежавшихся кадрах рядом — именно они и вводят в заблуждение
            OLD=$(find "$SCREENS" -maxdepth 1 -name '*.png' ! -name "$L.png" -mmin +360 2>/dev/null | head -3)
            [ -n "$OLD" ] && { echo "ВНИМАНИЕ: в $SCREENS лежат СТАРЫЕ кадры (>6 ч), не путать с текущим:"; echo "$OLD" | sed 's/^/  /'; }
            echo "снят $(date '+%Y-%m-%d %H:%M:%S') DISPLAY=$DISPLAY size=$(stat -c%s "$SCREENS/$L.jpg" 2>/dev/null)б"
            echo "$SCREENS/$L.jpg" ;;
  where)    # где этот запуск ищет и пишет кадры — чтобы не гадать про AD_SCREENS
            echo "DISPLAY=$DISPLAY"; echo "SCREENS=$SCREENS"
            ls -la --time-style=+%Y-%m-%d_%H:%M:%S "$SCREENS" 2>/dev/null | tail -n +2 ;;
  zoom)     # zoom <src_label> <WxH+X+Y> <out_label> [scale%]  — вырезать и увеличить область кадра
            S="$SCREENS/$2.png"
            [ -f "$S" ] || { echo "ZOOM_FAIL: нет исходного кадра $S — сначала shot $2" >&2; exit 1; }
            convert "$S" -crop "$3" +repage -resize "${5:-300%}" -quality 90 "$SCREENS/$4.jpg" && echo "$SCREENS/$4.jpg" ;;
  click)    xdotool mousemove "$2" "$3" click 1; echo "click $2 $3" ;;
  dblclick) xdotool mousemove "$2" "$3" click --repeat 2 --delay 90 1; echo "dblclick $2 $3" ;;
  move)     xdotool mousemove "$2" "$3"; echo "move $2 $3" ;;
  drag)     # drag x1 y1 x2 y2 — press at (x1,y1), move to (x2,y2), release (for moving remote windows/panels)
            xdotool mousemove "$2" "$3"; xdotool mousedown 1; sleep 0.3; xdotool mousemove --sync "$4" "$5"; sleep 0.3; xdotool mouseup 1; echo "drag $2 $3 -> $4 $5" ;;
  paste2)   # paste2 <text> — буфер + Ctrl+V с ПОЛНОЙ задержкой синка RustDesk (кириллица/длинный текст)
            printf '%s' "$2" | xclip -selection clipboard 2>/dev/null; sleep "$RD_CLIP_SYNC"; _focus; xdotool key ctrl+v; echo "paste2 (ждал синк буфера ${RD_CLIP_SYNC}s)" ;;
  key)      _focus; shift; xdotool key "$@"; echo "key $*" ;;
  type)     _focus; xdotool type --delay 60 -- "$2"; echo "typed (ascii/digits only)" ;;
  paste)    printf '%s' "$2" | xclip -selection clipboard 2>/dev/null; sleep "$RD_CLIP_SYNC"; _focus; xdotool key ctrl+v; echo "pasted (ждал ${RD_CLIP_SYNC}s)" ;;
  scroll)   # scroll x y <up|down|left|right> [n] — hover (x,y) and wheel-scroll (left/right = horizontal, needs button 6/7)
            xdotool mousemove "$2" "$3"; case "$4" in up) B=4;; down) B=5;; left) B=6;; right) B=7;; *) B=5;; esac; N="${5:-3}"; for _i in $(seq 1 "$N"); do xdotool click "$B"; done; echo "scroll $4 x$N @ $2 $3" ;;
  pos)      xdotool getmouselocation 2>/dev/null ;;
  alive)    # раньше здесь был литерал :99 — на :97 он врал «:99 alive», хотя стек другой
            xdpyinfo >/dev/null 2>&1 && echo "$DISPLAY alive" || echo "$DISPLAY DOWN (нужен root: anydesk_kso.sh up)" ;;
  *) echo "usage: shot <label> | where | zoom <src> <WxH+X+Y> <out> [scale%] | click x y | dblclick x y | move x y | key <seq> | type <ascii> | paste <text> | pos | alive" ;;
esac
