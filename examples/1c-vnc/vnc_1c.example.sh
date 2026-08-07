#!/bin/bash
# Example VNC launcher for a 1C web session.
#
# Template only:
# - provide IC_URL yourself
# - provide a working SOCKS tunnel yourself (optional)
# - calibrate coordinates separately

set -u

DISP="${VNC_DISPLAY:-:98}"
SCREEN="${VNC_SCREEN:-1920x1080x24}"
VNC_PORT="${VNC_PORT:-5901}"
CDP_PORT="${VNC_CDP:-9334}"
SOCKS="${VNC_SOCKS:-}"
IC_URL="${IC_URL:-https://your-1c-host.example.com/app/}"
PROFILE="${VNC_PROFILE:-/tmp/chromium-1c-profile}"
SCREENS_DIR="${IC_SHOTS_DIR:-/tmp/1c_vnc_shots}"

case "${1:-up}" in
  up)
    if curl -s -m3 "http://127.0.0.1:$CDP_PORT/json/version" >/dev/null 2>&1; then
      echo "[=] stack already up (CDP $CDP_PORT)"
      exit 0
    fi
    mkdir -p "$PROFILE" "$SCREENS_DIR"
    rm -f "$PROFILE"/Singleton* "$PROFILE"/DevToolsActivePort 2>/dev/null || true
    rm -f "/tmp/.X${DISP#:}-lock" 2>/dev/null || true
    [ -e "/tmp/.X11-unix/X${DISP#:}" ] && rm -f "/tmp/.X11-unix/X${DISP#:}" 2>/dev/null || true
    for p in "Xvfb $DISP" "fluxbox.*$DISP" "x11vnc.*$VNC_PORT"; do pkill -f "$p" 2>/dev/null || true; done
    sleep 1
    runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin \
      Xvfb "$DISP" -screen 0 "$SCREEN" -nolisten tcp >>/tmp/1c-vnc.log 2>&1 &
    sleep 2
    runuser -u hgff -- env DISPLAY="$DISP" xdpyinfo >/dev/null 2>&1 || { echo "[X] Xvfb failed"; exit 1; }
    runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" \
      fluxbox >>/tmp/1c-vnc.log 2>&1 &
    sleep 2
    PROXY_ARGS=()
    if [ -n "$SOCKS" ]; then
      PROXY_ARGS+=( "--proxy-server=$SOCKS" )
    fi
    setsid runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin DISPLAY="$DISP" \
      LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
      /usr/local/bin/chromium --no-sandbox --disable-setuid-sandbox \
      --remote-debugging-port="$CDP_PORT" --user-data-dir="$PROFILE" \
      --no-first-run --no-default-browser-check --disable-extensions --password-store=basic \
      "${PROXY_ARGS[@]}" \
      --window-position=0,0 --window-size=1920,1080 --new-window "$IC_URL" \
      >>/tmp/1c-vnc.log 2>&1 </dev/null &
    sleep 4
    runuser -u hgff -- env -i HOME=/home/hgff PATH=/usr/local/bin:/usr/bin:/bin \
      x11vnc -display "$DISP" -rfbport "$VNC_PORT" -localhost -nopw -forever -shared -quiet \
      >>/tmp/1c-vnc.log 2>&1 &
    sleep 2
    WIN=$(runuser -u hgff -- env DISPLAY="$DISP" xdotool search --class chromium 2>/dev/null | head -1)
    [ -n "$WIN" ] && runuser -u hgff -- env DISPLAY="$DISP" xdotool windowsize "$WIN" 1920 1080 2>/dev/null
    echo "[OK] 1C VNC stack up. VNC=localhost:$VNC_PORT CDP=$CDP_PORT URL=$IC_URL"
    ;;
  shot)
    # A frame must never be inherited from an earlier run: delete first, fail loudly, print the
    # capture time (kso-anydesk-stale-frame, 2026-08-05 — a July frame passed for "now").
    label="${2:-shot}"
    rm -f "$SCREENS_DIR/$label.jpg"
    if ! runuser -u hgff -- env DISPLAY="$DISP" scrot -o "$SCREENS_DIR/$label.jpg" || [ ! -s "$SCREENS_DIR/$label.jpg" ]; then
      rm -f "$SCREENS_DIR/$label.jpg"
      echo "SHOT_FAIL: no frame from $DISP (nothing left at $SCREENS_DIR/$label.jpg)" >&2
      exit 1
    fi
    echo "shot $(date '+%Y-%m-%d %H:%M:%S') DISPLAY=$DISP"
    echo "$SCREENS_DIR/$label.jpg"
    ;;
  status)
    curl -s -m3 "http://127.0.0.1:$CDP_PORT/json/version" >/dev/null 2>&1 && echo "chromium/CDP: OK" || echo "chromium/CDP: down"
    ss -ltn 2>/dev/null | grep -q ":$VNC_PORT " && echo "x11vnc $VNC_PORT: listening" || echo "x11vnc $VNC_PORT: down"
    ;;
  down)
    pkill -f "remote-debugging-port=$CDP_PORT" 2>/dev/null || true
    pkill -f "x11vnc.*$VNC_PORT" 2>/dev/null || true
    pkill -f "fluxbox.*$DISP" 2>/dev/null || true
    pkill -f "Xvfb $DISP" 2>/dev/null || true
    echo "[OK] 1C VNC stack down"
    ;;
  *)
    echo "usage: $0 {up|shot <label>|status|down}"
    exit 2
    ;;
esac
