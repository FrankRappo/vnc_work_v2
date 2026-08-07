#!/bin/bash
# rps_paste.sh — выполнить команду PowerShell в СФОКУСИРОВАННОМ окне PS на кассе (RustDesk :99) и
# забрать stdout через буфер обмена. Надёжнее type-варианта: команду ВСТАВЛЯЕМ (paste), а не печатаем —
# xdotool type роняет спецсимволы (' + | > &) и кириллицу из-за раскладки; paste их сохраняет.
#
# Ключевые уроки ZFISCAL (почему именно так):
#  - PowerShell-обёртка: `& { "$NONCE"; CMD } 2>&1 | Out-String | clip` (НЕ `( CMD )` — в PS группировка
#    не держит несколько операторов; script-block `& { }` — держит). NONCE в НАЧАЛЕ вывода отсеивает
#    устаревший буфер (RustDesk двунаправленно синкает буфер и может вернуть старое значение).
#  - НЕ слать `ctrl+c` перед вставкой пейлоада-файла: в консоли он КОПИРУЕТ выделение и затирает буфер.
#  - Кириллица в командах — только base64/wildcard; в paste кириллица иногда доходит, иногда нет.
#  - Окно РМК-киоска ворует фокус → держи окно PS always-on-top (topmost_console.ps1) и кликай в его тело
#    (PSX/PSY) перед вставкой.
# Экспорт: PSX,PSY — точка клика по ТЕЛУ окна PS (не тайтл-бар, не скроллбар). WAIT — таймаут чтения.
set -u
export DISPLAY="${AD_DISPLAY:-:99}"
CMD="$1"; WAIT="${WAIT:-16}"; SYNC="${SYNC:-1.4}"
PSX="${PSX:-850}"; PSY="${PSY:-250}"
N="NZ$$_$(date +%s%N | tail -c 7)"
WRAPPED="& { \"$N\"; $CMD } 2>&1 | Out-String | clip"
xdotool mousemove "$PSX" "$PSY" click 1; sleep 0.3
xdotool key ctrl+c; sleep 0.2; xdotool key Escape; sleep 0.2   # сброс частичной строки/continuation (>>)
printf '%s' "$WRAPPED" | xclip -selection clipboard 2>/dev/null; sleep "$SYNC"
xdotool key ctrl+v; sleep 0.5
xdotool key Return
deadline=$(( $(date +%s) + WAIT )); out=""
while [ "$(date +%s)" -lt "$deadline" ]; do
  cur="$(xclip -o -selection clipboard 2>/dev/null | tr -d '\0')"
  case "$cur" in *"$N"*) if [ "${cur:0:3}" != "& {" ]; then out="$cur"; break; fi;; esac
  sleep 0.5
done
echo "----- remote output -----"; printf '%s\n' "$out" | sed "s/$N//"; echo "----- end -----"
