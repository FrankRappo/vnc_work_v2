@echo off
REM Opens direct SSH terminal to VM121 through WSL Ubuntu-24.04.
where wt.exe >nul 2>nul
if %errorlevel%==0 (
  start "VM121 terminal" wt.exe wsl.exe -d Ubuntu-24.04 -u root -- bash -lc "/work/settings/vm121-terminal.sh"
) else (
  wsl.exe -d Ubuntu-24.04 -u root -- bash -lc "/work/settings/vm121-terminal.sh"
  pause
)
