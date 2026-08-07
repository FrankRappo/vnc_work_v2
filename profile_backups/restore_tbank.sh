#!/usr/bin/env bash
# Восстановить залогиненную сессию Т-Бизнес из последнего бэкапа профиля.
# Запускать с dangerouslyDisableSandbox. После — открыть TigerVNC localhost:5901.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
# 🔴 T201: сами профили (416 МБ) НЕ переезжали — они данные, не код. По умолчанию ищем их рядом
# со скриптом, при отсутствии — в старом каталоге, пока он жив. Переложил профили — задай BKDIR.
BKDIR="${BKDIR:-$DIR}"
BK=$(ls -1dt "$BKDIR"/tbank_orvelix_* 2>/dev/null | head -1)
[ -n "$BK" ] || BK=$(ls -1dt /work/vnc_work/profile_backups/tbank_orvelix_* 2>/dev/null | head -1)
[ -n "$BK" ] || { echo "нет бэкапа"; exit 1; }
echo "[*] восстанавливаю из: $BK"
bash "$DIR/../vnc.sh" down 2>/dev/null || true
sleep 2
rsync -a --delete "$BK/" /tmp/vnc_work_profile/
echo "[*] профиль восстановлен -> поднимаю стек"
VNC_SOCKS=socks5://127.0.0.1:1080 bash "$DIR/../vnc.sh" up "https://business.tbank.ru/sme/dashboard"
echo "[OK] готово. Открой TigerVNC localhost:5901 (или vnc.sh viewer)."
