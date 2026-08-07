#!/bin/bash
# kso_probe.sh <local.js> [remote_out_path]
# Deploy a JScript COM probe to the cash (as UTF-16LE+BOM so Cyrillic literals survive), run it under
# 32-bit cscript (V83.COMConnector is a 32-bit inproc server), and print the UTF-8 result file the
# probe wrote. Transport is scp (not -EncodedCommand) so large probes don't hit cmd's 8191-char limit.
#
# CONVENTION: your probe writes its human-readable result (UTF-8) to  C:\kso\_probe_out.txt  via
#   var s=new ActiveXObject("ADODB.Stream"); s.Type=2; s.Charset="utf-8"; s.Open();
#   s.WriteText(OUT.join("\r\n")); s.SaveToFile("C:\\kso\\_probe_out.txt",2); s.Close();
#
# 🔴 Run with dangerouslyDisableSandbox — the agent sandbox kills ssh/scp with signal 16.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
JS="$1"
OUTWIN="${2:-C:\\kso\\_probe_out.txt}"
OUTFWD="${OUTWIN//\\//}"                       # C:/kso/_probe_out.txt for scp
TMP16="$(mktemp)"; TMPOUT="$(mktemp)"
trap 'rm -f "$TMP16" "$TMPOUT"' EXIT
# UTF-16LE + BOM (FF FE) so cscript auto-detects the encoding.
{ printf '\xff\xfe'; iconv -f UTF-8 -t UTF-16LE "$JS"; } > "$TMP16"
bash "$DIR/kso_scp.sh" "$TMP16" 'kso:C:/kso/_probe.js' >/dev/null || { echo "SCP-PUSH-FAIL"; exit 1; }
bash "$DIR/kso_ssh.sh" 'cmd /c C:\Windows\SysWOW64\cscript.exe //nologo C:\kso\_probe.js' 2>&1
echo '===PROBE_OUT==='
if bash "$DIR/kso_scp.sh" "kso:${OUTFWD}" "$TMPOUT" >/dev/null 2>&1; then
  cat "$TMPOUT"
else
  echo "(no result file at ${OUTWIN})"
fi
