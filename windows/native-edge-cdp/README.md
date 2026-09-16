# Native Microsoft Edge control on Windows

This directory contains a Windows-native browser-control path for tasks that
do not need the Linux VNC desktop. `cdp/edge_cdp.py` starts Microsoft Edge with
an isolated profile and controls it through Chrome DevTools Protocol using the
Python standard library only.

It does **not** require WSL, Xvfb, x11vnc, Selenium, Playwright, or third-party
Python packages.

## Requirements

- Windows 10 or 11
- Microsoft Edge
- Python 3.11 or newer

## Quick start

Run these commands in PowerShell from this directory:

```powershell
$env:EDGE_CDP_PORT = '19444'
$env:EDGE_CDP_PROFILE = "$env:LOCALAPPDATA\VncWorkEdge\profile"

python .\cdp\edge_cdp.py start
python .\cdp\edge_cdp.py status
python .\cdp\edge_cdp.py get https://example.com/ --wait "document.title==='Example Domain'"
python .\cdp\edge_cdp.py screenshot --out "$env:TEMP\edge-cdp.png"
python .\cdp\edge_cdp.py stop
```

The default CDP port is `19444`. The default profile is
`%LOCALAPPDATA%\VncWorkEdge\profile`. Override the Edge executable with
`EDGE_CDP_BINARY` when Edge is installed in a nonstandard location.

Available commands are printed by running `python .\cdp\edge_cdp.py` without
arguments. Reusable JavaScript expressions are under `cdp/js/` and can be
passed with `--js`.

## Smoke test

```powershell
python .\smoke_test.py
```

The suite uses port `19445` and the disposable profile
`%LOCALAPPDATA%\VncWorkEdgeSmoke\profile`. It covers startup, target discovery,
navigation, screenshot capture, DOM evaluation, mouse input, and shutdown.
Success is reported as `10/10 passed`.

## Profile isolation and security

- Give each concurrent task a unique `EDGE_CDP_PORT` and
  `EDGE_CDP_PROFILE`.
- Never run the smoke test against an authenticated profile.
- Browser profiles, cookies, screenshots, page dumps, and `.dpapi` files are
  runtime data. Do not commit or share them.
- `ru-center-login` accepts a CurrentUser DPAPI-encrypted JSON credential file
  via `--creds`. No credentials are stored in this repository.
- `stop` selects Edge processes by the configured profile and debugging port;
  it is intentionally scoped instead of terminating all Edge instances.

An authenticated profile can be opened once by a human and then reused by the
same Windows user by keeping `EDGE_CDP_PROFILE` unchanged. Copy or archive that
profile only while all Edge processes using it are stopped.
