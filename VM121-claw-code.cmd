@echo off
REM Opens Claw Code directly on VM121 through WSL Ubuntu-24.04.
where wt.exe >nul 2>nul
if %errorlevel%==0 (
  start "VM121 Claw Code" wt.exe wsl.exe -d Ubuntu-24.04 -u root -- bash -lc "/work/settings/vm121-claw-code.sh"
) else (
  wsl.exe -d Ubuntu-24.04 -u root -- bash -lc "/work/settings/vm121-claw-code.sh"
  pause
)
