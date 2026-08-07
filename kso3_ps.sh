#!/bin/bash
# kso3_ps.sh — run a PowerShell script block on KSO #3 via EncodedCommand (UTF-16LE), clean output.
# Same contract as kso_ps.sh (cash #1) / kso2_ps.sh, but over the 2247 tunnel.
#   printf '%s' 'Get-Date' | bash /work/vnc_work_v2-vm121-review/kso3_ps.sh
#   bash /work/vnc_work_v2-vm121-review/kso3_ps.sh <<'PS'
#   ... script ...
#   PS
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh with signal 16.
# 🔴 -Wow64 as first arg runs the 32-bit PowerShell (SysWOW64) — required for AddIn.Fptr10 (ATOL COM).
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
PSEXE='powershell'
if [ "${1:-}" = "-Wow64" ]; then
  PSEXE='C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
  shift
fi
SCRIPT="$(cat)"
B64=$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/kso3_ssh.sh" "$PSEXE -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
