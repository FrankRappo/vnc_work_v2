#!/bin/bash
# Template SOCKS5 tunnel launcher for geo-restricted web apps.
#
# Fill real values via environment variables or ignored local wrappers.

set -u

PORT="${SOCKS_PORT:-1080}"
EXPECT_IP="${SOCKS_EXPECT_IP:-}"
JUMP1_HOST="${SOCKS_JUMP1_HOST:-jump1.example.com}"
JUMP1_USER="${SOCKS_JUMP1_USER:-root}"
JUMP1_PASSWORD="${SOCKS_JUMP1_PASSWORD:-}"
EXIT_HOST="${SOCKS_EXIT_HOST:-exit.example.com}"
EXIT_USER="${SOCKS_EXIT_USER:-root}"

raise() {
  if [ -z "$JUMP1_PASSWORD" ]; then
    echo "[X] SOCKS_JUMP1_PASSWORD is required"
    return 1
  fi
  ssh -o ProxyCommand="sshpass -p $JUMP1_PASSWORD ssh -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o IPQoS=cs1 -W %h:%p ${JUMP1_USER}@${JUMP1_HOST}" \
      -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o IPQoS=cs1 \
      -o ServerAliveInterval=30 -o TCPKeepAlive=yes \
      -fN -D 127.0.0.1:$PORT ${EXIT_USER}@${EXIT_HOST} </dev/null
}

exit_ip() {
  curl -s -m 15 --socks5 127.0.0.1:$PORT https://api.ipify.org 2>/dev/null
}

case "${1:-up}" in
  up)
    ip="$(exit_ip)"
    if [ -n "$EXPECT_IP" ] && [ "$ip" = "$EXPECT_IP" ]; then
      echo "[=] already up, exit IP=$ip"
      exit 0
    fi
    echo "[+] starting SOCKS on 127.0.0.1:$PORT (${JUMP1_HOST} -> ${EXIT_HOST})"
    pkill -f "D 127.0.0.1:$PORT" 2>/dev/null || true
    raise || exit 1
    ip="$(exit_ip)"
    if [ -n "$EXPECT_IP" ]; then
      [ "$ip" = "$EXPECT_IP" ] && echo "[OK] SOCKS up, exit IP=$ip" || { echo "[X] exit IP '$ip', expected '$EXPECT_IP'"; exit 1; }
    else
      echo "[OK] SOCKS status check: exit IP=${ip:-unknown}"
    fi
    ;;
  status)
    if ss -ltn 2>/dev/null | grep -q "127.0.0.1:$PORT "; then echo "port $PORT listening"; else echo "port $PORT down"; fi
    pgrep -af "D 127.0.0.1:$PORT" | grep -v grep | cut -c1-120 || echo "(no tunnel process)"
    echo "exit IP=$(exit_ip)"
    ;;
  down)
    pkill -f "D 127.0.0.1:$PORT" 2>/dev/null && echo "[+] tunnel down" || echo "[=] tunnel not running"
    ;;
  *)
    echo "usage: $0 {up|status|down}"
    exit 2
    ;;
esac
