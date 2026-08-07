#!/bin/bash
# kso2_ps.sh — run a PowerShell script block on KSO #2 via EncodedCommand (UTF-16LE), clean output.
# Same contract as kso_ps.sh (cash #1) / kso3_ps.sh (cash #3), but over the 2246 tunnel (kso2_ssh.sh).
# Added by T173 (2026-08-05): the helper was simply missing for cash #2 — every other cash had one,
# so multi-till work had to fall back to raw ssh + cmd quoting, which mangles Cyrillic (cp866).
#   printf '%s' 'Get-Date' | bash /work/vnc_work_v2-vm121-review/kso2_ps.sh
#   bash /work/vnc_work_v2-vm121-review/kso2_ps.sh <<'PS'
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
bash "$DIR/kso2_ssh.sh" "$PSEXE -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
