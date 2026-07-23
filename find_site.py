import time
from playwright.sync_api import sync_playwright

SITES = [
    "https://ra-data-fakerest.marmelab.com/",
    "https://demo.react-admin.com/",
    "https://mui.com/material-ui/react-table/",
    "https://tailwindcss.com/components/tabs",
    "https://github.com/trending", # Complex, many buttons/links
]

def try_capture(url):
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context(viewport={'width': 1920, 'height': 1080})
            page = context.new_page()
            page.set_default_timeout(10000)
            page.goto(url, wait_until="domcontentloaded")
            page.screenshot(path="complex_scene.png", full_page=False)
            browser.close()
            return True
    except Exception as e:
        print(f"Failed {url}: {e}")
        return False

for site in SITES:
    print(f"Trying {site}...")
    if try_capture(site):
        print(f"SUCCESS: Captured {site}")
        break
