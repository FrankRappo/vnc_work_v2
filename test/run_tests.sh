#!/bin/bash
# run_tests.sh — offline self-test for vnc_work_v2.
#
# Regenerates the synthetic fixtures, runs the unit tests, then exercises the
# rc.sh shell wiring in DRY-RUN so we prove the driver composes shot/find/verify/
# reconnect WITHOUT ever performing a live click. No network, no live machine.
set -u
DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY="${RC_PYTHON:-python3}"
fail=0
say(){ printf '\n=== %s ===\n' "$*"; }

say "0. fixtures"
"$PY" "$DIR/fixtures/make_fixtures.py" || { echo "fixture gen FAILED"; exit 1; }

say "1. unit tests (vmatch + veye + reconnect)"
"$PY" "$DIR/test/test_core.py" || fail=1

say "2. rc.sh dry-run wiring (must NOT click live)"
# force dry-run explicitly; operate on the fixture as the 'last shot'
export RC_SCREENS="$DIR/fixtures" RC_LIVE=0 RC_MIN_SCORE=0.80
# point find/verify at fixtures directly
echo "-- find --"
"$PY" "$DIR/lib/vmatch.py" find --scene "$DIR/fixtures/scene_before.png" \
      --template "$DIR/fixtures/tmpl_pay.png" --min-score 0.8 --json || fail=1

echo "-- click dry-run (must say DRY-RUN, must NOT execute) --"
OUT=$(bash "$DIR/rc.sh" click 640 505 2>&1)
echo "$OUT"
echo "$OUT" | grep -q "DRY-RUN" || { echo "SAFETY FAIL: click did not dry-run!"; fail=1; }

echo "-- reconnect plan dry-run --"
OUT=$(RC_PREFER=rustdesk RC_RD_ID=123456789 bash "$DIR/rc.sh" reconnect 2>&1)
echo "$OUT"
echo "$OUT" | grep -q "dry-run" || { echo "SAFETY FAIL: reconnect not dry-run!"; fail=1; }
echo "$OUT" | grep -q "rustdesk" || { echo "reconnect plan missing rustdesk"; fail=1; }

echo "-- click-template end-to-end (offline, fixture-fed capture, verify-after-click) --"
# Feed the flagship a capture backend that returns scene_before on the 1st shot
# and scene_after on the 2nd, so the before/after verify sees the button change.
CNT="$DIR/fixtures/.ctcnt"; echo 0 > "$CNT"
export RC_SHOT_CMD='n=$(cat '"$CNT"'); n=$((n+1)); echo $n > '"$CNT"'; \
  if [ "$n" -le 1 ]; then cp '"$DIR"'/fixtures/scene_before.png "$RC_SHOT_DEST"; \
  else cp '"$DIR"'/fixtures/scene_after.png "$RC_SHOT_DEST"; fi'
OUT=$(RC_LIVE=0 bash "$DIR/rc.sh" click-template "$DIR/fixtures/tmpl_pay.png" 2>&1)
echo "$OUT"
echo "$OUT" | grep -q '"found": true' || { echo "click-template did not find target"; fail=1; }
echo "$OUT" | grep -q "DRY-RUN would click 640 505" || { echo "click-template wrong coords/not dry-run"; fail=1; }
echo "$OUT" | grep -q '"changed": true' || { echo "click-template verify did not confirm change"; fail=1; }
echo "$OUT" | grep -q "click-template OK" || { echo "click-template did not report OK"; fail=1; }
unset RC_SHOT_CMD; rm -f "$CNT"

echo "-- classify fixtures --"
for f in scene_before:live scene_black:black; do
  img="${f%%:*}"; want="${f##*:}"
  got=$("$PY" "$DIR/lib/reconnect.py" classify --frame "$DIR/fixtures/$img.png" --json | "$PY" -c 'import sys,json;print(json.load(sys.stdin)["state"])')
  echo "$img -> $got (want $want)"
  [ "$got" = "$want" ] || { echo "classify mismatch"; fail=1; }
done

say "RESULT"
if [ "$fail" = "0" ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit $fail
