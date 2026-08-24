#!/bin/bash
# srvold_ps.sh — выполнить PowerShell-скрипт на СТАРОМ сервере DESKTOP-VGVHEOU (машина товароведа,
# 192.168.0.10) *через джамп* SERVER-1S, когда её собственный обратный туннель (VPS:2244) лежит.
# Текст скрипта читается со stdin и уезжает -EncodedCommand (UTF-16LE) — кириллица не бьётся.
#
# Пара к srvold_ssh.sh (тот же путь: VPS:2248 -> SERVER-1S -> direct-tcpip 192.168.0.10:22).
# Отношение то же, что у srv_ps.sh к srv_ssh.sh: там прямой туннель 2244, здесь — джамп.
#
# 🔴 Запускать с dangerouslyDisableSandbox — песочница агента рубит ssh сигналом 16.
#
#   cat ops/t245_recon.ps1 | bash srvold_ps.sh
#   echo 'hostname' | bash srvold_ps.sh
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$(cat)"
B64=$(printf '%s' "$SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
bash "$DIR/srvold_ssh.sh" "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $B64" 2>&1 \
  | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_'
