#!/bin/bash
# Coordinate-driving primitives for 1C-over-VNC sessions.

export DISPLAY="${IC_DISPLAY:-:98}"
IC_SCREEN_W="${IC_SCREEN_W:-1920}"
IC_SCREEN_H="${IC_SCREEN_H:-1080}"
IC_CDP_PORT="${IC_CDP_PORT:-9334}"
IC_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IC_SHOTS_DIR="${IC_SHOTS_DIR:-/tmp/1c_vnc_shots}"
IC_SHOT_N=0

ic_require_resolution() {
  local dim
  dim=$(DISPLAY="$DISPLAY" xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2}')
  if [ "$dim" != "${IC_SCREEN_W}x${IC_SCREEN_H}" ]; then
    echo "[X] DISPLAY $DISPLAY = '$dim', expected ${IC_SCREEN_W}x${IC_SCREEN_H}" >&2
    return 1
  fi
  echo "[ok] DISPLAY $DISPLAY = $dim"
}

ic_liveness() {
  if curl -s -m3 "http://127.0.0.1:${IC_CDP_PORT}/json/version" >/dev/null 2>&1; then
    echo "[ok] chromium/CDP ${IC_CDP_PORT} alive"
    return 0
  fi
  echo "[X] chromium/CDP ${IC_CDP_PORT} is down" >&2
  return 1
}

ic_win() { DISPLAY="$DISPLAY" xdotool search --class chromium 2>/dev/null | head -1; }

ic_focus() {
  local w
  w=$(ic_win)
  [ -n "$w" ] && DISPLAY="$DISPLAY" xdotool windowactivate --sync "$w" 2>/dev/null
  sleep 0.3
}

# A failed capture must never leave the PREVIOUS frame under the path we print: a plausible-looking
# but hours-old picture is read as "now" and clicked on by coordinates (kso-anydesk-stale-frame,
# 2026-08-05). So: delete first, shout on failure, and print the capture time next to the path.
ic_shot() {
  local label="${1:-shot}"
  IC_SHOT_N=$((IC_SHOT_N+1))
  local name
  name=$(printf '%02d_%s' "$IC_SHOT_N" "$label")
  mkdir -p "$IC_SHOTS_DIR"
  rm -f "$IC_SHOTS_DIR/$name.jpg"
  if ! DISPLAY="$DISPLAY" scrot -o "$IC_SHOTS_DIR/$name.jpg" 2>/dev/null || [ ! -s "$IC_SHOTS_DIR/$name.jpg" ]; then
    rm -f "$IC_SHOTS_DIR/$name.jpg"
    echo "SHOT_FAIL: no frame from DISPLAY=$DISPLAY (nothing left at $IC_SHOTS_DIR/$name.jpg)" >&2
    return 1
  fi
  echo "shot $(date '+%Y-%m-%d %H:%M:%S') DISPLAY=$DISPLAY" >&2
  echo "$IC_SHOTS_DIR/$name.jpg"
}

ic_click() {
  DISPLAY="$DISPLAY" xdotool mousemove "$1" "$2" 2>/dev/null
  sleep 0.15
  DISPLAY="$DISPLAY" xdotool click 1 2>/dev/null
  sleep "${3:-0.4}"
}

ic_dblclick() {
  DISPLAY="$DISPLAY" xdotool mousemove "$1" "$2" 2>/dev/null
  sleep 0.15
  DISPLAY="$DISPLAY" xdotool click --repeat 2 --delay 90 1 2>/dev/null
  sleep "${3:-0.6}"
}

ic_key() { DISPLAY="$DISPLAY" xdotool key "$@" 2>/dev/null; sleep 0.25; }
ic_type_ascii() { DISPLAY="$DISPLAY" xdotool type --delay 60 -- "$1" 2>/dev/null; sleep 0.3; }

ic_paste() {
  printf '%s' "$1" | DISPLAY="$DISPLAY" xclip -selection clipboard 2>/dev/null
  sleep 0.2
  DISPLAY="$DISPLAY" xdotool key ctrl+v 2>/dev/null
  sleep 0.4
}

ic_clear_field() {
  DISPLAY="$DISPLAY" xdotool key ctrl+a 2>/dev/null
  sleep 0.1
  DISPLAY="$DISPLAY" xdotool key Delete 2>/dev/null
  sleep 0.2
}
