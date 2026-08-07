#!/bin/bash
# ezxy.sh <X> <Y> ["<dump filter>"] — front EasySet, click screen (X,Y), re-dump UIA, print it.
# Call with dangerouslyDisableSandbox=true.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
X="$1"; Y="$2"; FILT="${3-}"
F=/tmp/ez_xy.ps1
sed -i "s/^\$CX = .*/\$CX = $X/" "$F"
sed -i "s/^\$CY = .*/\$CY = $Y/" "$F"
esc(){ printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
sed -i "s/^\$DUMPFILTER = .*/\$DUMPFILTER = \"$(esc "$FILT")\"/" "$F"
bash "$DIR/s1run.sh" "$F" "" "" 2 >/dev/null 2>&1
for i in $(seq 1 25); do
  sleep 5
  age=$(bash "$DIR/kso_ssh.sh" 'powershell -NoProfile -Command "((Get-Date)-(Get-Item C:\kso\_t10\uia.txt).LastWriteTime).TotalSeconds"' 2>/dev/null | grep -aoE '^[0-9]+' | head -1)
  [ -n "$age" ] && [ "$age" -lt 7 ] && [ "$i" -ge 2 ] && break
done
bash "$DIR/kso_scp.sh" kso:C:/kso/_t10/uia.txt /tmp/uia.txt >/dev/null 2>&1
cat /tmp/uia.txt
