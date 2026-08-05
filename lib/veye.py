#!/usr/bin/env python3
"""
veye.py — the "haiku-eye" layer of vnc_work_v2.

THE CORE IDEA of v2: the expensive main agent NEVER loads the remote screenshot
into its own context (tokens/limit). A cheap haiku sub-agent looks at the image
and must return EXACT pixel coordinates. The historical failure was that haiku,
handed a downscaled 1920x1080 jpg, estimated coordinates by eye (+-20..50 px) and
the caller then clicked between buttons.

veye removes the *estimation* step. Two mechanisms, both make the pixel a
computed value, not an eyeballed one:

  crop      Extract the region of interest and UPSCALE it, optionally stamping a
            coordinate grid whose labels are the REAL screen pixels. The haiku
            sub-agent reads coordinates off the ruler of a big, clear crop; the
            mapping back to the full frame is arithmetic (deproject), so there is
            no scale-guess error. Emits the deprojection params as JSON.

  deproject Map a point the sub-agent reported *inside a crop* back to real
            screen pixels:  real = origin + reported / scale.  This is the exact
            contract the main agent uses to click.

  grid      Stamp a labelled coordinate grid over a whole frame (fallback when
            there is no ROI yet) so even a full-frame read is on a ruler.

  roi       Compute a padded ROI box around a point/box (e.g. around a template
            match) to feed `crop`.

  ocr       OPTIONAL text->coordinate locator via the `tesseract` CLI. Degrades
            cleanly (exit 5, machine-readable reason) when tesseract is absent,
            so template-matching (vmatch.py) stays the reliable primary path.

Pure image math on FILES. No network, no clicks, no live machine. Coordinates
are always in full-frame screen pixels unless a subcommand says otherwise.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

try:
    import cv2
    import numpy as np
except Exception as exc:  # pragma: no cover
    sys.stderr.write("veye: OpenCV/numpy required: %s\n" % exc)
    sys.exit(4)


def _imread(path, gray=False):
    flag = cv2.IMREAD_GRAYSCALE if gray else cv2.IMREAD_COLOR
    img = cv2.imread(path, flag)
    if img is None:
        raise FileNotFoundError("cannot read image: %s" % path)
    return img


def _ints(s):
    return [int(round(float(x))) for x in s.split(",") if x.strip() != ""]


def _grid_color(bg_is_dark=True):
    return (0, 255, 0)  # green ruler, visible on both dark kiosks and light UIs


def stamp_grid(img, step=100, origin=(0, 0), scale=1.0, thickness=1):
    """
    Draw a labelled coordinate grid onto img (in place on a copy).

    Labels show REAL screen coordinates: for a plain full-frame grid origin=(0,0)
    scale=1. For a crop, pass the crop origin and the upscale factor so every
    ruler label is the real pixel the sub-agent should report.
    """
    out = img.copy()
    h, w = out.shape[:2]
    col = _grid_color()
    font = cv2.FONT_HERSHEY_SIMPLEX
    ox, oy = origin

    def label(txt, x, y):
        # black halo + green fill => readable on ANY background (light UI or dark kiosk),
        # so haiku never misreads the digit and picks the wrong line.
        cv2.putText(out, txt, (x, y), font, 0.5, (0, 0, 0), 3, cv2.LINE_AA)
        cv2.putText(out, txt, (x, y), font, 0.5, col, 1, cv2.LINE_AA)

    # vertical lines at every `step` REAL pixels -> pixel position = (real-ox)*scale.
    # Label at BOTH top and bottom so a tight crop always shows the ruler value next to the target.
    real_x = (int(ox // step) * step)
    while real_x <= ox + w / scale:
        px = int((real_x - ox) * scale)
        if 0 <= px < w:
            cv2.line(out, (px, 0), (px, h), col, thickness)
            label(str(real_x), min(px + 3, w - 52), 18)
            label(str(real_x), min(px + 3, w - 52), h - 6)
        real_x += step
    real_y = (int(oy // step) * step)
    while real_y <= oy + h / scale:
        py = int((real_y - oy) * scale)
        if 0 <= py < h:
            cv2.line(out, (0, py), (w, py), col, thickness)
            label(str(real_y), 3, min(py + 16, h - 3))
            label(str(real_y), max(3, w - 58), min(py + 16, h - 3))
        real_y += step
    return out


def _out_path(p):
    """cv2.imwrite needs a known image extension; append .png if the caller
    passed a bare label (e.g. 'start_grid'). Returns the actual path written."""
    import os
    ext = os.path.splitext(p)[1].lower()
    if ext not in (".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff"):
        p = p + ".png"
    return p


def cmd_grid(a):
    img = _imread(a.scene)
    out = stamp_grid(img, step=a.step)
    outp = _out_path(a.out)
    if not cv2.imwrite(outp, out):
        raise SystemExit("veye grid: cv2.imwrite failed for %s" % outp)
    res = {"out": outp, "step": a.step, "size": [img.shape[1], img.shape[0]],
           "note": "labels are real screen pixels; report the label under the target"}
    return res, 0


def cmd_crop(a):
    """
    Crop ROI (x,y,w,h) from scene, upscale by --scale, optionally stamp a grid
    labelled in real pixels. Prints the deprojection params so the caller can map
    any point the sub-agent reads back to full-frame pixels.
    """
    img = _imread(a.scene)
    H, W = img.shape[:2]
    x, y, w, h = a.region
    x = max(0, min(x, W - 1)); y = max(0, min(y, H - 1))
    w = max(1, min(w, W - x)); h = max(1, min(h, H - y))
    roi = img[y:y + h, x:x + w]
    scale = float(a.scale)
    if scale != 1.0:
        interp = cv2.INTER_LINEAR if scale > 1 else cv2.INTER_AREA
        roi = cv2.resize(roi, None, fx=scale, fy=scale, interpolation=interp)
    if a.grid:
        roi = stamp_grid(roi, step=a.step, origin=(x, y), scale=scale)
    outp = _out_path(a.out)
    if not cv2.imwrite(outp, roi):
        raise SystemExit("veye crop: cv2.imwrite failed for %s" % outp)
    res = {
        "out": outp,
        "origin": [x, y],            # real screen coords of crop top-left
        "scale": scale,
        "crop_size": [roi.shape[1], roi.shape[0]],
        "deproject": "real_x = %d + px/%g ; real_y = %d + py/%g" % (x, scale, y, scale),
        "note": "sub-agent reads coords ON THIS CROP; caller runs `veye deproject` to get real pixels",
    }
    return res, 0


def cmd_deproject(a):
    """real = origin + reported / scale.  The exact crop->screen contract."""
    ox, oy = a.origin
    px, py = a.point
    rx = int(round(ox + px / a.scale))
    ry = int(round(oy + py / a.scale))
    return {"x": rx, "y": ry, "origin": [ox, oy], "scale": a.scale,
            "point_in_crop": [px, py]}, 0


def cmd_roi(a):
    """Padded ROI box around a center or a box, clamped to the frame."""
    img = _imread(a.scene)
    H, W = img.shape[:2]
    if a.box:
        bx, by, bw, bh = a.box
        cx, cy = bx + bw // 2, by + bh // 2
        half_w, half_h = bw // 2 + a.pad, bh // 2 + a.pad
    else:
        cx, cy = a.center
        half_w = half_h = a.pad
    x = max(0, cx - half_w); y = max(0, cy - half_h)
    w = min(W - x, 2 * half_w); h = min(H - y, 2 * half_h)
    return {"region": [x, y, w, h], "center": [cx, cy]}, 0


def cmd_ocr(a):
    """
    Optional OCR text->coordinate. Uses the tesseract CLI TSV output. Returns the
    best word/line whose text matches --text (case-insensitive substring) and its
    center in real screen pixels. Degrades cleanly if tesseract is missing.
    """
    exe = shutil.which("tesseract")
    if not exe:
        return {"found": False, "reason": "tesseract not installed",
                "hint": "install tesseract-ocr, or use template match (vmatch.py find)"}, 5
    img = _imread(a.scene)
    tmp = a.scene + ".ocr"
    # --region X,Y,W,H + --scale: CROP AND UPSCALE BEFORE OCR.
    # Small UI text (1C section panel, form field captions at 1920x1080) is not read at all
    # on the full frame: tesseract returned zero hits for nine visible section names, i.e. a
    # negative OCR result on a full frame proves nothing. The same frame cropped to the column
    # and scaled 3x reads every one of them at conf 91-97. Coordinates are mapped back to real
    # screen pixels here, so callers keep working in screen space.
    scan = a.scene
    ox = oy = 0
    scale = float(getattr(a, "scale", 1.0) or 1.0)
    region = getattr(a, "region", None)
    if region or scale != 1.0:
        sub = img
        if region:
            ox, oy, rw, rh = region
            H, W = img.shape[:2]
            ox = max(0, min(ox, W - 1)); oy = max(0, min(oy, H - 1))
            rw = max(1, min(rw, W - ox)); rh = max(1, min(rh, H - oy))
            sub = img[oy:oy + rh, ox:ox + rw]
        if scale != 1.0:
            sub = cv2.resize(sub, None, fx=scale, fy=scale, interpolation=cv2.INTER_LANCZOS4)
        scan = a.scene + ".ocrscan.png"
        cv2.imwrite(scan, sub)
    try:
        proc = subprocess.run(
            [exe, scan, tmp, "-l", a.lang, "--psm", str(getattr(a, "psm", 3)), "tsv"],
            capture_output=True, text=True, timeout=60)
        tsv_path = tmp + ".tsv"
        if proc.returncode != 0 or not os.path.exists(tsv_path):
            return {"found": False, "reason": "tesseract failed",
                    "stderr": proc.stderr[-300:]}, 2
        want = a.text.lower()
        best = None
        with open(tsv_path) as fh:
            header = fh.readline().rstrip("\n").split("\t")
            idx = {k: i for i, k in enumerate(header)}
            for line in fh:
                f = line.rstrip("\n").split("\t")
                if len(f) < len(header):
                    continue
                txt = f[idx["text"]].strip()
                if not txt:
                    continue
                try:
                    conf = float(f[idx["conf"]])
                except ValueError:
                    conf = -1
                if want in txt.lower() and conf >= a.min_conf:
                    L, T = int(f[idx["left"]]), int(f[idx["top"]])
                    Wd, Hd = int(f[idx["width"]]), int(f[idx["height"]])
                    cand = (conf,
                            int(round(ox + (L + Wd / 2.0) / scale)),
                            int(round(oy + (T + Hd / 2.0) / scale)),
                            txt,
                            int(round(ox + L / scale)), int(round(oy + T / scale)),
                            int(round(Wd / scale)), int(round(Hd / scale)))
                    if best is None or conf > best[0]:
                        best = cand
        if best is None:
            return {"found": False, "reason": "text not found", "text": a.text}, 2
        conf, cx, cy, txt, bx, by, bw, bh = best
        return {"found": True, "x": cx, "y": cy, "conf": conf, "matched": txt,
                "box": "%d,%d,%d,%d" % (bx, by, bw, bh)}, 0
    finally:
        for ext in (".tsv", ".txt"):
            q = tmp + ext
            if os.path.exists(q):
                os.remove(q)
        if scan != a.scene and os.path.exists(scan):
            os.remove(scan)


# 🔴 Возраст сцены едет в КАЖДОМ ответе (kso-anydesk-stale-frame, 2026-08-05). Разбор идёт по
# файлу, и файл может быть каким угодно старым: картинка июльская, а JSON приходит бодрый и
# правдоподобный. Ответ без возраста кадра — это ответ «про какой-то экран», а не про текущий.
# rc.sh отказывается брать неявную старую сцену; здесь же страховка для ПРЯМЫХ вызовов veye.py.
_SCENE_META = {}


def _scene_meta(path):
    try:
        ts = os.path.getmtime(path)
        return {"scene_taken": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(ts)),
                "scene_age_min": int((time.time() - ts) / 60)}
    except OSError:
        return {}


def _emit(obj, as_json):
    for k, v in _SCENE_META.items():
        obj.setdefault(k, v)
    if as_json:
        print(json.dumps(obj, ensure_ascii=False))
    else:
        for k, v in obj.items():
            print("%s=%s" % (k, v))


def main(argv=None):
    p = argparse.ArgumentParser(prog="veye")
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("grid"); g.add_argument("--scene", required=True)
    g.add_argument("--out", required=True); g.add_argument("--step", type=int, default=100)
    g.add_argument("--json", action="store_true")

    c = sub.add_parser("crop"); c.add_argument("--scene", required=True)
    c.add_argument("--out", required=True); c.add_argument("--region", required=True)
    c.add_argument("--scale", default="3.0"); c.add_argument("--step", type=int, default=25)
    c.add_argument("--grid", action="store_true"); c.add_argument("--json", action="store_true")

    d = sub.add_parser("deproject"); d.add_argument("--origin", required=True)
    d.add_argument("--scale", type=float, required=True); d.add_argument("--point", required=True)
    d.add_argument("--json", action="store_true")

    r = sub.add_parser("roi"); r.add_argument("--scene", required=True)
    r.add_argument("--center", default=None); r.add_argument("--box", default=None)
    r.add_argument("--pad", type=int, default=120); r.add_argument("--json", action="store_true")

    o = sub.add_parser("ocr"); o.add_argument("--scene", required=True)
    o.add_argument("--text", required=True); o.add_argument("--lang", default="rus+eng")
    o.add_argument("--min-conf", type=float, default=40.0); o.add_argument("--json", action="store_true")
    o.add_argument("--region", default=None, help="X,Y,W,H crop before OCR (coords mapped back)")
    o.add_argument("--scale", type=float, default=1.0, help="upscale factor before OCR (3.0 for small UI text)")
    # 🔴 psm 11 (sparse text) is what makes scattered UI captions readable at all: with the
    # default page-segmentation the 1C section-page link was found at conf 42 on the full frame
    # and NOT AT ALL on the cropped one — the layout analyser decides there is no "page" there.
    o.add_argument("--psm", type=int, default=3, help="tesseract page segmentation mode (11 = sparse UI text)")

    a = p.parse_args(argv)
    _SCENE_META.update(_scene_meta(getattr(a, "scene", "") or ""))
    try:
        if a.cmd == "grid":
            res, rc = cmd_grid(a)
        elif a.cmd == "crop":
            a.region = _ints(a.region)
            if len(a.region) != 4:
                sys.stderr.write("crop: --region needs X,Y,W,H\n"); return 3
            res, rc = cmd_crop(a)
        elif a.cmd == "deproject":
            a.origin = _ints(a.origin); a.point = _ints(a.point)
            res, rc = cmd_deproject(a)
        elif a.cmd == "roi":
            a.center = _ints(a.center) if a.center else None
            a.box = _ints(a.box) if a.box else None
            if not a.center and not a.box:
                sys.stderr.write("roi: need --center X,Y or --box X,Y,W,H\n"); return 3
            res, rc = cmd_roi(a)
        elif a.cmd == "ocr":
            a.region = _ints(a.region) if a.region else None
            if a.region and len(a.region) != 4:
                sys.stderr.write("ocr: --region needs X,Y,W,H\n"); return 3
            res, rc = cmd_ocr(a)
        else:
            return 3
    except FileNotFoundError as e:
        sys.stderr.write("veye: %s\n" % e); return 3
    _emit(res, getattr(a, "json", False))
    return rc


if __name__ == "__main__":
    sys.exit(main())
