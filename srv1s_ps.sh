#!/bin/bash
# srv1s_ps.sh — run a PowerShell script block on SERVER-1S (VPS port 2248) via EncodedCommand
# (UTF-16LE, so Cyrillic survives), clean output. Script text comes from stdin.
# 🔴 Run with dangerouslyDisableSandbox.
#   echo 'hostname' | bash srv1s_ps.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cat)"
B64=$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/srv1s_ssh.sh" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
