#!/usr/bin/env bash
set -euo pipefail

# Direct interactive terminal to VM121 (claw-second-llm).
# Secrets are not stored here: srv1 password is read at runtime from the private access file.

ACCESS_FILE="${ACCESS_FILE:-/work/claster/llm-gpu-storage-cluster-20260527/private/access.md}"
JUMP_KEY="${JUMP_KEY:-/root/.ssh/ke_tunnel}"
JUMP_HOST="${JUMP_HOST:-178.253.55.128}"
SRV1_HOST="${SRV1_HOST:-134.0.107.8}"
SRV1_PORT="${SRV1_PORT:-234}"
VM121_HOST="${VM121_HOST:-192.168.87.33}"
VM121_USER="${VM121_USER:-ubuntu}"
VM121_KEY_ON_SRV1="${VM121_KEY_ON_SRV1:-/root/.ssh/vm-121-claw-second-llm-ed25519}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 127; }; }
need ssh
need sshpass
need python3

if [[ ! -r "$ACCESS_FILE" ]]; then
  echo "Cannot read access file: $ACCESS_FILE" >&2
  exit 1
fi
if [[ ! -r "$JUMP_KEY" ]]; then
  echo "Cannot read jump key: $JUMP_KEY" >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT
PASSFILE="$TMPDIR/srv1.pass"
python3 - <<'PY' "$ACCESS_FILE" "$PASSFILE"
from pathlib import Path
import sys
access = Path(sys.argv[1])
out = Path(sys.argv[2])
pw = None
for line in access.read_text(errors='replace').splitlines():
    if '| GPU node 1 ' in line:
        cells = [c.strip().strip('`') for c in line.strip().strip('|').split('|')]
        if len(cells) >= 6:
            pw = cells[5]
            break
if not pw:
    raise SystemExit('srv1 credential not found in access file')
out.write_text(pw, encoding='utf-8')
out.chmod(0o600)
PY

JUMP_CMD="ssh -i $JUMP_KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/omx_jump_known_hosts -W %h:%p root@$JUMP_HOST"
BASE_SSH=(
  sshpass -f "$PASSFILE" ssh
  -o PreferredAuthentications=password,keyboard-interactive
  -o PubkeyAuthentication=no
  -o NumberOfPasswordPrompts=1
  -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile=/tmp/omx_target_known_hosts
  -o ConnectTimeout=10
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=3
  -o ProxyCommand="$JUMP_CMD"
  -p "$SRV1_PORT"
  root@"$SRV1_HOST"
)

VM121_SSH="ssh -tt -i '$VM121_KEY_ON_SRV1' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new '$VM121_USER@$VM121_HOST'"

if [[ "${1:-}" == "--check" ]]; then
  exec "${BASE_SSH[@]}" "ssh -i '$VM121_KEY_ON_SRV1' -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new '$VM121_USER@$VM121_HOST' 'hostname; echo VM121_OK; command -v run-claw-gemma2; curl -fsS http://192.168.87.100:8081/health'"
fi

echo "Opening VM121 terminal: $VM121_USER@$VM121_HOST"
echo "Inside VM121 run: run-claw-gemma2"
echo
exec "${BASE_SSH[@]}" -tt "$VM121_SSH"
