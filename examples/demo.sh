#!/bin/bash
# demo.sh — end-to-end walkthrough of vnc_work_v2 on the LOCAL fixture screen.
# No live machine, no clicks. Shows the exact "haiku-eye returns precise pixels"
# flow the main agent would drive. Run:  bash examples/demo.sh
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY=python3
F="$DIR/fixtures"
OUT="$DIR/screens"; mkdir -p "$OUT"
j(){ "$PY" -c 'import sys,json;print(json.dumps(json.load(sys.stdin),ensure_ascii=False,indent=2))'; }
say(){ printf '\n\033[1m# %s\033[0m\n' "$*"; }

"$PY" "$F/make_fixtures.py" >/dev/null
SCENE="$F/scene_before.png"       # stands in for a fresh `rc.sh shot`

say "1) TEMPLATE MATCH — exact centre, no LLM eyes at all (the strongest path)"
echo "   The main agent has a reference crop of the button (tmpl_pay.png) and asks:"
echo "   where is it, exactly?  vmatch returns the pixel + a confidence score."
"$PY" "$DIR/lib/vmatch.py" find --scene "$SCENE" --template "$F/tmpl_pay.png" --json | j
echo "   -> click that x,y. Below --min-score it would return found:false = a"
echo "      REPORTED MISS, never a wild click."

say "2) HAIKU-EYE — no template? Hand a cheap sub-agent a BIG crop on a ruler."
echo "   The main (expensive) agent never loads the image. It crops the zone and"
echo "   upscales 3x with a coordinate grid labelled in REAL screen pixels:"
CROP=$("$PY" "$DIR/lib/veye.py" crop --scene "$SCENE" --out "$OUT/crop_demo.png" \
        --region 480,440,320,140 --scale 3.0 --grid --json)
echo "$CROP" | j
echo "   -> the haiku sub-agent reads coords OFF THE RULER of $OUT/crop_demo.png"
echo "      and reports, say, the crop-local point (480,195). We map it back:"
ORIGIN=$(echo "$CROP" | "$PY" -c 'import sys,json;o=json.load(sys.stdin)["origin"];print("%d,%d"%tuple(o))')
"$PY" "$DIR/lib/veye.py" deproject --origin "$ORIGIN" --scale 3.0 --point 480,195 --json | j
echo "   deproject = arithmetic, not eyeballing -> kills the +-20..50px error."

say "3) CALIBRATE — measure the AnyDesk/RustDesk toolbar offset ONCE."
echo "   Find a fixed anchor (remote desktop corner) vs where it's expected:"
"$PY" "$DIR/lib/vmatch.py" calibrate --scene "$SCENE" --anchor "$F/tmpl_anchor.png" --expect 0,0 --json | j
echo "   -> feed the offset to every later find/click so the panel shift is"
echo "      corrected once, not guessed per click."

say "4) VERIFY-AFTER-ACTION — did the click actually change the target region?"
echo "   Compare before/after in the button's box. changed:false => it was a miss,"
echo "   so DON'T proceed from a wrong state:"
"$PY" "$DIR/lib/vmatch.py" verify --before "$F/scene_before.png" --after "$F/scene_after.png" \
      --region 520,470,240,70 --json | j

say "5) RECONNECT — is the session alive, and how to come back on the stable channel."
echo "   Liveness of a live frame vs a black/frozen frame vs a disconnect banner:"
for f in scene_before:live scene_black:frozen scene_banner:banner; do
  img="${f%%:*}"
  printf '   %-14s -> ' "$img"
  "$PY" "$DIR/lib/reconnect.py" classify --frame "$F/$img.png" \
        --banner-template "$F/tmpl_banner.png" --json | "$PY" -c 'import sys,json;d=json.load(sys.stdin);print("state=%s alive=%s sd=%s"%(d["state"],d["alive"],d["content_sd"]))'
done
echo "   Reconnect plan prefers the stable RustDesk channel over AnyDesk-free:"
"$PY" "$DIR/lib/reconnect.py" plan --prefer rustdesk --rd-id 243540605 --json | j

say "DONE — all offline. To act for real, the driver: RC_LIVE=1 bash rc.sh click-template <tmpl>"
