#!/bin/bash
# Keepalive loop for an externally managed SOCKS tunnel.

PORT="${SOCKS_PORT:-1080}"
CHECK_CMD="${SOCKS_CHECK_CMD:-ss -ltn | grep -q \"127.0.0.1:${PORT} \"}"
RAISE_CMD="${SOCKS_RAISE_CMD:-bash ../socks_tunnel.example.sh up}"
PIDF="/tmp/socks_keepalive_${PORT}.pid"

case "${1:-start}" in
  start)
    echo $$ > "$PIDF"
    echo "[keepalive] start pid=$$ port=$PORT"
    while true; do
      if ! eval "$CHECK_CMD" >/dev/null 2>&1; then
        echo "[keepalive] $(date +%H:%M:%S) port $PORT down -> raise"
        eval "$RAISE_CMD" >/dev/null 2>&1
      fi
      sleep 6
    done
    ;;
  stop)
    if [ -f "$PIDF" ]; then
      kill "$(cat "$PIDF")" 2>/dev/null && echo "[keepalive] stopped pid=$(cat "$PIDF")" || echo "[keepalive] pid not alive"
      rm -f "$PIDF"
    else
      echo "[keepalive] no pid file"
    fi
    ;;
  status)
    if [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then
      echo "[keepalive] alive pid=$(cat "$PIDF")"
    else
      echo "[keepalive] not running"
    fi
    ;;
  *)
    echo "usage: $0 {start|stop|status}"
    exit 2
    ;;
esac
