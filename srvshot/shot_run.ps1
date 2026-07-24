param([string]$Png = "C:\Users\User\srvshot.png", [string]$Inner = "C:\Users\User\srvshot_inner.ps1",
      [string]$Task = "SRVSHOT", [string]$FocusTitle = "", [int]$SettleSec = 3)
# NOTE: run the capture through a HIDDEN powershell (no .bat) - a bat launcher shows a cmd.exe
# window ON TOP of the target and ruins the frame.
$tr = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Inner`" -Out `"$Png`" -FocusTitle `"$FocusTitle`" -SettleSec $SettleSec"
schtasks /create /tn $Task /tr $tr /sc once /st 00:00 /ru User /it /f | Out-Null
if (Test-Path ($Png + ".txt")) { Remove-Item ($Png + ".txt") -Force }
schtasks /run /tn $Task | Out-Null
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Seconds 1; if (Test-Path ($Png + ".txt")) { break } }
if (Test-Path ($Png + ".txt")) { Get-Content ($Png + ".txt") } else { Write-Output "SHOT=FAIL" }
