#!/bin/bash
# kso_ps.sh — run a PowerShell script block on the cash via EncodedCommand (UTF-16LE), clean output.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cat)"
B64=$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/kso_ssh.sh" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
