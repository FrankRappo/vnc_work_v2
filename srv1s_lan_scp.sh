#!/bin/bash
# srv1s_lan_scp.sh <local> <remote>   |   srv1s_lan_scp.sh --from <remote> <local>
# Копирование файлов на/с SERVER-1S через ЛОКАЛЬНУЮ сеть (форвард поднимает srv1s_lan_ssh.sh).
# 🔴 Запускать с dangerouslyDisableSandbox.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
LPORT="${SRV1S_LAN_PORT:-12248}"
bash "$DIR/srv1s_lan_ssh.sh" 'cd .' >/dev/null 2>&1 || true
OPTS=(-i "$DIR/ssh_channel/srv1s_me" -P "$LPORT" -o User=User
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
      -o ConnectTimeout=25 -o BatchMode=yes)
if [ "${1:-}" = "--from" ]; then
  exec scp "${OPTS[@]}" "127.0.0.1:$2" "$3"
else
  exec scp "${OPTS[@]}" "$1" "127.0.0.1:$2"
fi
