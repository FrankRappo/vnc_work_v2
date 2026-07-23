import os
import time
from playwright.sync_api import sync_playwright
import cv2
import numpy as np
from lib.vmatch import find

def run_browser_capture(url, output_path, width=1920, height=1080):
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={'width': width, 'height': height})
        page = context.new_page()
        page.goto(url, wait_until="networkidle")
        # Give it a bit more time for React components to mount and animations to finish
        time.sleep(2)
        page.screenshot(path=output_path, full_page=False)
        browser.close()
    print(f"Captured screenshot to {output_path}")

def create_template(scene_path, output_path, x, y, w, h):
    img = cv2.imread(scene_path)
    if img is None:
        raise FileNotFoundError(f"Could not read scene image: {scene_path}")
    crop = img[y:y+h, x:x+w]
    if crop.size == 0:
        raise ValueError("Crop area is empty. Check coordinates.")
    cv2.imwrite(output_path, crop)
    print(f"Created template at {output_path}")

def main():
    target_url = "https://example.com"
    scene_path = "real_scene.png"
    template_path = "real_tmpl.png"
    
    try:
        # 1. Capture a real complex page
        run_browser_capture(target_url, scene_path)
        
        # 2. Create a template from a region
        img = cv2.imread(scene_path)
        h, w, _ = img.shape
        print(f"Scene size: {w}x{h}")
        
        # Let's take a small region that's likely to contain a UI element
        # (e.g., the top navigation bar or a side menu button)
        # We'll take a slice from (100, 100) of size 40x40 for now.
        create_template(scene_path, template_path, 100, 100, 40, 40)
        
        # 3. Test current vmatch
        result = find(scene_path, template_path)
        print(f"Match result: {result}")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
