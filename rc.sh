#!/bin/bash
# rc.sh — vnc_work_v2 remote-control driver (reliable targeting + verify + reconnect).
#
# WHY v2: the legacy AnyDesk/RustDesk drivers (anydesk_kso.sh, rustdesk/x99.sh)
# read a screenshot by eye and click guessed pixels (+-20..50 px -> missed
# buttons). rc.sh replaces "guess" with:
#   * template matching (vmatch.py) -> exact element centre + confidence; below
#     threshold it REPORTS A MISS instead of clicking wild.
#   * a haiku-eye crop/grid (veye.py) whose coordinates are computed, not eyeballed.
#   * verify-after-every-click (before/after regional diff); on a miss it re-locates
#     and retries once, never proceeding from an unverified state.
#   * reconnect (reconnect.py) preferring the stable RustDesk channel.
#
# SAFETY: rc.sh is DRY-RUN by default. It NEVER performs a real click/keystroke on
# a live machine unless RC_LIVE=1 is set explicitly. Tests run without RC_LIVE, so
# no live cash register / AnyDesk session is ever touched. Everything is driven off
# image FILES; only `click*`/`reconnect --run` translate a match into xdotool, and
# only under RC_LIVE=1.
#
# Runtime discovery (no hardcode): display, screens dir, click backend, target IDs
# and the calibration offset are all read from env with sane defaults; nothing is
# pinned to one cash register or user.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$DIR/lib"
PY="${RC_PYTHON:-python3}"

# --- runtime-discovered config (all overridable via env) --------------------
DISPLAY_="${RC_DISPLAY:-:99}"                 # X display carrying the viewer
SCREENS="${RC_SCREENS:-$DIR/screens}"         # where shots land
USER_="${RC_USER:-hgff}"                      # display owner (for root->runuser)
MIN_SCORE="${RC_MIN_SCORE:-0.80}"             # refuse-to-click threshold
LIVE="${RC_LIVE:-0}"                          # 1 = really click; else dry-run
OFFSET_FILE="$SCREENS/.offset"                # calibrated toolbar offset DX,DY
mkdir -p "$SCREENS" 2>/dev/null

log(){ printf '%s\n' "$*" >&2; }
die(){ log "rc: $*"; exit 3; }

# xdotool/scrot on the right display. Root -> runuser as the display owner;
# non-root -> direct (the agent runs as the owner). No hardcode beyond env.
X(){
  if [ "$(id -u)" = "0" ]; then
    runuser -u "$USER_" -- env -i HOME="/home/$USER_" PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISPLAY_" "$@"
  else
    env DISPLAY="$DISPLAY_" "$@"
  fi
}

# Capture one frame to $1. Pluggable via RC_SHOT_CMD (runtime-discovered capture
# backend: scrot here, but could be a scheduled-task pull like shot1.sh, or — in
# offline tests — a fixture copier). RC_SHOT_DEST is exported for the custom cmd.
_shot_to(){
  local dest="$1"
  if [ -n "${RC_SHOT_CMD:-}" ]; then
    RC_SHOT_DEST="$dest" bash -c "$RC_SHOT_CMD"
  else
    X scrot -o "$dest" 2>/dev/null
  fi
}

_read_offset(){ [ -r "$OFFSET_FILE" ] && cat "$OFFSET_FILE" || echo "0,0"; }

# scene defaults to the most recent shot if not given
_last_scene(){ ls -t "$SCREENS"/*.png 2>/dev/null | head -1; }

usage(){
  sed -n '1,32p' "$0"
  cat >&2 <<'EOF'

commands:
  shot <label>                         capture DISPLAY -> screens/<label>.png(+jpg)
  find <template> [scene]              template-match -> exact centre + score (JSON)
  crop <x,y,w,h> <out> [scale] [--grid]   haiku-eye crop (coords computed, not eyeballed)
  grid <out> [step]                    stamp a labelled coordinate ruler over last shot
  deproject <ox,oy> <scale> <px,py>    map a point read on a crop -> real screen pixel
  ocr <text> [scene]                   optional tesseract text->coord (degrades cleanly)
  click <x> <y>                        click (DRY-RUN unless RC_LIVE=1); applies offset
  click-template <template>            shot->find->click->VERIFY->retry-once (flagship)
  verify <before> <after> <x,y,w,h>    did the target region change? (exit 0=yes)
  calibrate <anchor> [expectX,Y]       measure toolbar offset -> screens/.offset
  classify [frame]                     session liveness: live | black | banner
  livecheck                            frozen-frame detector (viewer error dialog present?)
  reconnect [--run]                    print (or --run under RC_LIVE) the reconnect plan
  selftest                             run the offline fixture test

env: RC_DISPLAY RC_SCREENS RC_USER RC_MIN_SCORE RC_LIVE(=1 to really click)
     RC_AD_ID RC_RD_ID RC_PREFER(rustdesk|anydesk)
EOF
}

case "${1:-}" in
  shot)
    L="${2:-shot}"
    _shot_to "$SCREENS/$L.png" || die "capture failed on $DISPLAY_ (is the display up?)"
    command -v convert >/dev/null && convert "$SCREENS/$L.png" -quality 88 "$SCREENS/$L.jpg" 2>/dev/null
    echo "$SCREENS/$L.png"
    ;;

  find)
    T="${2:?need template}"; S="${3:-$(_last_scene)}"; [ -n "$S" ] || die "no scene"
    OFF="$(_read_offset)"
    "$PY" "$LIB/vmatch.py" find --scene "$S" --template "$T" \
        --min-score "$MIN_SCORE" --offset "$OFF" --json
    ;;

  crop)
    R="${2:?need x,y,w,h}"; O="${3:?need out}"; SC="${4:-3.0}"; shift 4 2>/dev/null || shift $#
    GRID=""; for a in "$@"; do [ "$a" = "--grid" ] && GRID="--grid"; done
    S="$(_last_scene)"; [ -n "$S" ] || die "no scene; run shot first"
    "$PY" "$LIB/veye.py" crop --scene "$S" --out "$O" --region "$R" --scale "$SC" $GRID --json
    ;;

  grid)
    O="${2:?need out}"; ST="${3:-100}"; S="$(_last_scene)"; [ -n "$S" ] || die "no scene"
    "$PY" "$LIB/veye.py" grid --scene "$S" --out "$O" --step "$ST" --json
    ;;

  deproject)
    "$PY" "$LIB/veye.py" deproject --origin "${2:?ox,oy}" --scale "${3:?scale}" --point "${4:?px,py}" --json
    ;;

  ocr)
    # ocr <text> [scene] [region X,Y,W,H] [scale]
    # 🔴 Region+scale matter: on a full 1920x1080 frame tesseract reads none of the small UI
    # captions, so a "not found" there is not evidence of absence. Crop to the area and scale 3x.
    TX="${2:?need text}"; S="${3:-$(_last_scene)}"; [ -n "$S" ] || die "no scene"
    RG="${4:-}"; SC="${5:-1.0}"
    if [ -n "$RG" ]; then
      "$PY" "$LIB/veye.py" ocr --scene "$S" --text "$TX" --region "$RG" --scale "$SC" --json
    else
      "$PY" "$LIB/veye.py" ocr --scene "$S" --text "$TX" --scale "$SC" --json
    fi
    ;;

  click)
    X_="${2:?need x}"; Y_="${3:?need y}"
    OFF="$(_read_offset)"; DX="${OFF%%,*}"; DY="${OFF##*,}"
    FX=$((X_ + DX)); FY=$((Y_ + DY))
    if [ "$LIVE" = "1" ]; then
      X xdotool mousemove "$FX" "$FY" click 1 && echo "clicked $FX $FY (offset $OFF)"
    else
      echo "DRY-RUN would click $FX $FY (offset $OFF); set RC_LIVE=1 to execute"
    fi
    ;;

  click-template)
    # flagship: shot -> find -> click -> verify-after -> retry-once. Never clicks
    # below threshold; never proceeds from an unverified state.
    T="${2:?need template}"
    attempt=1; ok=0
    while [ "$attempt" -le 2 ]; do
      _shot_to "$SCREENS/_ct_before.png" || die "capture failed"
      M=$("$PY" "$LIB/vmatch.py" find --scene "$SCREENS/_ct_before.png" --template "$T" \
            --min-score "$MIN_SCORE" --offset "$(_read_offset)" --json)
      echo "find[$attempt]: $M"
      FOUND=$(printf '%s' "$M" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("found"))')
      if [ "$FOUND" != "True" ]; then
        log "miss[$attempt]: below threshold ($MIN_SCORE) -> not clicking"; attempt=$((attempt+1)); continue
      fi
      read CX CY BX BY BW BH < <(printf '%s' "$M" | "$PY" -c \
        'import sys,json;d=json.load(sys.stdin);print(d["x"],d["y"],d["left"],d["top"],d["w"],d["h"])')
      if [ "$LIVE" = "1" ]; then
        X xdotool mousemove "$CX" "$CY" click 1
      else
        echo "DRY-RUN would click $CX $CY"
      fi
      sleep 0.4
      _shot_to "$SCREENS/_ct_after.png"
      V=$("$PY" "$LIB/vmatch.py" verify --before "$SCREENS/_ct_before.png" \
            --after "$SCREENS/_ct_after.png" --region "$BX,$BY,$BW,$BH" --json)
      echo "verify[$attempt]: $V"
      CHANGED=$(printf '%s' "$V" | "$PY" -c 'import sys,json;print(json.load(sys.stdin).get("changed"))')
      if [ "$LIVE" != "1" ]; then echo "(dry-run: verify is informational)"; ok=1; break; fi
      if [ "$CHANGED" = "True" ]; then ok=1; break; fi
      log "no change after click[$attempt] -> re-locate & retry"; attempt=$((attempt+1))
    done
    [ "$ok" = "1" ] && echo "click-template OK" || { echo "click-template FAILED (no verified click)"; exit 2; }
    ;;

  verify)
    "$PY" "$LIB/vmatch.py" verify --before "${2:?before}" --after "${3:?after}" --region "${4:?x,y,w,h}" --json
    ;;

  calibrate)
    A="${2:?need anchor template}"; EXP="${3:-}"; S="$(_last_scene)"; [ -n "$S" ] || die "no scene"
    if [ -n "$EXP" ]; then
      R=$("$PY" "$LIB/vmatch.py" calibrate --scene "$S" --anchor "$A" --expect "$EXP" --json)
    else
      R=$("$PY" "$LIB/vmatch.py" calibrate --scene "$S" --anchor "$A" --json)
    fi
    echo "$R"
    OFF=$(printf '%s' "$R" | "$PY" -c 'import sys,json
d=json.load(sys.stdin)
print("%d,%d"%tuple(d["offset"])) if d.get("ok") else print("")' )
    [ -n "$OFF" ] && { echo "$OFF" > "$OFFSET_FILE"; echo "saved offset $OFF -> $OFFSET_FILE"; }
    ;;

  livecheck)
    # Is the viewer showing the REAL remote screen right now, or a FROZEN last frame?
    # classify() only measures picture content -- a dead session leaves the last frame on :99 and
    # still scores "live". The give-away is the viewer's own modal: alongside the session window
    # ("<id>@<host> - Remote Desktop - RustDesk") a bare "RustDesk" dialog appears on disconnect.
    wins="$(DISPLAY="$RC_DISPLAY" xdotool search --name "." getwindowname %@ 2>/dev/null)"
    sess=0; dlg=0
    while IFS= read -r w; do
      case "$w" in
        *"Remote Desktop - RustDesk") sess=1 ;;
        "RustDesk") dlg=$((dlg+1)) ;;
      esac
    done <<< "$wins"
    printf '{"session_window":%s,"viewer_dialog":%s,"stale":%s}\n' \
      "$([ "$sess" = 1 ] && echo true || echo false)" \
      "$dlg" \
      "$([ "$dlg" -gt 0 ] && echo true || echo false)"
    [ "$dlg" -gt 0 ] && exit 1 || exit 0
    ;;

  classify)
    F="${2:-$(_last_scene)}"; [ -n "$F" ] || die "no frame"
    "$PY" "$LIB/reconnect.py" classify --frame "$F" ${RC_BANNER_TEMPLATE:+--banner-template "$RC_BANNER_TEMPLATE"} --json
    ;;

  reconnect)
    RUN=""; [ "${2:-}" = "--run" ] && RUN=1
    PREFER="${RC_PREFER:-rustdesk}"
    PLAN=$("$PY" "$LIB/reconnect.py" plan --prefer "$PREFER" \
             ${RC_AD_ID:+--ad-id "$RC_AD_ID"} ${RC_RD_ID:+--rd-id "$RC_RD_ID"} --json)
    echo "$PLAN"
    if [ -z "$RUN" ] || [ "$LIVE" != "1" ]; then
      echo "(dry-run: not executing; pass --run AND set RC_LIVE=1 to actually reconnect)"; exit 0
    fi
    # LIVE reconnect: walk the plan with backoff, verify liveness after each step.
    SCHED=$("$PY" "$LIB/reconnect.py" backoff --json)
    log "reconnect plan resolved; executing (RC_LIVE=1) — driver cmds relative to /work/vnc_work"
    echo "$SCHED"
    log "NOTE: rc.sh delegates the actual connect to the ORIGINAL drivers in /work/vnc_work; wire RC_AD_ID/RC_RD_ID and run those under dangerouslyDisableSandbox."
    ;;

  selftest)
    exec bash "$DIR/test/run_tests.sh"
    ;;

  ""|-h|--help|help) usage ;;
  *) die "unknown command: $1 (try: $0 help)" ;;
esac
