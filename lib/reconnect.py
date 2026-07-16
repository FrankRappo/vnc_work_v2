#!/usr/bin/env python3
"""
reconnect.py — session liveness classifier + reconnect policy for vnc_work_v2.

The AnyDesk-free channel drops the session on a ~5-minute timer and throttles the
reconnect; RustDesk (self-hosted server) is the stable channel. v2 needs to (a)
DECIDE whether the current frame is a live remote desktop or a dead/frozen one,
and (b) drive reconnect with backoff, preferring the stable channel.

This module does the pure, testable parts:

  classify   Look at a captured frame and label it:
               live    — real remote desktop content (high luminance variance,
                         not a solid colour, no disconnect banner)
               black   — near-black / blank (frozen or torn-down session)
               banner  — a disconnect/error banner is present (optionally
                         confirmed by matching a banner template)
             Uses the same "content variance" heuristic the old rustdesk_kso.sh
             verify used (std-dev of grayscale), made explicit and thresholded,
             plus an optional banner-template check via vmatch.

  backoff    Emit a reconnect schedule (attempt -> wait seconds) with jitter and
             a cap, so callers don't hammer AnyDesk's throttle. Deterministic
             given a seed (no Math.random dependency) so it is testable.

  plan       Given a channel preference, print the ordered reconnect plan
             (which driver command to run) WITHOUT running anything — the shell
             layer executes it, and only when RC_LIVE=1.

Pure: reads image files, prints JSON. Never opens a socket or a session.
"""
import argparse
import json
import os
import sys

try:
    import cv2
    import numpy as np
except Exception as exc:  # pragma: no cover
    sys.stderr.write("reconnect: OpenCV/numpy required: %s\n" % exc)
    sys.exit(4)

_LIB = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _LIB)
try:
    import vmatch  # reuse the template matcher for banner confirmation
except Exception:
    vmatch = None


def classify(frame_path, banner_template=None, min_content_sd=0.03,
             black_mean=16.0, banner_min_score=0.7):
    """
    Returns {state, content_sd, mean, ...}. content_sd is the normalised (0..1)
    std-dev of grayscale luminance — the same signal the legacy verify used
    (>0.03 == real content). mean near 0 == black/frozen.
    """
    img = cv2.imread(frame_path, cv2.IMREAD_GRAYSCALE)
    if img is None:
        raise FileNotFoundError("cannot read frame: %s" % frame_path)
    mean = float(img.mean())
    sd = float(img.std() / 255.0)

    banner_hit = None
    if banner_template and vmatch is not None:
        try:
            m = vmatch.find(frame_path, banner_template,
                            min_score=banner_min_score, use_edges=False)
            if m.get("found"):
                banner_hit = {"score": m["score"], "x": m["x"], "y": m["y"]}
        except Exception:
            banner_hit = None

    if banner_hit:
        state = "banner"
    elif mean <= black_mean or sd < min_content_sd:
        state = "black"
    else:
        state = "live"
    return {
        "state": state,
        "alive": state == "live",
        "mean": round(mean, 3),
        "content_sd": round(sd, 4),
        "min_content_sd": min_content_sd,
        "black_mean": black_mean,
        "banner": banner_hit,
    }


def backoff(attempts=6, base=3.0, factor=2.0, cap=60.0, seed=1):
    """
    Deterministic exponential backoff with bounded jitter. Jitter is derived from
    a linear-congruential sequence seeded by `seed` (no Math.random / time), so
    the schedule is reproducible and unit-testable.
    """
    sched = []
    state = (seed * 1103515245 + 12345) & 0x7FFFFFFF
    wait = base
    for i in range(1, attempts + 1):
        state = (state * 1103515245 + 12345) & 0x7FFFFFFF
        jitter = (state / 0x7FFFFFFF) * (wait * 0.25)   # up to +25%
        w = min(cap, wait + jitter)
        sched.append({"attempt": i, "wait_s": round(w, 2)})
        wait = min(cap, wait * factor)
    return sched


def plan(channel_pref, ad_id=None, rd_id=None):
    """
    Ordered reconnect plan. Prefers the stable RustDesk channel; AnyDesk-free is
    the fallback (and flagged as throttled/5-min). The shell layer maps each step
    to a real driver command and runs it ONLY under RC_LIVE=1.
    """
    steps = []
    order = ["rustdesk", "anydesk"] if channel_pref != "anydesk" else ["anydesk", "rustdesk"]
    for ch in order:
        if ch == "rustdesk":
            steps.append({
                "channel": "rustdesk", "stable": True,
                "cmd": "rustdesk/connect.sh %s" % (rd_id or "<RD_ID>"),
                "why": "self-hosted server, no time limit, real clipboard",
            })
        else:
            steps.append({
                "channel": "anydesk", "stable": False,
                "cmd": "anydesk_kso.sh id %s" % (ad_id or "<AD_ID>"),
                "why": "FREE: ~5-min drop + reconnect throttle — bootstrap only",
            })
    return {"prefer": channel_pref, "steps": steps}


def main(argv=None):
    p = argparse.ArgumentParser(prog="reconnect")
    sub = p.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("classify"); c.add_argument("--frame", required=True)
    c.add_argument("--banner-template", default=None)
    c.add_argument("--min-content-sd", type=float, default=0.03)
    c.add_argument("--black-mean", type=float, default=16.0)
    c.add_argument("--json", action="store_true")

    b = sub.add_parser("backoff"); b.add_argument("--attempts", type=int, default=6)
    b.add_argument("--base", type=float, default=3.0); b.add_argument("--factor", type=float, default=2.0)
    b.add_argument("--cap", type=float, default=60.0); b.add_argument("--seed", type=int, default=1)
    b.add_argument("--json", action="store_true")

    pl = sub.add_parser("plan"); pl.add_argument("--prefer", default="rustdesk")
    pl.add_argument("--ad-id", default=None); pl.add_argument("--rd-id", default=None)
    pl.add_argument("--json", action="store_true")

    a = p.parse_args(argv)
    as_json = getattr(a, "json", False)
    try:
        if a.cmd == "classify":
            res = classify(a.frame, banner_template=a.banner_template,
                           min_content_sd=a.min_content_sd, black_mean=a.black_mean)
            rc = 0 if res["alive"] else 2
        elif a.cmd == "backoff":
            res = {"schedule": backoff(a.attempts, a.base, a.factor, a.cap, a.seed)}
            rc = 0
        elif a.cmd == "plan":
            res = plan(a.prefer, ad_id=a.ad_id, rd_id=a.rd_id)
            rc = 0
        else:
            return 3
    except FileNotFoundError as e:
        sys.stderr.write("reconnect: %s\n" % e); return 3
    if as_json:
        print(json.dumps(res, ensure_ascii=False))
    else:
        print(json.dumps(res, ensure_ascii=False, indent=2))
    return rc


if __name__ == "__main__":
    sys.exit(main())
