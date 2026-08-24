#!/bin/bash
# srv1s_lan_ps.sh — то же, что srv1s_ps.sh, но через ЛОКАЛЬНУЮ сеть (srv1s_lan_ssh.sh).
# Текст скрипта с stdin, кириллица переживает переход через -EncodedCommand (UTF-16LE).
# 🔴 Запускать с dangerouslyDisableSandbox.
#   echo 'hostname' | bash srv1s_lan_ps.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cat)"
B64=$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/srv1s_lan_ssh.sh" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
