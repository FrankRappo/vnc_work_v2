#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Smoke tests for edge_cdp.py Windows port.
Run after edge_cdp.py to verify all basic functions work.
"""

import os
import sys
import time

# Smoke tests must never reuse or stop an authenticated browser profile.
LOCAL_APPDATA = os.environ.get(
    "LOCALAPPDATA", os.path.expanduser(r"~\AppData\Local")
)
SMOKE_STATE = os.path.join(LOCAL_APPDATA, "VncWorkEdgeSmoke")
os.environ.setdefault("EDGE_CDP_PORT", "19445")
os.environ.setdefault(
    "EDGE_CDP_PROFILE",
    os.path.join(SMOKE_STATE, "profile"),
)

# Add our cdp module to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'cdp'))

from edge_cdp import (
    cmd_start, cmd_stop, cmd_status, cmd_screenshot,
    cmd_get, is_up, http_json, PORT, PROFILE
)

OUT_DIR = os.path.join(SMOKE_STATE, "results")
os.makedirs(OUT_DIR, exist_ok=True)

def test(name, func, *args, **kwargs):
    print(f"TEST: {name} ... ", end="", flush=True)
    try:
        result = func(*args, **kwargs)
        if result == 0 or result is True:
            print("PASS")
            return True
        else:
            print(f"FAIL (returned {result})")
            return False
    except Exception as e:
        print(f"FAIL ({type(e).__name__}: {e})")
        return False

def main():
    results = []

    # Recover cleanly from an interrupted earlier smoke run.  The module is
    # pinned to the disposable port/profile above, so this cannot touch the
    # authenticated browser on port 19444.
    if is_up():
        cmd_stop()
        time.sleep(2)

    # 1. Status before start
    results.append(test("status_before_start", lambda: not is_up()))

    # 2. Start Edge
    results.append(test("start_edge", cmd_start))
    time.sleep(2)

    # 3. Status after start
    results.append(test("status_after_start", is_up))

    # 4. Target discovery
    def check_target():
        pages = http_json("/json/list")
        return len(pages) > 0
    results.append(test("target_discovery", check_target))

    # 5. Screenshot
    results.append(test("screenshot", cmd_screenshot, os.path.join(OUT_DIR, "smoke_screenshot.png")))
    time.sleep(1)

    # 6. Navigate to test page
    results.append(test("navigate_test", cmd_get,
        "https://example.com/",
        None, "document.title==='Example Domain'", 15000, 1000,
        os.path.join(OUT_DIR, "smoke_example.html"),
        False, None, 1, "left"))

    # 7. DOM evaluate
    def eval_test():
        from edge_cdp import attach
        cdp = attach()
        cdp.call("Runtime.enable")
        val, err = cdp.evaluate("document.title")
        cdp.close()
        return val == "Example Domain" and err is None
    results.append(test("dom_evaluate", eval_test))

    # 8. Input test (click at 0,0 - harmless)
    def input_test():
        from edge_cdp import attach
        cdp = attach()
        cdp.call("Input.dispatchMouseEvent", {
            "type": "mouseMoved", "x": 10, "y": 10, "button": "left"
        })
        cdp.close()
        return True
    results.append(test("input_mouse", input_test))

    # 9. Stop
    results.append(test("stop_edge", cmd_stop))
    time.sleep(2)

    # 10. Verify stopped
    results.append(test("verify_stopped", lambda: not is_up()))

    # Summary
    passed = sum(results)
    total = len(results)
    print(f"\n{'='*50}")
    print(f"SMOKE TEST RESULTS: {passed}/{total} passed")
    if passed == total:
        print("ALL TESTS PASSED - native Edge/CDP tool is ready")
        return 0
    else:
        print("SOME TESTS FAILED - review output above")
        return 1

if __name__ == "__main__":
    sys.exit(main())
