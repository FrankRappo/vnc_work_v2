#!/bin/bash
# shot1.sh <label> — capture the cash's real session-1 screen (native 1024x768) via a scheduled
# task, pull the PNG to /work/vnc_work_v2-vm121-review/screens/<label>.png (+ .jpg), print the local jpg path.
# Reliable, pixel-accurate (unlike RustDesk's upscaled :99 frame). Run WITHOUT sandbox concerns
# for the ssh/scp parts (this script calls kso_ssh/kso_scp which need dangerouslyDisableSandbox
# when invoked by the agent — so call THIS script itself with dangerouslyDisableSandbox=true).
#
# 🔴 ЗАЛЕЖАВШИЙСЯ КАДР здесь опаснее, чем где-либо (грабля kso-anydesk-stale-frame, 05.08.2026):
# кадр приезжает с ЧУЖОЙ машины, и сорваться может каждое из трёх звеньев по отдельности —
#   а) задача съёмки на кассе не отработала → C:\kso\screen_capture.png остался ПРОШЛЫМ;
#   б) scp не забрал файл → локальный screens/<label>.png остался от прошлого вызова;
#   в) convert не собрал jpg → .jpg остался прошлым при свежем .png.
# Старая версия печатала путь к .jpg, если локальный .png ПРОСТО СУЩЕСТВОВАЛ, а возраст удалённого
# кадра вычисляла и выбрасывала в /dev/null. Теперь проверяются все три звена, и время съёмки
# (по часам КАССЫ) печатается явно. Путь — ПОСЛЕДНЯЯ строка (контракт `| tail -1`).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
L="${1:-shot1}"
OUT="${SHOT1_OUT:-$DIR/screens}"
MAXAGE="${SHOT1_MAX_AGE_SEC:-120}"     # старше стольких секунд = кадр на кассе НЕ обновился
SSH_CMD="${SHOT1_SSH:-$DIR/kso_ssh.sh}"   # переопределяемы (вместе с SHOT1_OUT), чтобы драйвер можно
SCP_CMD="${SHOT1_SCP:-$DIR/kso_scp.sh}"   # было проверить оффлайн-заглушками, не трогая кассу
mkdir -p "$OUT"

# 1. Локальные артефакты этого лейбла сносим ДО попытки — «кадр» не должен уцелеть от прошлого раза.
rm -f "$OUT/$L.png" "$OUT/$L.jpg" 2>/dev/null

# 2. Съёмка на кассе + ВОЗРАСТ полученного файла по часам кассы (раньше это значение выбрасывалось).
read -r -d '' PS <<'EOF'
$ErrorActionPreference="SilentlyContinue"
$action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File C:\kso\kso_capture_screen.ps1'
$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10)
$principal=New-ScheduledTaskPrincipal -UserId 'SCO_M210' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'KSOCapture' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName 'KSOCapture'
Start-Sleep -Seconds 2
$f=Get-Item C:\kso\screen_capture.png
if($f){ "KSOSHOT|{0}|{1:0}" -f $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), ((Get-Date)-$f.LastWriteTime).TotalSeconds }
else  { "KSOSHOT|NOFILE|-1" }
EOF
B64=$(printf '%s' "$PS" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
# фильтруем на стороне вывода: в контекст берём ТОЛЬКО маркерную строку, не весь CLIXML-шум
MARK=$(bash "$SSH_CMD" "powershell -NoProfile -EncodedCommand $B64" 2>/dev/null | grep -a -m1 '^KSOSHOT|')

if [ -z "$MARK" ]; then
  echo "SHOT1_FAIL: касса не ответила о кадре (ssh/задача съёмки) — свежего кадра НЕТ" >&2
  exit 1
fi
REMOTE_TS="$(printf '%s' "$MARK" | cut -d'|' -f2)"
REMOTE_AGE="$(printf '%s' "$MARK" | cut -d'|' -f3)"
if [ "$REMOTE_TS" = "NOFILE" ]; then
  echo "SHOT1_FAIL: на кассе нет C:\\kso\\screen_capture.png — задача KSOCapture не отработала" >&2
  exit 1
fi
if [ "$REMOTE_AGE" -gt "$MAXAGE" ] 2>/dev/null; then
  echo "SHOT1_FAIL: кадр НА КАССЕ не обновился: снят $REMOTE_TS (${REMOTE_AGE} с назад, лимит ${MAXAGE} с)." >&2
  echo "  Это ЗАЛЕЖАВШИЙСЯ кадр — тянуть его нельзя. Проверь задачу KSOCapture / сессию 1 на кассе." >&2
  echo "  Осознанно нужен старый кадр? SHOT1_MAX_AGE_SEC=99999 $0 $L" >&2
  exit 1
fi

# 3. Забрать файл.
bash "$SCP_CMD" kso:C:/kso/screen_capture.png "$OUT/$L.png" >/dev/null 2>&1
if [ ! -s "$OUT/$L.png" ]; then
  echo "SHOT1_FAIL: scp не привёз кадр в $OUT/$L.png (файла нет или он пуст)" >&2
  rm -f "$OUT/$L.png"; exit 1
fi

# 4. JPG. Не собрался — .jpg удаляем, чтобы не остался прошлый при свежем .png.
if ! convert "$OUT/$L.png" -quality 90 "$OUT/$L.jpg" 2>/dev/null; then
  rm -f "$OUT/$L.jpg"
  echo "SHOT1_WARN: convert не собрал JPG — отдаю PNG" >&2
  echo "снят на кассе $REMOTE_TS (${REMOTE_AGE} с назад), забран $(date '+%H:%M:%S'), size=$(stat -c%s "$OUT/$L.png")б"
  echo "$OUT/$L.png"; exit 0
fi
echo "снят на кассе $REMOTE_TS (${REMOTE_AGE} с назад), забран $(date '+%H:%M:%S'), size=$(stat -c%s "$OUT/$L.jpg")б"
echo "$OUT/$L.jpg"
