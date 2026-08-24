#!/bin/bash
# statkassa_lan_scp.sh <local> <remote> | --from <remote> <local> — файлы на кассу РМК по ЛОКАЛЬНОЙ
# сети. 🔴 Крупные файлы возить ТОЛЬКО так: через VPS-туннель 2250 они рвутся молча (T299).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LPORT="${STATKASSA_LAN_PORT:-12250}"
bash "$DIR/statkassa_lan_ssh.sh" 'cd .' >/dev/null 2>&1 || true
OPTS=(-i "$DIR/ssh_channel/statkassa_me" -P "$LPORT" -o User=днс
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
      -o ConnectTimeout=25 -o BatchMode=yes)
if [ "${1:-}" = "--from" ]; then exec scp "${OPTS[@]}" "127.0.0.1:$2" "$3"
else exec scp "${OPTS[@]}" "$1" "127.0.0.1:${2}"; fi
