#!/usr/bin/env python3
"""
vmatch.py — reliable visual targeting + verify engine for vnc_work_v2.

Replaces "guess coordinates by eye" (the ±20–50 px blind-click problem) with
deterministic template matching on the actual captured frame:

  * find      — locate a template image inside a scene screenshot (multi-scale,
                normalised cross-correlation) and return the click point + a
                confidence score. The caller refuses to click below a threshold,
                so a bad match becomes a *reported miss*, never a wild click.
  * verify    — compare a before/after screenshot pair (optionally within the
                target region) and decide whether the action actually changed
                the screen — the "verify-after-every-action" gate.
  * calibrate — locate a known anchor template (e.g. the top-left corner of the
                remote desktop, or a fixed toolbar landmark) and derive the
                content-origin offset, so the AnyDesk/RustDesk toolbar shift is
                measured once instead of guessed.

Pure OpenCV + numpy. No network, no clicks, no dependency on any live machine.
Everything here operates on image *files*; the shell layer (rc.sh) decides when
(and whether) to translate a match into a real xdotool click.

CLI (all subcommands accept --json for machine-readable output):

  vmatch.py find      --scene S.png --template T.png [--min-score 0.80]
                      [--scales 1.0,0.9,1.1] [--offset DX,DY] [--edges] [--json]
  vmatch.py verify    --before B.png --after A.png [--region X,Y,W,H]
                      [--min-change 0.01] [--json]
  vmatch.py calibrate --scene S.png --anchor A.png [--expect X,Y]
                      [--min-score 0.80] [--json]

Exit codes: 0 = ok / found / verified-changed, 2 = not found / below threshold,
3 = bad usage. (verify uses 0 = changed, 2 = unchanged so it composes in shell.)
"""
import argparse
import json
import sys

try:
    import cv2
    import numpy as np
except Exception as exc:  # pragma: no cover - environment guard
    sys.stderr.write(
        "vmatch: OpenCV/numpy required (python3 -c 'import cv2,numpy'): %s\n" % exc
    )
    sys.exit(4)


def _imread(path, gray=True):
    flag = cv2.IMREAD_GRAYSCALE if gray else cv2.IMREAD_COLOR
    img = cv2.imread(path, flag)
    if img is None:
        raise FileNotFoundError("cannot read image: %s" % path)
    return img


def _parse_floats(s):
    return [float(x) for x in s.split(",") if x.strip() != ""]


def _parse_ints(s):
    return [int(round(float(x))) for x in s.split(",") if x.strip() != ""]


def _match_one(scene, templ, method=cv2.TM_CCOEFF_NORMED):
    """Single-scale match. Returns (score, top_left_x, top_left_y, w, h)."""
    th, tw = templ.shape[:2]
    sh, sw = scene.shape[:2]
    if th > sh or tw > sw:
        return None
    res = cv2.matchTemplate(scene, templ, method)
    _min_v, max_v, _min_l, max_l = cv2.minMaxLoc(res)
    return float(max_v), int(max_l[0]), int(max_l[1]), int(tw), int(th)


def find(scene_path, templ_path, min_score=0.80, scales=None, offset=(0, 0),
         use_edges=False):
    """
    Multi-scale template match. Returns a dict describing the best hit.

    Robustness knobs:
      * multi-scale — the remote frame may be up/down-scaled (RustDesk upscales
        the :99 frame; AnyDesk fits-to-window), so we try several template scales
        and keep the best-scoring one.
      * --edges — match on Canny edges instead of raw grayscale, which survives
        brightness/theme shifts (kiosk day/night, JPEG recompression).
    """
    scene = _imread(scene_path, gray=True)
    templ = _imread(templ_path, gray=True)
    if scales is None:
        scales = [1.0, 0.9, 0.8, 1.1, 1.25, 0.67, 1.5]

    def prep(img):
        if not use_edges:
            return img
        return cv2.Canny(img, 60, 180)

    scene_p = prep(scene)
    best = None  # (score, cx, cy, left, top, w, h, scale)
    for sc in scales:
        if sc <= 0:
            continue
        if abs(sc - 1.0) < 1e-9:
            t = templ
        else:
            t = cv2.resize(templ, None, fx=sc, fy=sc,
                           interpolation=cv2.INTER_AREA if sc < 1 else cv2.INTER_LINEAR)
        tt = prep(t) if use_edges else t
        r = _match_one(scene_p, tt)
        if r is None:
            continue
        score, left, top, w, h = r
        cx = left + w // 2 + offset[0]
        cy = top + h // 2 + offset[1]
        cand = (score, cx, cy, left, top, w, h, sc)
        if best is None or score > best[0]:
            best = cand

    if best is None:
        return {"found": False, "score": 0.0, "reason": "template larger than scene at all scales"}

    score, cx, cy, left, top, w, h, sc = best
    return {
        "found": bool(score >= min_score),
        "score": round(score, 4),
        "min_score": min_score,
        "x": cx, "y": cy,               # click point (scene coords + offset)
        "left": left, "top": top,        # bounding box top-left (raw match)
        "w": w, "h": h,
        "scale": sc,
        "offset": list(offset),
        "edges": bool(use_edges),
    }


def verify(before_path, after_path, region=None, min_change=0.01):
    """
    Did the screen change between before/after?  Returns fraction of pixels that
    differ by more than a small tolerance (and mean abs diff), plus a boolean.

    region = (x, y, w, h) restricts the comparison to where the action was aimed
    (e.g. the button we clicked / the field we typed into) — a global compare is
    noisy on live desktops (clocks, cursors), a regional one is decisive.
    """
    a = _imread(before_path, gray=True).astype(np.int16)
    b = _imread(after_path, gray=True).astype(np.int16)
    if a.shape != b.shape:
        # Resize after->before shape so mismatched captures still compare.
        b = cv2.resize(b.astype(np.uint8), (a.shape[1], a.shape[0])).astype(np.int16)
    if region:
        x, y, w, h = region
        x = max(0, x); y = max(0, y)
        a = a[y:y + h, x:x + w]
        b = b[y:y + h, x:x + w]
        if a.size == 0:
            return {"changed": False, "reason": "empty region", "changed_frac": 0.0}
    diff = np.abs(a - b)
    changed_frac = float((diff > 18).mean())   # 18/255 ≈ ignore JPEG/noise jitter
    mean_diff = float(diff.mean())
    return {
        "changed": bool(changed_frac >= min_change),
        "changed_frac": round(changed_frac, 5),
        "mean_diff": round(mean_diff, 3),
        "min_change": min_change,
        "region": list(region) if region else None,
    }


def calibrate(scene_path, anchor_path, expect=None, min_score=0.80):
    """
    Locate a fixed anchor (a UI landmark that never moves relative to the remote
    desktop origin) and derive the offset between where it *is* and where it is
    *expected*. That offset is the AnyDesk/RustDesk toolbar/title-bar shift; apply
    it via `find --offset DX,DY` so every later click is corrected once, not eyeballed.
    """
    hit = find(scene_path, anchor_path, min_score=min_score, use_edges=False)
    if not hit.get("found"):
        return {"ok": False, "score": hit.get("score", 0.0),
                "reason": "anchor not found above threshold"}
    found_xy = (hit["left"], hit["top"])
    if expect is None:
        # No expectation given: the anchor's top-left *is* the content origin.
        dx, dy = found_xy
    else:
        dx = found_xy[0] - expect[0]
        dy = found_xy[1] - expect[1]
    return {
        "ok": True,
        "score": hit["score"],
        "anchor_at": list(found_xy),
        "expect": list(expect) if expect else None,
        "offset": [int(dx), int(dy)],
        "hint": "pass to find as: --offset %d,%d" % (int(dx), int(dy)),
    }


def _emit(obj, as_json, ok_key=None):
    if as_json:
        print(json.dumps(obj, ensure_ascii=False))
    else:
        for k, v in obj.items():
            print("%s=%s" % (k, v))
    return obj


def main(argv=None):
    p = argparse.ArgumentParser(prog="vmatch")
    sub = p.add_subparsers(dest="cmd", required=True)

    pf = sub.add_parser("find")
    pf.add_argument("--scene", required=True)
    pf.add_argument("--template", required=True)
    pf.add_argument("--min-score", type=float, default=0.80)
    pf.add_argument("--scales", default=None)
    pf.add_argument("--offset", default="0,0")
    pf.add_argument("--edges", action="store_true")
    pf.add_argument("--json", action="store_true")

    pv = sub.add_parser("verify")
    pv.add_argument("--before", required=True)
    pv.add_argument("--after", required=True)
    pv.add_argument("--region", default=None)
    pv.add_argument("--min-change", type=float, default=0.01)
    pv.add_argument("--json", action="store_true")

    pc = sub.add_parser("calibrate")
    pc.add_argument("--scene", required=True)
    pc.add_argument("--anchor", required=True)
    pc.add_argument("--expect", default=None)
    pc.add_argument("--min-score", type=float, default=0.80)
    pc.add_argument("--json", action="store_true")

    args = p.parse_args(argv)

    try:
        if args.cmd == "find":
            scales = _parse_floats(args.scales) if args.scales else None
            off = _parse_ints(args.offset)
            off = (off + [0, 0])[:2]
            res = find(args.scene, args.template, min_score=args.min_score,
                       scales=scales, offset=tuple(off), use_edges=args.edges)
            _emit(res, args.json)
            return 0 if res.get("found") else 2

        if args.cmd == "verify":
            region = tuple(_parse_ints(args.region)) if args.region else None
            if region is not None and len(region) != 4:
                sys.stderr.write("verify: --region needs X,Y,W,H\n")
                return 3
            res = verify(args.before, args.after, region=region,
                         min_change=args.min_change)
            _emit(res, args.json)
            return 0 if res.get("changed") else 2

        if args.cmd == "calibrate":
            expect = tuple(_parse_ints(args.expect)) if args.expect else None
            res = calibrate(args.scene, args.anchor, expect=expect,
                            min_score=args.min_score)
            _emit(res, args.json)
            return 0 if res.get("ok") else 2
    except FileNotFoundError as e:
        sys.stderr.write("vmatch: %s\n" % e)
        return 3

    return 3


if __name__ == "__main__":
    sys.exit(main())
