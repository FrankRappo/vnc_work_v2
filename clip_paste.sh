#!/bin/bash
# clip_paste.sh — RELIABLE remote text input (incl. Cyrillic) for a RustDesk/AnyDesk
# viewer running on an Xvfb :99 display. Pastes via the CLIPBOARD, never char-by-char.
#
# WHY: xdotool `type` of Cyrillic over a remote-desktop viewer is unreliable — the
# viewer forwards keysyms/keycodes that the remote Windows layout does not map, so
# Russian text arrives as 1 char / garbage (this exact blocker stalled task T47).
# The fix, proven live on 2026-07-23 against DESKTOP-VGVHEOU (1C server) via RustDesk:
#   1. set the LOCAL X clipboard (xclip) — full UTF-8 Cyrillic survives intact;
#   2. let the viewer sync the clipboard to the remote OS (needs a short wait +
#      the viewer window focused);
#   3. send Ctrl+V — a plain ASCII keystroke the viewer forwards correctly.
# Verified: a 55-char Cyrillic string ("Проверка_Кириллица…_ЖилетСигнальный") pasted
# whole into a remote field, no mojibake. See FIELD_NOTES.md.
#
# Keyboard-focus caveat (FIELD_NOTES #1): the viewer window needs a REAL CLICK to take
# keyboard focus on :99/fluxbox — `windowactivate` alone is not enough. So pass the
# target field's screen coords and this helper clicks there first (focus + field focus
# in one), then pastes.
#
# SAFETY: like rc.sh, this is DRY-RUN unless RC_LIVE=1. Dry-run prints the plan and
# sets the clipboard but performs NO click/keystroke on the live machine.
#
# Usage:
#   RC_LIVE=1 clip_paste.sh "<utf8 text>" [x,y]        # click x,y to focus, then paste
#   RC_LIVE=1 clip_paste.sh --replace "<text>" x,y      # Ctrl+A first (overwrite field)
#   RC_LIVE=1 clip_paste.sh --enter   "<text>" x,y      # press Enter after paste
#   clip_paste.sh --set-only "<text>"                   # only load local clipboard
#
# Env: RC_DISPLAY(:99) RC_WIN(auto: window whose name matches RC_WIN_MATCH)
#      RC_WIN_MATCH('Remote Desktop|RustDesk|AnyDesk') RC_SYNC_MS(700) RC_LIVE(0)
set -u

DISPLAY_="${RC_DISPLAY:-:99}"; export DISPLAY="$DISPLAY_"
WIN_MATCH="${RC_WIN_MATCH:-Remote Desktop|RustDesk|AnyDesk}"
SYNC_MS="${RC_SYNC_MS:-700}"
LIVE="${RC_LIVE:-0}"
log(){ printf '%s\n' "$*" >&2; }
die(){ log "clip_paste: $*"; exit 3; }
command -v xclip  >/dev/null || die "xclip not found"
command -v xdotool>/dev/null || die "xdotool not found"

REPLACE=0; ENTER=0; SETONLY=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --replace)  REPLACE=1;;
    --enter)    ENTER=1;;
    --set-only) SETONLY=1;;
    *) die "unknown flag $1";;
  esac; shift
done
TEXT="${1:-}"; CLICK="${2:-}"
[ -n "$TEXT" ] || die "no text given"

# 1) load LOCAL clipboard (both selections for good measure)
printf '%s' "$TEXT" | xclip -selection clipboard
printf '%s' "$TEXT" | xclip -selection primary 2>/dev/null
GOT="$(xclip -selection clipboard -o 2>/dev/null)"
[ "$GOT" = "$TEXT" ] || die "local clipboard mismatch after set"
log "clip set (${#TEXT} chars)"
[ "$SETONLY" = 1 ] && { log "set-only done"; exit 0; }

# discover the viewer window: try each pattern, pick the LARGEST-area match
# (the real remote-desktop viewer is fullscreen; RustDesk also has tiny helper windows).
# NB: xdotool --name takes ONE regex and mishandles '|'-alternation with spaces, so we
# iterate patterns instead of OR-ing them.
WIN="${RC_WIN:-}"
if [ -z "$WIN" ]; then
  IFS='|' read -r -a PATS <<< "$WIN_MATCH"
  best=""; bestarea=0
  for p in "${PATS[@]}"; do
    for w in $(xdotool search --name "$p" 2>/dev/null); do
      g="$(xdotool getwindowgeometry "$w" 2>/dev/null | grep -oE '[0-9]+x[0-9]+' | tail -1)"
      [ -n "$g" ] || continue
      area=$(( ${g%x*} * ${g#*x} ))
      if [ "$area" -gt "$bestarea" ]; then bestarea="$area"; best="$w"; fi
    done
  done
  WIN="$best"
fi
[ -n "$WIN" ] || die "viewer window not found (RC_WIN_MATCH=$WIN_MATCH)"
log "viewer win=$WIN  live=$LIVE"

plan(){ log "PLAN: $*"; }
run(){ if [ "$LIVE" = 1 ]; then eval "$@"; else plan "$@"; fi; }

# 2) focus viewer + optional real click on target field (keyboard focus)
run "xdotool windowactivate $WIN"; sleep 0.25
if [ -n "$CLICK" ]; then
  X="${CLICK%,*}"; Y="${CLICK#*,}"
  run "xdotool mousemove $X $Y click 1"; sleep 0.35
fi
# 3) let the viewer sync the clipboard to the remote OS
sleep "$(awk "BEGIN{print $SYNC_MS/1000}")"
# 4) optional select-all (overwrite), then paste
if [ "$REPLACE" = 1 ]; then run "xdotool key --clearmodifiers ctrl+a"; sleep 0.15; fi
run "xdotool key --clearmodifiers ctrl+v"; sleep 0.35
if [ "$ENTER" = 1 ]; then run "xdotool key --clearmodifiers Return"; fi
log "paste ${LIVE:+done}"
[ "$LIVE" = 1 ] && log "DONE (live)" || log "DRY-RUN (set RC_LIVE=1 to perform)"
exit 0
