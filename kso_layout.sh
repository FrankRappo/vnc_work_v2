#!/bin/bash
# kso_layout.sh <cmd> [payload] — drive the session-1 KSOLAYOUT helper (report|seten|sendcode).
# Writes the command file, triggers the task, waits, prints the fresh t09_out.txt tail.
# payload may contain ~GS~ token (=> GS 0x1D) for sendcode.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:?usage: kso_layout.sh <report|seten|sendcode> [payload]}"
PAYLOAD="${2:-}"
WAIT="${3:-6}"
# Build cmd file content (line1=cmd, line2=payload) and push as base64 to avoid quoting/encoding loss.
CONTENT="$CMD
$PAYLOAD"
B64=$(printf '%s' "$CONTENT" | base64 -w0)
read -r -d '' PS <<EOF
\$b='$B64'
\$bytes=[Convert]::FromBase64String(\$b)
\$txt=[Text.Encoding]::UTF8.GetString(\$bytes)
Set-Content -Path 'C:\kso\_t10\t09_cmd.txt' -Value \$txt -Encoding UTF8 -NoNewline
Remove-Item 'C:\kso\_t10\t09_out.txt' -EA SilentlyContinue
Start-ScheduledTask -TaskName 'KSOLAYOUT'
EOF
bash "$DIR/kso_ps.sh" >/dev/null 2>&1 <<< "$PS"
sleep "$WAIT"
bash "$DIR/kso_ps.sh" <<< "if(Test-Path 'C:\kso\_t10\t09_out.txt'){ Get-Content 'C:\kso\_t10\t09_out.txt' } else { 'NO OUT (task may still be running)' }"
