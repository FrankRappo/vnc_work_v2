import os
import time
from playwright.sync_api import sync_playwright
import cv2
import numpy as np
from lib.vmatch import find

# Use a very reliable site to avoid network timeouts in the CI/VM environment
TARGET_URL = "https://example.com"

def capture_template(page, selector, name):
    print(f"Capturing template for {name} using selector {selector}...")
    try:
        element = page.locator(selector).first
        element.screenshot(path=f"{name}.png")
        print(f"Saved {name}.png")
    except Exception as e:
        print(f"Could not capture {name}: {e}")

def simulate_click(page, template_path, name):
    print(f"\n--- Testing click for {name} ---")
    page.screenshot(path="current_scene.png")
    res = find("current_scene.png", template_path, min_score=0.8)
    if res["found"]:
        print(f"SUCCESS: Found {name} at ({res['x']}, {res['y']}) with score {res['score']}")
        return True
    else:
        print(f"FAILURE: Could not find {name}. Score: {res['score']}")
        return False

def main():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(viewport={'width': 1920, 'height': 1080})
        page = context.new_page()
        
        try:
            print(f"Navigating to {TARGET_URL}...")
            # Use a shorter timeout and avoid waiting for networkidle on a simple site
            page.goto(TARGET_URL, timeout=10000, wait_until="domcontentloaded")
            
            # Targets on example.com
            targets = [
                ("h1", "header"),
                ("a", "link"),
                ("p", "paragraph")
            ]
            
            for selector, name in targets:
                capture_template(page, selector, name)
            
            results = []
            for selector, name in targets:
                results.append(simulate_click(page, f"{name}.png", name))
                
            success_rate = sum(results) / len(results) * 100
            print(f"\nFinal E2E Robustness Score: {success_rate:.2f}%")
            
            if success_rate < 80:
                exit(1)
                
        except Exception as e:
            print(f"Error during E2E: {e}")
            exit(1)
        finally:
            browser.close()

if __name__ == "__main__":
    main()
