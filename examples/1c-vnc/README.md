# 1C over VNC examples

Sanitized examples derived from real 1C Fresh / VNC operating scripts.

These files are **templates**, not drop-in production scripts:

- no real credentials
- no real jump-host passwords
- no client-specific URLs
- no screenshots or persisted sessions

Use them when a 1C web client is too fragile for DOM/CDP automation and a
coordinate-driven VNC workflow is more reliable.

## Included files

- `vnc_1c.example.sh` — bring up/down a 1C browser session in Xvfb + x11vnc
- `socks_tunnel.example.sh` — template for an external SOCKS5 jump tunnel
- `1c_setup/lib_1c.sh` — coordinate-driving primitives (`xdotool`, `xclip`, `scrot`)
- `1c_setup/login_1c.sh` — login flow using env-provided username/password
- `1c_setup/release_session.sh` — logout flow to free the 1C seat
- `1c_setup/socks_keepalive.sh` — keepalive loop for unstable SOCKS tunnels
- `1c_setup/1C_CALIBRATION.md` — calibration notes and placeholder coordinates

## Required environment

Set real values outside git:

```bash
export IC_URL='https://your-1c-host.example.com/app/'
export IC_USERNAME='Your User'
export IC_PASSWORD='your-password'
export VNC_SOCKS='socks5://127.0.0.1:1080'
```

Optional:

```bash
export IC_SHOTS_DIR=/tmp/1c_vnc_shots
export SOCKS_PORT=1080
```

## Typical flow

```bash
bash examples/1c-vnc/vnc_1c.example.sh up
bash examples/1c-vnc/1c_setup/login_1c.sh
# ... perform task via VNC / xdotool / screenshots ...
bash examples/1c-vnc/1c_setup/release_session.sh
bash examples/1c-vnc/vnc_1c.example.sh down
```

## Safety notes

- Keep credentials in environment variables or ignored local files only.
- Recalibrate coordinates for your 1C instance and screen geometry.
- Always log out: many 1C setups allow only one active seat/session.
