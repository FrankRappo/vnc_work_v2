#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""edge_cdp.py -- Windows-native CDP driver for Microsoft Edge (isolated profile).
Uses RAW WebSocket (no Origin header) to avoid 403 from CDP origin check.
Based on cdp_linux.py from vnc_work_v2-vm121-review.

Usage:
    python edge_cdp.py start [--port 19444] [--profile-dir PATH]
    python edge_cdp.py status
    python edge_cdp.py get URL [--js EXPR_OR_FILE] [--wait PRED] [--waitms N]
    python edge_cdp.py eval --js EXPR_OR_FILE
    python edge_cdp.py click X,Y [--clicks N] [--btn left|right]
    python edge_cdp.py screenshot [--out FILE]
    python edge_cdp.py cookies [--url URL]
    python edge_cdp.py stop
    python edge_cdp.py ru-center-login [--creds PATH] [--out-dir DIR]
"""

import base64
import json
import os
import socket
import struct
import subprocess
import sys
import time
import urllib.request

# Windows-specific imports
import ctypes
from ctypes import wintypes

PORT = int(os.environ.get("EDGE_CDP_PORT", "19444"))
LOCAL_APPDATA = os.environ.get(
    "LOCALAPPDATA", os.path.expanduser(r"~\AppData\Local")
)
STATE_DIR = os.path.join(LOCAL_APPDATA, "VncWorkEdge")
PROFILE = os.environ.get("EDGE_CDP_PROFILE", os.path.join(STATE_DIR, "profile"))
EDGE = os.environ.get(
    "EDGE_CDP_BINARY",
    os.path.join(
        os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"),
        "Microsoft", "Edge", "Application", "msedge.exe",
    ),
)
UA_DEFAULT = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36 Edg/153.0.0.0")


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# DPAPI credential decryption (Windows-only)
# --------------------------------------------------------------------------
CRYPTPROTECT_UI_FORBIDDEN = 0x01

class DATA_BLOB(ctypes.Structure):
    _fields_ = [("cbData", wintypes.DWORD), ("pbData", wintypes.LPBYTE)]


def decrypt_dpapi(encrypted_bytes):
    """Decrypt bytes using Windows DPAPI CurrentUser scope."""
    blob_in = DATA_BLOB()
    blob_in.cbData = len(encrypted_bytes)
    blob_in.pbData = ctypes.cast(ctypes.create_string_buffer(encrypted_bytes), wintypes.LPBYTE)
    blob_out = DATA_BLOB()
    result = ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(blob_in), None, None, None, None,
        CRYPTPROTECT_UI_FORBIDDEN, ctypes.byref(blob_out))
    if not result:
        raise RuntimeError("CryptUnprotectData failed")
    decrypted = ctypes.string_at(blob_out.pbData, blob_out.cbData)
    ctypes.windll.kernel32.LocalFree(blob_out.pbData)
    return decrypted


def load_credentials(cred_path):
    """Load and decrypt RU-CENTER credentials from DPAPI file."""
    with open(cred_path, 'rb') as f:
        encrypted = f.read()
    decrypted = decrypt_dpapi(encrypted)
    return json.loads(decrypted.decode('utf-8'))


# --------------------------------------------------------------------------
# RAW WebSocket client (no Origin header - avoids CDP 403)
# --------------------------------------------------------------------------
class RawWS:
    def __init__(self, host, port, path, timeout=60):
        self.sock = socket.create_connection((host, port), timeout=15)
        self.sock.settimeout(timeout)
        self.buf = b''
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            'GET /' + path + ' HTTP/1.1\r\n'
            'Host: ' + host + ':' + str(port) + '\r\n'
            'Upgrade: websocket\r\n'
            'Connection: Upgrade\r\n'
            'Sec-WebSocket-Key: ' + key + '\r\n'
            'Sec-WebSocket-Version: 13\r\n'
            '\r\n'
        )
        self.sock.sendall(req.encode())
        hdr = self._read_until(b'\r\n\r\n')
        if b' 101 ' not in hdr.split(b'\r\n')[0]:
            raise RuntimeError("websocket handshake failed: %r" % hdr[:200])

    def _read_until(self, marker):
        while marker not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("socket closed during handshake")
            self.buf += chunk
        head, _, self.buf = self.buf.partition(marker)
        return head + marker

    def _recv_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(max(65536, n - len(self.buf)))
            if not chunk:
                raise RuntimeError("socket closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, text):
        data = text.encode("utf-8")
        n = len(data)
        frame = bytearray([0x81])
        mask = os.urandom(4)
        if n < 126:
            frame.append(0x80 | n)
        elif n < 65536:
            frame.append(0x80 | 126)
            frame += struct.pack(">H", n)
        else:
            frame.append(0x80 | 127)
            frame += struct.pack(">Q", n)
        frame += mask
        frame += bytes(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(bytes(frame))

    def recv(self):
        parts = []
        while True:
            b0, b1 = self._recv_exact(2)
            fin, opcode = b0 & 0x80, b0 & 0x0F
            ln = b1 & 0x7F
            if ln == 126:
                ln = struct.unpack(">H", self._recv_exact(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", self._recv_exact(8))[0]
            payload = self._recv_exact(ln) if ln else b""
            if opcode == 0x9:
                self._pong(payload)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x8:
                raise RuntimeError("websocket closed by peer")
            parts.append(payload)
            if fin:
                return b"".join(parts).decode("utf-8", "replace")

    def _pong(self, payload):
        mask = os.urandom(4)
        frame = bytearray([0x8A, 0x80 | len(payload)]) + mask
        frame += bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(frame))

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass


# --------------------------------------------------------------------------
# CDP session
# --------------------------------------------------------------------------
class CDP:
    def __init__(self, ws_url, timeout=60):
        # Parse ws://host:port/path
        rest = ws_url.split("://", 1)[1]
        hostport, _, path = rest.partition("/")
        host, _, port = hostport.partition(":")
        self.ws = RawWS(host, int(port or 80), path, timeout)
        self.n = 0

    def call(self, method, params=None, timeout_note=""):
        self.n += 1
        mid = self.n
        payload = {"id": mid, "method": method}
        if params:
            payload["params"] = params
        self.ws.send(json.dumps(payload))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError("%s: %s %s" % (method, msg["error"], timeout_note))
                return msg.get("result", {})
            # Events ignored

    def evaluate(self, expr, await_promise=False, timeout_ms=30000):
        r = self.call("Runtime.evaluate", {
            "expression": expr,
            "returnByValue": True,
            "awaitPromise": await_promise,
            "timeout": timeout_ms,
        })
        if r.get("exceptionDetails"):
            desc = r["exceptionDetails"].get("exception", {}).get("description", "")
            return None, desc or json.dumps(r["exceptionDetails"])[:300]
        return r.get("result", {}).get("value"), None

    def close(self):
        self.ws.close()


def http_json(path, port=None):
    p = port or PORT
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (p, path), timeout=10) as r:
        return json.loads(r.read().decode())


def find_edge():
    if EDGE and os.path.exists(EDGE):
        return EDGE
    candidates = [
        r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
        r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    raise RuntimeError("Edge not found")


def is_up(port=None):
    try:
        http_json("/json/version", port)
        return True
    except Exception:
        return False


def get_page_ws(port=None):
    tabs = [t for t in http_json("/json/list", port) if t.get("type") == "page"]
    if not tabs:
        raise RuntimeError("no page target")
    return tabs[0]["webSocketDebuggerUrl"]


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------
def cmd_start(ua=None):
    if is_up():
        log("cdp: already up on :%d" % PORT)
        return 0
    binary = find_edge()
    os.makedirs(PROFILE, exist_ok=True)
    args = [
        binary,
        "--user-data-dir=%s" % PROFILE,
        "--remote-debugging-port=%d" % PORT,
        "--remote-allow-origins=*",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-default-apps",
        "--disable-extensions",
        "--disable-sync",
        "--window-size=1400,1200",
        "--lang=ru-RU",
        "about:blank",
    ]
    if ua:
        args.append("--user-agent=%s" % ua)

    subprocess.Popen(args, creationflags=subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP)

    for _ in range(60):
        if is_up():
            log("cdp: Edge up on :%d" % PORT)
            return 0
        time.sleep(0.5)
    log("cdp: Edge failed to open :%d" % PORT)
    return 3


def cmd_stop():
    import subprocess as sp
    result = sp.run(['wmic', 'process', 'where', "name='msedge.exe'", 'get', 'ProcessId,CommandLine', '/format:csv'],
                    capture_output=True, text=True)
    our_pids = []
    for line in result.stdout.splitlines():
        if PROFILE.replace('\\', '\\\\') in line or PROFILE in line:
            parts = line.strip().split(',')
            if len(parts) >= 2 and parts[1].isdigit():
                our_pids.append(parts[1])

    for pid in our_pids:
        try:
            sp.run(['taskkill', '/F', '/PID', pid], capture_output=True)
            log("cdp: killed PID %s" % pid)
        except Exception as e:
            log("cdp: failed to kill PID %s: %s" % (pid, e))

    sp.run(['wmic', 'process', 'where', "CommandLine like '%%remote-debugging-port=%d%%'" % PORT, 'call', 'terminate'],
           capture_output=True)
    log("cdp: stopped")
    return 0


def cmd_status():
    print("UP" if is_up() else "DOWN")
    return 0


def attach(port=None):
    return CDP(get_page_ws(port))


def load_js(arg):
    if arg and os.path.exists(arg):
        with open(arg, "r", encoding="utf-8") as f:
            return f.read()
    return arg


DEFAULT_WAIT = ("document.readyState==='complete' && "
                "document.body && document.body.innerText.length>200")


def do_wait(cdp, pred, waitms):
    deadline = time.time() + waitms / 1000.0
    last = None
    while time.time() < deadline:
        val, err = cdp.evaluate("!!(%s)" % pred)
        last = err
        if val is True:
            return True
        time.sleep(0.5)
    if last:
        log("cdp: wait predicate error: %s" % last[:200])
    return False


def cmd_get(url, js, wait, waitms, settle, out, nonav, click, clicks, btn):
    cdp = attach()
    cdp.call("Page.enable")
    cdp.call("Runtime.enable")
    try:
        cdp.call("Network.enable")
        cdp.call("Network.setExtraHTTPHeaders",
                 {"headers": {"Accept-Language": "ru-RU,ru;q=0.9,en;q=0.8"}})
    except Exception as e:
        log("cdp: Network domain unavailable: %s" % e)

    if not nonav and url:
        cdp.call("Page.navigate", {"url": url})
        time.sleep(1.0)

    if click:
        x, y = [int(v) for v in click.split(",")]
        for i in range(1, clicks + 1):
            for typ in ("mousePressed", "mouseReleased"):
                cdp.call("Input.dispatchMouseEvent", {
                    "type": typ, "x": x, "y": y, "button": btn,
                    "clickCount": i, "buttons": 1 if btn == "left" else 2})
            time.sleep(0.12)

    ok = True
    if wait != "-":
        ok = do_wait(cdp, wait or DEFAULT_WAIT, waitms)
        log("WAIT=%s" % ("OK" if ok else "TIMEOUT"))
    if settle:
        time.sleep(settle / 1000.0)

    expr = js or "document.documentElement.outerHTML"
    val, err = cdp.evaluate(expr)
    if err:
        log("cdp: EVAL ERROR: %s" % err[:400])
        cdp.close()
        return 3

    text = val if isinstance(val, str) else json.dumps(val, ensure_ascii=False, indent=1)
    if text is None:
        text = ""

    if out:
        with open(out, "w", encoding="utf-8") as f:
            f.write(text)
        log("cdp: %d chars -> %s" % (len(text), out))
    else:
        sys.stdout.write(text)

    cdp.close()
    return 0 if ok else 4


def cmd_screenshot(out=None):
    cdp = attach()
    cdp.call("Page.enable")
    result = cdp.call("Page.captureScreenshot", {"format": "png"})
    cdp.close()

    if "data" in result:
        data = base64.b64decode(result["data"])
        path = out or os.path.join(STATE_DIR, "screenshot.png")
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)
        log("cdp: screenshot %d bytes -> %s" % (len(data), path))
        return 0
    log("cdp: screenshot failed")
    return 3


def cmd_cookies(url=None):
    cdp = attach()
    cdp.call("Network.enable")
    ck = cdp.call("Network.getCookies", {"urls": [url]} if url else {})
    cdp.close()
    print("; ".join("%s=%s" % (c["name"], c["value"]) for c in ck.get("cookies", [])))
    return 0


# --------------------------------------------------------------------------
# RU-CENTER specific helpers
# --------------------------------------------------------------------------
def cmd_ru_center_login(cred_path, out_dir=None):
    """Login to RU-CENTER using DPAPI-encrypted credentials."""
    out_dir = out_dir or os.path.join(STATE_DIR, "ru-center-output")
    os.makedirs(out_dir, exist_ok=True)
    creds = load_credentials(cred_path)
    login = creds['login']
    password = creds['password']
    log("cdp: credentials loaded for %s" % login)

    # Navigate to auth page
    result = cmd_get("https://www.nic.ru/auth/", None, DEFAULT_WAIT, 25000, 2000,
                     os.path.join(out_dir, "ru-auth-page.html"), False, None, 1, "left")
    if result != 0:
        return result

    # Fill and submit form via CDP
    cdp = attach()
    cdp.call("Page.enable")
    cdp.call("Runtime.enable")

    # Fill login
    fill_login = """
    (function() {
        var el = document.querySelector('input[name="login"], input[id="login"], input[type="email"]');
        if (!el) el = document.querySelector('form input[type="text"]');
        if (el) { el.focus(); el.value = '%s'; el.dispatchEvent(new Event('input', {bubbles:true})); return 'ok'; }
        return 'not found';
    })()
    """ % login.replace("'", "\\'")

    val, err = cdp.evaluate(fill_login)
    log("cdp: fill login: %s" % val)

    # Fill password
    fill_pass = """
    (function() {
        var el = document.querySelector('input[type="password"], input[name="password"]');
        if (el) { el.focus(); el.value = '%s'; el.dispatchEvent(new Event('input', {bubbles:true})); return 'ok'; }
        return 'not found';
    })()
    """ % password.replace("'", "\\'")

    val, err = cdp.evaluate(fill_pass)
    log("cdp: fill password: %s" % val)

    # Submit
    submit = """
    (function() {
        var btn = document.querySelector('button[type="submit"], input[type="submit"]');
        if (btn) { btn.click(); return 'clicked'; }
        var form = document.querySelector('form');
        if (form) { form.submit(); return 'submitted'; }
        return 'no submit';
    })()
    """
    val, err = cdp.evaluate(submit)
    log("cdp: submit: %s" % val)

    time.sleep(5)

    # Check result
    check = """
    (function() {
        var html = document.body.innerHTML.toLowerCase();
        var url = location.href;
        if (html.includes('captcha') || html.includes('капча')) return 'BLOCKED:CAPTCHA';
        if (html.includes('код подтверждения') || html.includes('sms') || html.includes('двухфакторн')) return 'BLOCKED:MFA';
        if (html.includes('блокировка') || html.includes('заблокирован')) return 'BLOCKED:ACCOUNT';
        if (html.includes('неверный') || html.includes('error')) return 'ERROR:INVALID';
        if (url.includes('lk') || url.includes('manager') || url.includes('cabinet')) return 'SUCCESS';
        return 'UNKNOWN:' + url;
    })()
    """
    status, err = cdp.evaluate(check)
    log("cdp: status: %s" % status)

    # Save post-login page
    html, _ = cdp.evaluate("document.documentElement.outerHTML")
    if html:
        with open(os.path.join(out_dir, "ru-after-login.html"), "w", encoding="utf-8") as f:
            f.write(html)

    cdp.close()

    # Write status
    with open(os.path.join(out_dir, "RU_LOGIN_STATUS.txt"), "w") as f:
        f.write("STATUS: %s\n" % status)

    if status == "SUCCESS":
        return 0
    elif status.startswith("BLOCKED"):
        return 5
    else:
        return 3


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 3
    cmd, a = a[0], a[1:]

    def opt(name, default=None):
        if name in a:
            return a[a.index(name) + 1]
        return default

    ua = opt("--ua", os.environ.get("EDGE_CDP_UA", UA_DEFAULT))

    if cmd == "start":
        return cmd_start(ua)
    if cmd == "stop":
        return cmd_stop()
    if cmd == "status":
        return cmd_status()
    if cmd == "screenshot":
        return cmd_screenshot(opt("--out"))

    url = a[0] if a and not a[0].startswith("--") else ""
    js = load_js(opt("--js"))
    wait = opt("--wait")
    waitms = int(opt("--waitms", "25000"))
    settle = int(opt("--settle", "0"))
    out = opt("--out")
    click = opt("--click")
    clicks = int(opt("--clicks", "1"))
    btn = opt("--btn", "left")
    nonav = cmd in ("eval", "click") or "--nonav" in a

    if cmd == "click" and url and not click:
        click = url

    if cmd in ("get", "eval", "click"):
        if cmd != "get" and not wait:
            wait = "-"
        return cmd_get(url, js, wait, waitms, settle, out, nonav, click, clicks, btn)

    if cmd == "cookies":
        return cmd_cookies(url)

    if cmd == "ru-center-login":
        cred_path = opt("--creds", os.path.join(STATE_DIR, "credentials.dpapi"))
        return cmd_ru_center_login(cred_path, opt("--out-dir"))

    log("cdp: unknown command %r" % cmd)
    return 3


if __name__ == "__main__":
    sys.exit(main())
