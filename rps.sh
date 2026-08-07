#!/bin/bash
# rps.sh <local-ps1|-> [local-out] — run a PowerShell script ON the remote machine and bring the
# output back as UTF-8 TEXT. Solves the recurring "cp866 mojibake" problem: everything Windows
# prints (Cyrillic product names, certificate subjects, ЛК page text) arrives readable and greppable.
#
# Why a helper and not `ofd_ssh.sh 'powershell -Command ...'`:
#   1. OpenSSH on Windows hands stdout through the console code page (cp866) -> Cyrillic turns to
#      mojibake and greps stop matching. Here the script writes UTF-8 to a FILE, pulled with scp.
#   2. The ssh command line is parsed by cmd.exe FIRST: a -Command body containing  * > & |
#      gets eaten as cmd redirection (cost one debug round: `*>&1` -> PowerShell syntax error).
#      Shipping a script file removes that quoting layer entirely.
#   3. The script is uploaded with a UTF-8 BOM so PowerShell 5.1 does not decode Cyrillic literals
#      as ANSI (cp1251) garbage.
#
#   bash rps.sh ./probe.ps1 /tmp/out.txt        # script file
#   echo 'Get-Date' | bash rps.sh - /tmp/o.txt  # script on stdin
#
# Channel is parameterised the same way as cdp/: SSH= SCP= RHOST= RDIR=
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="${SSH:-/work/vnc_work/ofd_ssh.sh}"
SCP="${SCP:-/work/vnc_work/ofd_scp.sh}"
RHOST="${RHOST:-ofd}"
RDIR="${RDIR:-C:/Users/User}"

SRC="${1:?usage: rps.sh <local-ps1|-> [local-out]}"
OUT="${2:-/tmp/rps_out.txt}"
TAG="rps$(date +%H%M%S)$$"
TMP="/tmp/$TAG.ps1"
if [ "$SRC" = "-" ]; then cat > "$TMP"; else cat "$SRC" > "$TMP"; fi
# PowerShell 5.1 reads a BOM-less file as ANSI -> Cyrillic literals break. Prepend UTF-8 BOM.
printf '\xEF\xBB\xBF' | cat - "$TMP" > "$TMP.bom" && mv "$TMP.bom" "$TMP"

REMOTE_PS="$RDIR/$TAG.ps1"
REMOTE_OUT="$RDIR/$TAG.out"
WIN_PS="${REMOTE_PS//\//\\}"
WIN_OUT="${REMOTE_OUT//\//\\}"

# 🔴 T203, 2026-08-07. ЛЮБОЙ ВЫХОД ПО ОШИБКЕ ТЕПЕРЬ ТОЖЕ УБИРАЕТ ЗА СОБОЙ. Прежде `SCP_FAIL script`
# и `SCP_FAIL pull` делали голый `exit 1` — а неудачный scp прекрасно оставляет на той стороне
# ЧАСТИЧНО скопированный файл. Найдено фактом: на боевом SERVER-1S после такого обрыва лежал
# `rps085130866414.ps1` на 3767 байт, и в этих байтах был ПОДСТАВЛЕННЫЙ ПАРОЛЬ ИБ (обёртки
# *_pwrun.sh подставляют его в тело до отправки; строка с ним — семнадцатая). То есть путь
# «не долетело» оставлял секрет на чужой машине ровно так же, как когда-то путь «вызывающий умер»,
# который чинили в T194 §7.1. Здесь тот же ответ: уборка не зависит от того, чем кончился прогон.
cleanup_remote() {
  bash "$SSH" "cmd /c del \"$WIN_PS\" \"$WIN_OUT\"" >/dev/null 2>&1
  local left
  left=$(bash "$SSH" "cmd /c if exist \"$WIN_PS\" (echo LEFT) else (echo GONE)" 2>/dev/null | tr -d '\r' | grep -aE '^(LEFT|GONE)$' | head -1)
  rm -f "$TMP"
  echo "REMOTE_SCRIPT=${left:-UNKNOWN}"
  [ "${left:-}" = "LEFT" ] && echo "RPS_WARN: удалённый скрипт НЕ удалён: $WIN_PS — в нём могут быть подставленные пароли" >&2
  return 0
}

bash "$SCP" "$DIR/rps_run.ps1" "$RHOST:$RDIR/rps_run.ps1" >/dev/null 2>&1 || { echo "SCP_FAIL runner"; rm -f "$TMP"; exit 1; }
bash "$SCP" "$TMP" "$RHOST:$REMOTE_PS" >/dev/null 2>&1 || { echo "SCP_FAIL script"; cleanup_remote; exit 1; }
bash "$SSH" "powershell -NoProfile -ExecutionPolicy Bypass -File ${RDIR//\//\\}\\rps_run.ps1 -Script \"$WIN_PS\" -Out \"$WIN_OUT\"" 2>&1 | tail -8
bash "$SCP" "$RHOST:$REMOTE_OUT" "$OUT" >/dev/null 2>&1 || { echo "SCP_FAIL pull"; cleanup_remote; exit 1; }
# 🔴 Cleanup is now BELT AND BRACES (T194, 2026-08-07). rps_run.ps1 deletes the shipped script on
# the remote side the moment it finishes, so a caller that dies mid-run no longer strands a file
# that may hold SUBSTITUTED PASSWORDS (the kso pwrun wrappers put real creds into it). This client
# -side del still runs — it also removes the .out — and, unlike before, its result is VERIFIED and
# printed instead of being swallowed by >/dev/null. "I deleted it" is not evidence; the check is.
LEFT=$(cleanup_remote | sed -n 's/^REMOTE_SCRIPT=//p')
echo "LOCAL=$OUT BYTES=$(wc -c < "$OUT") REMOTE_SCRIPT=${LEFT:-UNKNOWN}"
exit 0
