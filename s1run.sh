#!/bin/bash
# s1run.sh <local_ps_script> [remote_out_file] [local_out_file] [wait_secs]
# Push a PowerShell script to the cash, run it in the INTERACTIVE session 1 (scheduled task,
# LogonType Interactive, RunLevel Highest -> can see/drive session-1 GUI, no UAC prompt), then
# optionally pull an output file the script wrote. Call THIS with dangerouslyDisableSandbox=true.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$1"
REMOTE_OUT="${2:-}"
LOCAL_OUT="${3:-}"
WAITS="${4:-4}"
[ -f "$SCRIPT" ] || { echo "no script: $SCRIPT"; exit 2; }
# push script (as-is; assume ascii/utf8 content, converted to remote UTF-8)
bash "$DIR/kso_scp.sh" "$SCRIPT" kso:C:/kso/_t10/_s1.ps1 >/dev/null 2>&1 || { echo "scp script failed"; exit 3; }
REG='$ErrorActionPreference="SilentlyContinue"
$action=New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File C:\kso\_t10\_s1.ps1"
$trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10)
$principal=New-ScheduledTaskPrincipal -UserId "SCO_M210" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName "KSOS1" -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName "KSOS1"'
B64=$(printf '%s' "$REG" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/kso_ssh.sh" "powershell -NoProfile -EncodedCommand $B64" >/dev/null 2>&1
sleep "$WAITS"
if [ -n "$REMOTE_OUT" ]; then
  LO="${LOCAL_OUT:-/tmp/s1out.txt}"
  bash "$DIR/kso_scp.sh" "kso:$REMOTE_OUT" "$LO" >/dev/null 2>&1 && cat "$LO" || echo "PULL_FAILED ($REMOTE_OUT)"
fi
