#!/bin/bash
# eznav.sh "<TARGET name to click>" ["<dump filter>"]
# Sets the click target + dump filter in /tmp/ez_nav.ps1, runs it in session 1 (topmost EasySet,
# UIA-find target by Name, click its center, re-dump UIA tree), waits for the fresh dump, prints it.
# Pass "" as TARGET to just re-dump without clicking. Call with dangerouslyDisableSandbox=true.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
TGT="${1-}"
FILT="${2-}"
F=/tmp/ez_nav.ps1
# escape for sed replacement (slashes, ampersands)
esc(){ printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'; }
sed -i "s/^\$TARGET = .*/\$TARGET = \"$(esc "$TGT")\"   # set by eznav.sh/" "$F"
sed -i "s/^\$DUMPFILTER = .*/\$DUMPFILTER = \"$(esc "$FILT")\"/" "$F"
bash "$DIR/s1run.sh" "$F" "" "" 2 >/dev/null 2>&1
for i in $(seq 1 25); do
  sleep 5
  age=$(bash "$DIR/kso_ssh.sh" 'powershell -NoProfile -Command "((Get-Date)-(Get-Item C:\kso\_t10\uia.txt).LastWriteTime).TotalSeconds"' 2>/dev/null | grep -aoE '^[0-9]+' | head -1)
  [ -n "$age" ] && [ "$age" -lt 7 ] && [ "$i" -ge 2 ] && break
done
bash "$DIR/kso_scp.sh" kso:C:/kso/_t10/uia.txt /tmp/uia.txt >/dev/null 2>&1
cat /tmp/uia.txt
