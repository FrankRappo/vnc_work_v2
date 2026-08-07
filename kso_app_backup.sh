#!/bin/bash
# kso_app_backup.sh — полный ЛОКАЛЬНЫЙ бэкап приложения КСО (без 1С-базы).
# Деплоит kso_app_backup.ps1 на кассу, архивирует C:\kso (без node_modules/логов/старых бэкапов),
# стягивает архив к нам в /work/kso/backups/ и проверяет содержимое.
#
# Использование:  bash /work/vnc_work_v2-vm121-review/kso_app_backup.sh [dest_dir]
#   dest_dir по умолчанию /work/kso/backups
# 🔴 Запускать с dangerouslyDisableSandbox — внутри ssh/scp к кассе (песочница рубит сигналом 16).
# Read-only относительно кассы: только читает файлы, кассе/смене/фискалу не мешает.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="${1:-/work/kso/backups}"
TS=$(date +%Y%m%d_%H%M)
mkdir -p "$DEST"

echo "[1/5] заливаю архиватор на кассу..."
bash "$DIR/kso_scp.sh" "$DIR/kso_app_backup.ps1" 'kso:C:/kso/_app_backup.ps1' >/dev/null || { echo "SCP-PUSH-FAIL"; exit 1; }

echo "[2/5] архивирую C:\\kso на кассе..."
OUT=$(bash "$DIR/kso_ssh.sh" 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\kso\_app_backup.ps1' 2>&1)
echo "$OUT" | grep -E "BACKUP_ZIP=|SIZE_MB=|CHECK "
ZIP=$(echo "$OUT" | grep -oE 'BACKUP_ZIP=C:\\kso\\[^ ]+\.zip' | head -1 | cut -d= -f2 | tr '\\' '/')
[ -z "$ZIP" ] && { echo "FATAL: не получил путь архива от кассы. Вывод:"; echo "$OUT" | tail -5; exit 1; }

echo "[3/5] стягиваю архив к нам..."
LOCAL="$DEST/full_kso_app_${TS}.zip"
bash "$DIR/kso_scp.sh" "kso:$ZIP" "$LOCAL" >/dev/null || { echo "SCP-PULL-FAIL"; exit 1; }

echo "[4/5] проверка локально:"
ls -la "$LOCAL"; sha256sum "$LOCAL"
echo "  ключевое в архиве:"; unzip -l "$LOCAL" 2>/dev/null | grep -iE "ksoapp/dist|electron|\.epf|close_shift|open_shift|exchange_share" | head -6
NM=$(unzip -l "$LOCAL" 2>/dev/null | grep -c node_modules)
echo "  node_modules в архиве (должно быть 0): $NM"

# 🔴 Правило владельца 29.07.2026 (workflow §21): копия архива ОСТАЁТСЯ и на самой кассе —
# если канал ляжет или наша VM умрёт, точка отката должна быть на кассе. Раньше архив здесь удалялся.
# KEEP_ON_CASH=0 — вернуть прежнее поведение (удалять).
KEEP_ON_CASH="${KEEP_ON_CASH:-1}"
if [ "$KEEP_ON_CASH" = "1" ]; then
  echo "[5/5] оставляю копию на кассе (C:\\kso\\backups) и прибираю temp..."
  KEEP="C:/kso/backups/full_kso_app_${TS}.zip"
  ZIPW="${ZIP//\//\\}"; KEEPW="${KEEP//\//\\}"
  # 🔴 без кавычек вокруг путей и отдельными вызовами: цепочка "if not exist ... & move ..." в одной
  # ssh-команде молча не срабатывала (30.07: архив оставался в корне C:\kso).
  bash "$DIR/kso_ssh.sh" "if not exist C:\\kso\\backups mkdir C:\\kso\\backups" >/dev/null 2>&1
  bash "$DIR/kso_ssh.sh" "move /Y $ZIPW $KEEPW" 2>&1 | tail -1
  bash "$DIR/kso_ssh.sh" "del C:\\kso\\_app_backup.ps1 2>nul" >/dev/null 2>&1
  echo "  копия на кассе: ${KEEP//\//\\}"
  bash "$DIR/kso_ssh.sh" "dir /-c \"${KEEP//\//\\}\"" 2>/dev/null | grep -iE "full_kso_app|File Not Found|не найден" | head -2
else
  echo "[5/5] прибираю temp на кассе (KEEP_ON_CASH=0, копия на кассе НЕ остаётся)..."
  bash "$DIR/kso_ssh.sh" "del \"${ZIP//\//\\}\" 2>nul & del C:\\kso\\_app_backup.ps1 2>nul" >/dev/null 2>&1
fi
echo "DONE -> $LOCAL"
