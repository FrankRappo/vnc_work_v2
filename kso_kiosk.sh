#!/bin/bash
# kso_kiosk.sh stop|start|status — reversibly PARK / RESTORE the self-checkout kiosk (Electron)
# on the cash (session-1). Used for on-screen tests (e.g. T07 hex scanner capture) where the
# kiosk's fullscreen alwaysOnTop focus-guard (see workflow.md §16) would otherwise cover the
# test window and swallow scans into a purchase.
#
#   stop   : kills all electron.exe. There is NO external relauncher/watchdog (verified), and the
#            focus-guard lives INSIDE electron, so once killed the kiosk stays down (desktop shows)
#            until you explicitly start it again. Does NOT touch the 1C agent (cv8) or the ATOL FR.
#   start  : runs the canonical KSORelaunch task -> C:\kso\restart_kiosk.ps1 (kills any electron +
#            relaunches the kiosk via C:\kso\KSO.bat, detached, hidden). This is the ONE command to
#            bring the kiosk back. Wait ~20-25s, then `status` should show electron>=1.
#   status : prints the current electron.exe process count.
#
# Reversible by design: `stop` then `start` returns the cash to its normal kiosk state.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
enc(){ printf '%s' "$1" | iconv -f UTF-8 -t UTF-16LE | base64 -w0; }
run_ps(){ bash "$DIR/kso_ssh.sh" "powershell -NoProfile -EncodedCommand $(enc "$1")" 2>&1 \
          | grep -avE '^#< CLIXML|^<Objs|xmlns|_x000D_' | grep -vE '^[[:space:]]*$'; }

case "${1:-status}" in
  stop)
    run_ps 'Stop-Process -Name electron -Force -EA SilentlyContinue
            Start-Sleep -Seconds 3
            $n=@(Get-Process electron -EA SilentlyContinue).Count
            Write-Output ("KIOSK_STOPPED electron_procs="+$n)'
    ;;
  start)
    run_ps 'Start-ScheduledTask -TaskName "KSORelaunch"
            Write-Output "KSORelaunch triggered (restart_kiosk.ps1). Wait ~20-25s, then: kso_kiosk.sh status"'
    ;;
  status)
    run_ps '$n=@(Get-Process electron -EA SilentlyContinue).Count
            Write-Output ("electron_procs="+$n)'
    ;;
  *)
    echo "usage: kso_kiosk.sh stop|start|status"; exit 2;;
esac
