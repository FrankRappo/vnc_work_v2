#!/usr/bin/env python3
"""
test_core.py — offline unit tests for the vnc_work_v2 core.

Everything runs on the synthetic LOCAL fixtures (fixtures/make_fixtures.py). No
network, no live machine, no clicks. Assertions are to the pixel where the
fixture defines ground truth, which is the whole point: v2 must be exact, not
"about right".
"""
import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LIB = os.path.join(ROOT, "lib")
FIX = os.path.join(ROOT, "fixtures")
sys.path.insert(0, LIB)

import vmatch      # noqa: E402
import veye        # noqa: E402
import reconnect   # noqa: E402

with open(os.path.join(FIX, "ground_truth.json")) as _fh:
    GT = json.load(_fh)


def fx(name):
    return os.path.join(FIX, name)


class TestFind(unittest.TestCase):
    def test_exact_center(self):
        r = vmatch.find(fx("scene_before.png"), fx("tmpl_pay.png"), min_score=0.8)
        self.assertTrue(r["found"], r)
        self.assertGreaterEqual(r["score"], 0.95)
        self.assertEqual([r["x"], r["y"]], GT["pay_center"])

    def test_edges_mode_also_finds(self):
        r = vmatch.find(fx("scene_before.png"), fx("tmpl_pay.png"),
                        min_score=0.6, use_edges=True)
        self.assertTrue(r["found"], r)
        # edge match must still land within a few px of ground truth
        self.assertLessEqual(abs(r["x"] - GT["pay_center"][0]), 5)
        self.assertLessEqual(abs(r["y"] - GT["pay_center"][1]), 5)

    def test_absent_template_reports_miss_not_wildclick(self):
        # the banner template does NOT exist in the clean desktop -> low score,
        # so found must be False (a reported miss, never a wild click).
        r = vmatch.find(fx("scene_before.png"), fx("tmpl_banner.png"), min_score=0.8)
        self.assertFalse(r["found"], r)


class TestVerify(unittest.TestCase):
    def test_change_detected_in_region(self):
        r = vmatch.verify(fx("scene_before.png"), fx("scene_after.png"),
                          region=tuple(GT["pay_box"]))
        self.assertTrue(r["changed"], r)

    def test_no_change_when_identical(self):
        r = vmatch.verify(fx("scene_before.png"), fx("scene_before.png"),
                          region=tuple(GT["pay_box"]))
        self.assertFalse(r["changed"], r)


class TestCalibrate(unittest.TestCase):
    def test_anchor_offset(self):
        # anchor's real top-left is (0, toolbar_h); with expect=(0,0) the derived
        # offset must equal that shift.
        r = vmatch.calibrate(fx("scene_before.png"), fx("tmpl_anchor.png"),
                             expect=(0, 0))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["offset"], [0, GT["toolbar_h"]])


class TestHaikuEye(unittest.TestCase):
    def test_crop_deproject_roundtrip(self):
        # crop around the pay button, upscale 3x, then a point at the crop centre
        # must deproject back to (near) the button centre.
        region = veye.cmd_roi(_A(scene=fx("scene_before.png"),
                                 center=GT["pay_center"], box=None, pad=100))[0]["region"]
        out = os.path.join(FIX, "_crop_test.png")
        res, rc = veye.cmd_crop(_A(scene=fx("scene_before.png"), out=out,
                                   region=region, scale="3.0", step=25, grid=True))
        self.assertEqual(rc, 0)
        ox, oy = res["origin"]
        scale = res["scale"]
        # the pay centre sits at (center-origin)*scale inside the crop:
        px = (GT["pay_center"][0] - ox) * scale
        py = (GT["pay_center"][1] - oy) * scale
        dj, _ = veye.cmd_deproject(_A(origin=[ox, oy], scale=scale, point=[px, py]))
        self.assertLessEqual(abs(dj["x"] - GT["pay_center"][0]), 1)
        self.assertLessEqual(abs(dj["y"] - GT["pay_center"][1]), 1)
        os.remove(out)

    def test_grid_preserves_size(self):
        img = veye._imread(fx("scene_before.png"))
        out = veye.stamp_grid(img, step=100)
        self.assertEqual(out.shape, img.shape)


class TestReconnect(unittest.TestCase):
    def test_live_frame(self):
        r = reconnect.classify(fx("scene_before.png"))
        self.assertEqual(r["state"], "live", r)
        self.assertTrue(r["alive"])

    def test_black_frame(self):
        r = reconnect.classify(fx("scene_black.png"))
        self.assertEqual(r["state"], "black", r)
        self.assertFalse(r["alive"])

    def test_banner_frame_with_template(self):
        r = reconnect.classify(fx("scene_banner.png"),
                               banner_template=fx("tmpl_banner.png"))
        self.assertEqual(r["state"], "banner", r)
        self.assertFalse(r["alive"])

    def test_banner_template_absent_on_live(self):
        # banner template must NOT false-positive on the clean desktop.
        r = reconnect.classify(fx("scene_before.png"),
                               banner_template=fx("tmpl_banner.png"))
        self.assertEqual(r["state"], "live", r)

    def test_backoff_is_deterministic_and_bounded(self):
        s1 = reconnect.backoff(attempts=6, base=3, factor=2, cap=60, seed=1)
        s2 = reconnect.backoff(attempts=6, base=3, factor=2, cap=60, seed=1)
        self.assertEqual(s1, s2)                       # reproducible
        self.assertTrue(all(x["wait_s"] <= 60 for x in s1))  # capped
        self.assertTrue(s1[0]["wait_s"] < s1[-1]["wait_s"])  # growing

    def test_plan_prefers_rustdesk(self):
        p = reconnect.plan("rustdesk", ad_id="111", rd_id="222")
        self.assertEqual(p["steps"][0]["channel"], "rustdesk")
        self.assertTrue(p["steps"][0]["stable"])


class _A:
    """Tiny attribute bag so we can call the veye cmd_* helpers directly."""
    def __init__(self, **kw):
        self.__dict__.update(kw)


if __name__ == "__main__":
    unittest.main(verbosity=2)
