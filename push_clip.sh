#!/bin/bash
# push_clip.sh <local_file> <remote_path_win>  — ONE-SHOT file transfer to the cash register via the
# RustDesk clipboard SYNC (local->remote), not via cmd-paste chunking. Much faster/robust than push_raw
# for medium files: the whole base64 rides the local->remote clipboard sync in one go; we TYPE (not paste)
# a short reader invocation so the clipboard is never clobbered, then C:\kso\c2f.ps1 reads the clipboard
# and WriteAllBytes()s the exact bytes. Verifies sha256+length. Falls back message on mismatch.
#
# Prereq: C:\kso\c2f.ps1 present on the kiosk (bootstrap once). Elevated cmd FOCUSED at TB_X,TB_Y (export).
set -u
LOCAL="$1"; REMOTE="$2"
export DISPLAY="${AD_DISPLAY:-:99}"
TBX="${TB_X:-760}"; TBY="${TB_Y:-76}"
RUN="${RUN:-5}"          # seconds to let the remote reader run
RC=/work/kso/chat/remote_cmd.sh
LEN=$(stat -c%s "$LOCAL"); SHA=$(sha256sum "$LOCAL" | cut -d' ' -f1 | tr 'a-f' 'A-F')
B64=$(base64 -w0 "$LOCAL"); NB=${#B64}
# Auto-scale clipboard sync wait with payload size (наблюдение ZKSO2: 3s хватает лишь на мелочь;
# ~30КБ b64 рвётся при 3s, ок при 8s; ~90КБ — ~14s). База ≈ 3 + b64/8000, но не ниже явного $SYNC.
AUTO=$(( 3 + NB / 8000 )); [ "$AUTO" -lt 3 ] && AUTO=3
SYNC="${SYNC:-$AUTO}"; [ "$SYNC" -lt "$AUTO" ] && SYNC="$AUTO"
echo "[push_clip] $LOCAL -> $REMOTE bytes=$LEN b64=$NB sha=${SHA:0:16} sync=${SYNC}s"

# ── одна попытка передачи (clipboard->c2f.ps1) с заданным временем синка ──
attempt(){
  local s="$1"
  # 1) load the whole base64 onto the local :99 clipboard (RustDesk mirrors it to the remote)
  printf '%s' "$B64" | xclip -selection clipboard 2>/dev/null
  sleep "$s"
  # 2) focus cmd, clear the input line, then TYPE (never paste) the reader invocation
  xdotool mousemove "$TBX" "$TBY" click 1; sleep 0.35
  xdotool key Escape; sleep 0.2
  xdotool type --delay 22 "powershell -nop -ep bypass -f C:\\kso\\c2f.ps1 $REMOTE"
  sleep 0.3
  xdotool key Return
  sleep "$RUN"
  # 3) read back the reader's verdict (sha+len)
  WAIT=8 "$RC" "powershell -nop -c \"Get-Content 'C:\\kso\\c2f.out'\"" 2>/dev/null \
    | sed -n '/remote output/,/end -----/p' | grep -viE '^-----' | tr -d '\r'
}

# Попытка + авто-ретрай с удвоенным синком при несовпадении (частая причина — недосинк большого буфера).
OK=0
for s in "$SYNC" "$(( SYNC * 2 ))"; do
  OUT=$(attempt "$s")
  echo "[push_clip] remote verdict (sync=${s}s): $OUT"
  if printf '%s' "$OUT" | grep -q "$SHA" && printf '%s' "$OUT" | grep -q " $LEN"; then
    echo "[push_clip] OK (sha+len match)"; OK=1; break
  fi
  echo "[push_clip] MISMATCH — clipboard sync may have truncated; retrying with longer sync…"
done
echo "[push_clip] local  sha=$SHA len=$LEN"
[ "$OK" = 1 ] || echo "[push_clip] FAILED after retry — use push_raw.sh or raise SYNC manually"
