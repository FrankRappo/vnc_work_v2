import cv2
import numpy as np
from lib.vmatch import find
import os

def apply_gaussian_blur(img, ksize=5):
    return cv2.GaussianBlur(img, (ksize, ksize), 0)

def apply_heavy_noise(img, amount=0.2):
    noise = np.random.randint(0, 256, img.shape, dtype='uint8')
    return cv2.addWeighted(img, 1 - amount, noise, amount, 0)

def apply_contrast_shift(img, alpha=0.5):
    # Contrast shift: a * img + b
    return cv2.convertScaleAbs(img, alpha=alpha, beta=0)

def main():
    scene_path = "complex_scene.png"
    if not os.path.exists(scene_path):
        print("Scene file missing!")
        return

    scene = cv2.imread(scene_path, cv2.IMREAD_GRAYSCALE)
    h, w = scene.shape
    
    # We'll use a more "interesting" part of the screen. 
    # Instead of a fixed slice, we'll try to find a high-gradient area.
    # But for simplicity, let's stick to a region that's likely a button.
    rx, ry, rw, rh = 1200, 200, 150, 50
    template = scene[ry:ry+rh, rx:rx+rw]
    
    if template.size == 0:
        print("Template area empty!")
        return

    cv2.imwrite("tmpl_base.png", template)
    
    tests = [
        ("Exact", template),
        ("Blurred", apply_gaussian_blur(template)),
        ("Heavy Noise", apply_heavy_noise(template)),
        ("Low Contrast", apply_contrast_shift(template, 0.4)),
        ("High Contrast", apply_contrast_shift(template, 1.8)),
    ]
    
    print(f"{'Test Case':<20} | {'Score':<10} | {'Found':<10}")
    print("-" * 45)
    
    for name, tmpl in tests:
        tmpl_path = f"tmpl_{name.lower().replace(' ', '_')}.png"
        cv2.imwrite(tmpl_path, tmpl)
        res = find(scene_path, tmpl_path, min_score=0.8)
        print(f"{name:<20} | {res.get('score'):<10.4f} | {str(res.get('found')):<10}")

if __name__ == "__main__":
    main()
