#!/bin/bash
# connect.sh — поднять RustDesk на :99 и подключиться к удалённой машине через НАШ сервер.
# ID цели — первым аргументом; без аргумента по умолчанию касса (243540605).
# Запускать ОТ ROOT и с dangerouslyDisableSandbox (песочница рубит долгие процессы сигналом 16).
#   bash /work/vnc_work_v2-vm121-review/rustdesk/connect.sh <ID>     # напр. 2512413 — клиент ZennoLab
# Пароль кассы запомнен в клиенте (галка "Remember") → обычно коннект без запроса пароля.
# Если всё же спросит пароль: bash x99.sh type '<пароль из /work/kso/chat/rustdesk_kassa.md>'; bash x99.sh key Return
set -u
DISP=:99; RT=/tmp/xrt99; PORT=5902
TARGET_ID=${1:-243540605}
# runuser lives in /sbin, which sudo's secure_path strips -> resolve an absolute path once
# (bare `runuser` fails with "command not found" under sudo). Fallback keeps old behaviour.
RUNUSER="$(command -v runuser 2>/dev/null || echo /sbin/runuser)"
mkdir -p "$RT"; chown hgff:hgff "$RT" 2>/dev/null
U(){ "$RUNUSER" -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" "$@"; }
RD(){ setsid "$RUNUSER" -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" XDG_RUNTIME_DIR="$RT" "$@" >>/tmp/rustdesk_kso.log 2>&1 </dev/null & }

# 1. Xvfb + fluxbox
if ! U xdpyinfo >/dev/null 2>&1; then
  "$RUNUSER" -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin Xvfb "$DISP" -screen 0 1920x1080x24 -nolisten tcp >>/tmp/rustdesk_kso.log 2>&1 &
  sleep 2; U fluxbox >>/tmp/rustdesk_kso.log 2>&1 & sleep 1
fi
# 2. x11vnc (просмотр человеком на localhost:5902)
pgrep -f "x11vnc.*-rfbport $PORT" >/dev/null || U x11vnc -display "$DISP" -rfbport "$PORT" -nopw -forever -shared -quiet >>/tmp/rustdesk_kso.log 2>&1 &
sleep 1
# 3. сервис + GUI RustDesk (читает /home/hgff/.config/rustdesk/RustDesk2.toml — наш сервер уже прописан)
pgrep -f 'rustdesk --service' >/dev/null || { RD rustdesk --service; sleep 3; }
pgrep -x rustdesk >/dev/null 2>&1 || { RD rustdesk; sleep 8; }
# 4. коннект к цели
RD rustdesk --connect "$TARGET_ID"
sleep 10
# 5. скрин — через общий защищённый снимок (грабля kso-anydesk-stale-frame): если съёмка не удалась,
#    /tmp/x99.jpg от ПРОШЛОГО коннекта не должен остаться и сойти за подтверждение этого.
. "$(cd "$(dirname "$0")/.." && pwd)/shotlib.sh"
if shot_guarded x99 /tmp "$DISP" U; then
  echo "connect.sh → цель ID $TARGET_ID. Скрин выше (снят только что). Если спросит пароль — x99.sh type '<pw>'; x99.sh key Return."
else
  echo "connect.sh → цель ID $TARGET_ID ЗАПУЩЕН, но КАДР НЕ СНЯТ — подтверждения коннекта нет." >&2
  echo "  Проверить вручную: bash $(dirname "$0")/x99.sh shot ; bash $(dirname "$0")/x99.sh wins" >&2
  exit 1
fi
