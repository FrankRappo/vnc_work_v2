#!/bin/bash
# srv_ps.sh — run a PowerShell script block on the 1C-server box (DESKTOP-VGVHEOU, port 2244)
# via EncodedCommand (UTF-16LE), clean output. Script text comes from stdin.
# 🔴 Run with dangerouslyDisableSandbox (ssh is killed by the sandbox).
#   echo 'hostname' | bash srv_ps.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cat)"
B64=$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/srv_ssh.sh" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
