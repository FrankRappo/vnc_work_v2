#!/bin/bash
# statkassa_lan_ps.sh — PowerShell на кассе РМК через ЛОКАЛЬНУЮ сеть (statkassa_lan_ssh.sh).
# Тело скрипта со stdin, кириллица переживает -EncodedCommand (UTF-16LE).
# 🔴 Запускать с dangerouslyDisableSandbox.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cat)"
B64=$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/statkassa_lan_ssh.sh" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
