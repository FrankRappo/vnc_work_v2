#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cdp_linux.py -- dependency-free Chrome DevTools Protocol driver for LINUX hosts.

WHY THIS EXISTS
    cdp/ already drives a headless Chrome on a *Windows* box (cdp_start.ps1 +
    cdp_get.ps1).  This is its Linux twin, needed whenever the browser has to
    live on a plain Linux host -- e.g. our Russian VPS jump box (T198): the RU
    shops that matter either geo-block our LAN IP or answer plain curl with a
    Qrator / DDoS-Guard JS challenge (dns-shop.ru -> HTTP 401 + 6 KB of JS).
    A real browser solves the challenge, stores the cookie and renders the page;
    curl never can.

    Same contract as the Windows path: the expensive agent never loads a
    screenshot -- pages come back as TEXT, greppable, cheap.

WHY STDLIB ONLY
    The VPS has python3 and google-chrome, but no pip, no node, no
    websocket-client.  Installing packages onto a shared jump host that carries
    every reverse tunnel is not something a research task gets to do.  So the
    RFC6455 client below is hand-rolled on top of `socket` (~90 lines).

USAGE
    ./cdp_linux.py start [--port 9222] [--ua UA]      # idempotent launch
    ./cdp_linux.py get URL [--js EXPR_OR_FILE] [--wait PRED] [--waitms N]
                           [--settle MS] [--out FILE]
    ./cdp_linux.py eval --js EXPR_OR_FILE            # act on the page already open
    ./cdp_linux.py click X,Y [--clicks N] [--btn left|right]
    ./cdp_linux.py cookies [--url URL]
    ./cdp_linux.py stop

    Default expression is document.documentElement.outerHTML.  `--js` takes an
    inline JS expression or a path to a file holding one (cdp/js/*.js work
    as-is).  Exit code 0 = got a value, 4 = WAIT=TIMEOUT, 3 = driver error.

GOTCHAS worth the debugging rounds they cost (Linux-specific; the Windows list
lives in cdp/README.md):
  * Chrome >=112 needs `--headless=new`; the old `--headless` silently ignores
    part of the flags.  `--dump-dom` still cannot pass a JS challenge (it does
    one navigation and exits, the challenge needs cookie-then-reload), which is
    exactly why we go through the debugging port.
  * Running as root on a VPS requires `--no-sandbox`, and `--disable-dev-shm-usage`
    or Chrome dies on the small /dev/shm containers give you.
  * Headless Chrome puts `HeadlessChrome/<ver>` in its User-Agent and antibots
    read it.  We override the UA at launch AND via Network.setUserAgentOverride.
  * A JS challenge resolves by *reloading itself*.  Navigating once and reading
    immediately gives you the challenge page.  `--wait` polls a predicate
    (default: "page is not the challenge") instead of betting on a fixed sleep.
"""

import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import sys
import time
import urllib.request

PORT = int(os.environ.get("CDP_PORT", "9222"))
PROFILE = os.environ.get("CDP_PROFILE", "/tmp/cdp-profile")
CHROME = os.environ.get("CDP_CHROME", "")
UA_DEFAULT = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
              "Chrome/148.0.0.0 Safari/537.36")


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# minimal RFC6455 client -- text frames only, which is all CDP speaks
# --------------------------------------------------------------------------
class WS:
    def __init__(self, url, timeout=60):
        # ws://127.0.0.1:9222/devtools/page/<id>
        rest = url.split("://", 1)[1]
        hostport, _, path = rest.partition("/")
        host, _, port = hostport.partition(":")
        self.sock = socket.create_connection((host, int(port or 80)), timeout=15)
        self.sock.settimeout(timeout)
        self.buf = b""
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            "GET /%s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n" % (path, hostport, key)
        )
        self.sock.sendall(req.encode())
        hdr = self._read_until(b"\r\n\r\n")
        if b" 101 " not in hdr.split(b"\r\n")[0]:
            raise RuntimeError("websocket handshake failed: %r" % hdr[:200])
        magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"   # RFC6455 handshake GUID
        accept = base64.b64encode(
            hashlib.sha1((key + magic).encode()).digest()).decode()
        if accept.encode() not in hdr:
            # not fatal (CDP is localhost-only), but a real mismatch means the
            # handshake maths is wrong -- verified against the RFC6455 test
            # vector: key dGhlIHNhbXBsZSBub25jZQ== -> s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
            log("cdp: warning: Sec-WebSocket-Accept mismatch (continuing)")

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
        """Return one complete text message (handles fragmentation + ping)."""
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
            if opcode == 0x9:                      # ping -> pong, keep reading
                self._pong(payload)
                continue
            if opcode == 0xA:                      # pong
                continue
            if opcode == 0x8:                      # close
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
        self.ws = WS(ws_url, timeout)
        self.n = 0

    def call(self, method, params=None, timeout_note=""):
        self.n += 1
        mid = self.n
        self.ws.send(json.dumps({"id": mid, "method": method,
                                 "params": params or {}}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError("%s: %s %s" % (method, msg["error"], timeout_note))
                return msg.get("result", {})
            # events are ignored; we poll instead of listening (simpler + robust)

    def evaluate(self, expr, await_promise=False):
        r = self.call("Runtime.evaluate", {
            "expression": expr,
            "returnByValue": True,
            "awaitPromise": await_promise,
            "timeout": 30000,
        })
        if r.get("exceptionDetails"):
            desc = r["exceptionDetails"].get("exception", {}).get("description", "")
            return None, desc or json.dumps(r["exceptionDetails"])[:300]
        return r.get("result", {}).get("value"), None


def http_json(path):
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (PORT, path), timeout=10) as r:
        return json.loads(r.read().decode())


def find_chrome():
    if CHROME:
        return CHROME
    for c in ("google-chrome", "google-chrome-stable", "chromium",
              "chromium-browser", "/opt/chrome-linux/chrome"):
        p = subprocess.run(["bash", "-lc", "command -v %s" % c],
                           capture_output=True, text=True)
        if p.returncode == 0 and p.stdout.strip():
            return p.stdout.strip()
    raise RuntimeError("no chrome binary found (set CDP_CHROME)")


def is_up():
    try:
        http_json("/json/version")
        return True
    except Exception:
        return False


def cmd_start(ua):
    if is_up():
        log("cdp: already up on :%d" % PORT)
        return 0
    binary = find_chrome()
    os.makedirs(PROFILE, exist_ok=True)
    args = [
        binary, "--headless=new", "--remote-debugging-port=%d" % PORT,
        "--remote-allow-origins=*",
        "--user-data-dir=%s" % PROFILE,
        "--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu",
        "--window-size=1400,2400", "--lang=ru-RU",
        "--user-agent=%s" % ua,
        "--disable-blink-features=AutomationControlled",
        "about:blank",
    ]
    with open("/tmp/cdp_chrome.log", "ab") as lg:
        subprocess.Popen(args, stdout=lg, stderr=lg,
                         start_new_session=True)
    for _ in range(60):
        if is_up():
            log("cdp: chrome up on :%d (%s)" % (PORT, binary))
            return 0
        time.sleep(0.5)
    log("cdp: chrome failed to open :%d -- see /tmp/cdp_chrome.log" % PORT)
    return 3


def cmd_stop():
    subprocess.run(["pkill", "-f", "remote-debugging-port=%d" % PORT])
    log("cdp: stopped")
    return 0


def attach():
    tabs = [t for t in http_json("/json/list") if t.get("type") == "page"]
    if not tabs:
        raise RuntimeError("no page target; run `cdp_linux.py start`")
    return CDP(tabs[0]["webSocketDebuggerUrl"])


def load_js(arg):
    if arg and os.path.exists(arg):
        with open(arg, "r", encoding="utf-8") as f:
            return f.read()
    return arg


# Default predicate: "we are past the antibot interstitial".  Qrator/DDoS-Guard
# challenge pages are tiny and carry no rendered text, so a body with real text
# and no challenge marker means the real page arrived.
DEFAULT_WAIT = ("document.readyState==='complete' && "
                "document.body && document.body.innerText.length>200 && "
                "!/qrator|__jhash_|ddos-guard|Проверка браузера/i.test("
                "document.documentElement.outerHTML.slice(0,4000))")


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

    if not nonav:
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
        return 3
    text = val if isinstance(val, str) else json.dumps(val, ensure_ascii=False, indent=1)
    if text is None:
        log("cdp: EVAL=NULL")
        text = ""
    if out:
        with open(out, "w", encoding="utf-8") as f:
            f.write(text)
        log("cdp: %d chars -> %s" % (len(text), out))
    else:
        sys.stdout.write(text)
    return 0 if ok else 4


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

    ua = opt("--ua", os.environ.get("CDP_UA", UA_DEFAULT))
    if cmd == "start":
        return cmd_start(ua)
    if cmd == "stop":
        return cmd_stop()
    if cmd == "status":
        print("UP" if is_up() else "DOWN")
        return 0

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
        cdp = attach()
        cdp.call("Network.enable")
        ck = cdp.call("Network.getCookies", {"urls": [url]} if url else {})
        print("; ".join("%s=%s" % (c["name"], c["value"])
                        for c in ck.get("cookies", [])))
        return 0
    log("cdp: unknown command %r" % cmd)
    return 3


if __name__ == "__main__":
    sys.exit(main())
