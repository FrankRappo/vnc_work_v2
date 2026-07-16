#!/usr/bin/env python3
"""
make_fixtures.py — generate deterministic LOCAL test images for vnc_work_v2.

No network, no live machine, no clicks. Produces a synthetic "remote desktop"
that mimics the real failure modes the toolkit hits:

  scene_before.png  — a 1280x800 kiosk-ish desktop with a toolbar, an anchor
                      landmark (top-left corner marker) and a green "Оплата"
                      button at a KNOWN pixel center (used as ground truth).
  scene_after.png   — same desktop after the button was "pressed" (button
                      changes colour + a dialog appears) → verify() must see a
                      change in the button region.
  scene_black.png   — a frozen/disconnected frame (near-black) → reconnect
                      classifier must call this DEAD.
  scene_banner.png  — a frame carrying a "Connection Closed" banner → DEAD.
  tmpl_pay.png      — the "Оплата" button cropped out → template to find.
  tmpl_anchor.png   — the top-left corner landmark → calibration anchor.
  ground_truth.json — the exact centres/offsets so tests assert to the pixel.

Everything is drawn with OpenCV so the fixtures are byte-stable across runs
(no fonts/AA randomness beyond OpenCV's Hershey font, which is deterministic).
"""
import json
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))

W, H = 1280, 800
# Ground-truth geometry (the numbers tests assert against).
PAY_BOX = (520, 470, 240, 70)          # x, y, w, h of the green button
PAY_CENTER = (PAY_BOX[0] + PAY_BOX[2] // 2, PAY_BOX[1] + PAY_BOX[3] // 2)
ANCHOR_BOX = (0, 0, 46, 46)            # top-left landmark
TOOLBAR_H = 40                         # simulated AnyDesk/RustDesk toolbar band


def _base_desktop():
    img = np.full((H, W, 3), (40, 42, 48), np.uint8)          # dark desktop
    # faint content texture so a live frame has real variance (not flat).
    rng = np.random.RandomState(7)
    noise = rng.randint(0, 22, (H, W, 3), dtype=np.uint8)
    img = cv2.add(img, noise)
    # simulated remote toolbar band at the very top (the offset source).
    cv2.rectangle(img, (0, 0), (W, TOOLBAR_H), (70, 72, 80), -1)
    cv2.putText(img, "AnyDesk  231 456 789", (60, 27),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 205), 1, cv2.LINE_AA)
    # anchor landmark: a bright unique corner glyph at (0,0)+toolbar.
    ax, ay, aw, ah = ANCHOR_BOX
    cv2.rectangle(img, (ax + 4, ay + TOOLBAR_H + 4),
                  (ax + aw - 4, ay + TOOLBAR_H + ah - 4), (0, 200, 255), 3)
    cv2.line(img, (ax + 8, ay + TOOLBAR_H + 8),
             (ax + aw - 8, ay + TOOLBAR_H + ah - 8), (0, 200, 255), 2)
    # a window title + some UI so template matching has real structure.
    cv2.rectangle(img, (200, 120), (1080, 700), (60, 63, 70), -1)
    cv2.rectangle(img, (200, 120), (1080, 160), (90, 94, 104), -1)
    cv2.putText(img, "KSO :: EasySet terminal", (220, 148),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (230, 230, 235), 2, cv2.LINE_AA)
    cv2.putText(img, "Total: 1 240.00", (240, 300),
                cv2.FONT_HERSHEY_SIMPLEX, 1.0, (220, 220, 225), 2, cv2.LINE_AA)
    return img


def _draw_pay(img, pressed=False):
    x, y, w, h = PAY_BOX
    colour = (40, 120, 40) if pressed else (40, 170, 60)     # BGR green
    cv2.rectangle(img, (x, y), (x + w, y + h), colour, -1)
    cv2.rectangle(img, (x, y), (x + w, y + h), (230, 230, 230), 2)
    cv2.putText(img, "Oplata", (x + 55, y + 46),
                cv2.FONT_HERSHEY_SIMPLEX, 1.0, (255, 255, 255), 2, cv2.LINE_AA)
    return img


def main():
    scene = _draw_pay(_base_desktop(), pressed=False)
    cv2.imwrite(os.path.join(HERE, "scene_before.png"), scene)

    # after: button pressed (darker) + a confirmation dialog pops in its region.
    after = _draw_pay(_base_desktop(), pressed=True)
    cv2.rectangle(after, (480, 440), (800, 560), (60, 63, 70), -1)
    cv2.rectangle(after, (480, 440), (800, 560), (0, 200, 255), 2)
    cv2.putText(after, "Podtverdite", (500, 500),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2, cv2.LINE_AA)
    cv2.imwrite(os.path.join(HERE, "scene_after.png"), after)

    # template crops (with a 2px margin so matching is non-trivial).
    x, y, w, h = PAY_BOX
    cv2.imwrite(os.path.join(HERE, "tmpl_pay.png"), scene[y:y + h, x:x + w])
    ax, ay, aw, ah = ANCHOR_BOX
    cv2.imwrite(os.path.join(HERE, "tmpl_anchor.png"),
                scene[ay + TOOLBAR_H:ay + TOOLBAR_H + ah, ax:ax + aw])

    # dead frames.
    black = np.full((H, W, 3), 3, np.uint8)                 # ~black, tiny noise
    black = cv2.add(black, np.random.RandomState(1).randint(0, 3, (H, W, 3), dtype=np.uint8))
    cv2.imwrite(os.path.join(HERE, "scene_black.png"), black)

    banner = np.full((H, W, 3), 20, np.uint8)
    cv2.rectangle(banner, (340, 340), (940, 460), (30, 30, 160), -1)  # red-ish
    cv2.putText(banner, "Connection Closed", (380, 415),
                cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 3, cv2.LINE_AA)
    cv2.imwrite(os.path.join(HERE, "scene_banner.png"), banner)
    # banner template: the "Connection Closed" text region, used to CONFIRM a
    # disconnect banner (present in scene_banner, absent from scene_before).
    cv2.imwrite(os.path.join(HERE, "tmpl_banner.png"), banner[350:450, 360:920])

    gt = {
        "size": [W, H],
        "toolbar_h": TOOLBAR_H,
        "pay_box": list(PAY_BOX),
        "pay_center": list(PAY_CENTER),
        "anchor_box_content": [ANCHOR_BOX[0], ANCHOR_BOX[1] + TOOLBAR_H,
                               ANCHOR_BOX[2], ANCHOR_BOX[3]],
    }
    with open(os.path.join(HERE, "ground_truth.json"), "w") as fh:
        json.dump(gt, fh, indent=2)
    print("fixtures written to", HERE)
    print("pay_center ground truth =", PAY_CENTER)


if __name__ == "__main__":
    sys.exit(main())
