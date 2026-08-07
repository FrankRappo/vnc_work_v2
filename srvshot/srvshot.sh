#!/bin/bash
# srvshot.sh <local-out.png> — screenshot the REMOTE machine's own screen over SSH and fetch it.
#
# Why: it does not need a RustDesk/AnyDesk viewer at all. The viewer can silently die and leave a
# FROZEN last frame on :99 — rc.sh classify still calls that "live", so a stale picture gets read
# as the current screen (this cost a wrong conclusion once). A server-side capture is always now.
#
# 🔴 …but only if the capture is PROVEN to have happened (kso-anydesk-stale-frame, 2026-08-05).
# The previous version had the trap in two places at once:
#   * the remote C:\…\srvshot.png was never deleted before the run, so when the inner capture died
#     (locked session, no interactive session 1, task not started) the marker said SHOT=FAIL — and
#     the script pulled YESTERDAY'S remote png anyway and printed a cheerful LOCAL=… BYTES=…;
#   * the local <out.png> was never deleted before the pull, so a failed pull left the PREVIOUS
#     run's frame under the exact path the caller was about to read.
# Both ends are now cleared before capture, the SHOT= marker is required to carry a byte count,
# and the capture time (remote clock) is printed. The path stays the LAST line (`| tail -1`).
#
# Channel is parameterised like cdpq.sh: SSH= SCP= RHOST= RDIR=
#   bash srvshot.sh /tmp/screen.png
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="${SSH:-/work/vnc_work/ofd_ssh.sh}"
SCP="${SCP:-/work/vnc_work/ofd_scp.sh}"
RHOST="${RHOST:-ofd}"
RDIR="${RDIR:-C:/Users/User}"
OUT="${1:?usage: srvshot.sh <local-out.png> [focus-title-substring] [settle-sec]}"
FOCUS="${2:-}"
SETTLE="${3:-3}"
# 🔴 RUNAS (T194, 2026-08-07): учётка, под которой регистрируется задача /it. Пустая = сервер
# определит владельца интерактивной сессии сам (см. shot_run.ps1). Раньше было жёстко «User»,
# и на машине с другим логином (1С-сервер входит как «Админ») кадр не снимался вовсе, а
# выглядело это как таймаут съёмки.
RUNAS="${RUNAS:-}"
WIN_PNG="${RDIR//\//\\}\\srvshot.png"

# 1. Локальный артефакт сносим ДО попытки: если кадр не приедет, под этим путём не должно остаться
#    ничего — иначе следующий Read покажет прошлый экран как текущий.
rm -f "$OUT" 2>/dev/null

bash "$SCP" "$DIR/shot_inner.ps1" "$RHOST:$RDIR/srvshot_inner.ps1" >/dev/null 2>&1 || { echo "SRVSHOT_FAIL: не залит shot_inner.ps1 (канал SCP=$SCP RHOST=$RHOST)" >&2; exit 1; }
bash "$SCP" "$DIR/shot_run.ps1"   "$RHOST:$RDIR/srvshot_run.ps1"   >/dev/null 2>&1 || { echo "SRVSHOT_FAIL: не залит shot_run.ps1" >&2; exit 1; }

# 2. Съёмка. shot_run.ps1 сам сносит прошлый .png и .txt на удалённой стороне и ждёт маркер;
#    маркер SHOT=<байты> TIME=<часы удалённой машины> — единственное доказательство, что кадр НОВЫЙ.
RESP=$(bash "$SSH" "powershell -NoProfile -ExecutionPolicy Bypass -File ${RDIR//\//\\}\\srvshot_run.ps1 -Png $WIN_PNG -Inner ${RDIR//\//\\}\\srvshot_inner.ps1 -FocusTitle \"$FOCUS\" -SettleSec $SETTLE -RunAs \"$RUNAS\"" 2>&1 | grep -aE "^SHOT=|^WIN |^SHOT_RUNAS=" | head -20)
MARK=$(printf '%s\n' "$RESP" | grep -a -m1 '^SHOT=')
printf '%s\n' "$RESP" | grep -a '^WIN ' | head -12

BYTES=$(printf '%s' "$MARK" | sed -n 's/^SHOT=\([0-9][0-9]*\).*/\1/p')
RTIME=$(printf '%s' "$MARK" | sed -n 's/.*TIME=\([0-9:_-]*\).*/\1/p')
if [ -z "$MARK" ]; then
  echo "SRVSHOT_FAIL: удалённая сторона не прислала маркер SHOT= — съёмка НЕ состоялась (сессия 1 жива? задача SRVSHOT?)" >&2
  echo "  ответ: $(printf '%s' "$RESP" | head -3)" >&2
  exit 1
fi
if [ -z "$BYTES" ]; then
  echo "SRVSHOT_FAIL: маркер '$MARK' — кадр на удалённой машине НЕ снят. Старый кадр НЕ тянем." >&2
  exit 1
fi

# 3. Забрать. Пустой/непривезённый файл — провал, и под путём OUT ничего не остаётся.
bash "$SCP" "$RHOST:$RDIR/srvshot.png" "$OUT" >/dev/null 2>&1 || { echo "SRVSHOT_FAIL: scp не привёз кадр в $OUT" >&2; rm -f "$OUT"; exit 1; }
if [ ! -s "$OUT" ]; then
  echo "SRVSHOT_FAIL: $OUT пуст после scp" >&2; rm -f "$OUT"; exit 1
fi
echo "снят на удалённой машине ${RTIME:-?} (${BYTES}б), забран $(date '+%Y-%m-%d %H:%M:%S'), локально $(wc -c < "$OUT")б"
echo "$OUT"
