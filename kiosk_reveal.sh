#!/bin/bash
# kiosk_reveal.sh — на КСО-кассе (RustDesk :99) Electron-киоск часто перекрывает cmd/1С-окна.
# Наблюдение 2026-07-02: киоск НЕ строго always-on-top — Win+D (Show Desktop) сворачивает ВСЁ,
# включая киоск, и открывает рабочий стол + таскбар. После этого окна поднимаются кликом по
# кнопке в таскбаре (если у приложения несколько окон — сначала показывается группа превью,
# нужен ВТОРОЙ клик по нужному превью).
#
# Использование:
#   kiosk_reveal.sh desktop        — Win+D (показать рабочий стол; повторный вызов вернёт окна)
#   kiosk_reveal.sh cmd            — Win+D, затем клик по иконке cmd в таскбаре (показывает превью-группу)
#   kiosk_reveal.sh focus-cmd      — вернуть фокус клавиатуры в plain-cmd (таскбар-группа cmd → превью
#                                    «Командная строка»); НУЖНО после кликов по превью/иконкам (иначе
#                                    xdotool type уходит в никуда, clipboard-readback пуст). Проверено ZFIX-PAY.
#   kiosk_reveal.sh restore-kiosk  — поднять киоск на передний план fullscreen (клик по его иконке)
#   kiosk_reveal.sh taskbar        — подсказка по X-координатам иконок таскбара (этот киоск)
#
# ГЕОМЕТРИЯ (портретная касса 1080x1920 в кадре :99 1920x1080):
#   удалённый экран отмасштабирован по высоте: scale = 1080/1920 = 0.5625 → ширина ≈ 607px,
#   центрирован → занимает X≈[656..1263], Y=[0..1067] кадра :99. Таскбар — снизу, Y≈1070.
#   Иконки таскбара (Y≈1070), нативные :99, СВЕРЕНО 2026-07-03:
#     Пуск=669 Поиск=696 Задачи=726 Edge=753 Проводник=780 cmd=807 1С=835 RustDesk=863
#     Electron/киоск=890 IE=918   (проверять скрином+зумом; X сдвигается при др. наборе окон)
#
# КАВЕАТЫ (ZFIX-PAY 2026-07-03), см. память kso-rustdesk-cmd-focus:
#   * После кликов по таскбару/превью ВВОД (xdotool type) не доходит до cmd — потерян фокус клавиатуры
#     RustDesk-окна на :99 (клики при этом работают). Лечит `focus-cmd` (клик тайтл-бара НЕ хватает).
#   * Киоск может быть ELEVATED electron (держит :9100 bridge) — его окно нельзя AppActivate из medium
#     (UIPI→False), но ТАСКБАР-клик (restore-kiosk) поднимает. Non-elevated дубль electron снимается
#     обычным `taskkill /F /IM electron.exe`; мост на elevated при этом жив (проверять /hs/kso/v1/health).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
export DISPLAY="${AD_DISPLAY:-:99}"
Y_TB="${Y_TB:-1070}"
X_CMD="${X_CMD:-807}"
X_KIOSK="${X_KIOSK:-890}"
X_CMD_PREVIEW="${X_CMD_PREVIEW:-985}"   # превью «Командная строка» (правое из группы консолей)
Y_PREVIEW="${Y_PREVIEW:-990}"
SCREENS="${AD_SCREENS:-$DIR/screens}"

# 🔴 через shotlib: провал съёмки — громкий SHOT_FAIL и НЕТ старого кадра на месте (kso-anydesk-stale-frame)
. "$(cd "$(dirname "$0")" && pwd)/shotlib.sh"
shot(){ shot_guarded "${1:-kr}" "$SCREENS" "$DISPLAY"; }

case "${1:-}" in
  desktop)      xdotool key --clearmodifiers super+d; sleep 1.2; shot kr_desktop ;;
  cmd)          xdotool key --clearmodifiers super+d; sleep 1.2
                xdotool mousemove "$X_CMD" "$Y_TB" click 1; sleep 1.2
                echo "[i] если открылась группа превью cmd — кликни нужное превью (обычно ~y=990);"
                echo "    напр.: xdotool mousemove $X_CMD_PREVIEW $Y_PREVIEW click 1"; shot kr_cmd ;;
  focus-cmd)    xdotool mousemove "$X_CMD" "$Y_TB" click 1; sleep 1.3
                xdotool mousemove "$X_CMD_PREVIEW" "$Y_PREVIEW" click 1; sleep 1.0
                echo "[i] plain-cmd в фокусе; проверь: printf mark|xclip -selection clipboard; xdotool type 'echo OK|clip'; xdotool key Return; xclip -o" ;;
  restore-kiosk) xdotool mousemove "$X_KIOSK" "$Y_TB" click 1; sleep 1.5; shot kr_kiosk ;;
  taskbar)      echo "Y_TB=$Y_TB  Пуск=669 Поиск=696 Задачи=726 Edge=753 Проводник=780 cmd=$X_CMD 1С=835 RustDesk=863 Electron=$X_KIOSK IE=918" ;;
  *) echo "usage: kiosk_reveal.sh desktop|cmd|focus-cmd|restore-kiosk|taskbar" ;;
esac
