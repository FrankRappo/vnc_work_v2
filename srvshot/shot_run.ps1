param([string]$Png = "C:\Users\User\srvshot.png", [string]$Inner = "C:\Users\User\srvshot_inner.ps1", [string]$Task = "SRVSHOT")
$bat = "$env:TEMP\$Task.bat"
Set-Content -Path $bat -Value ("set T67_SHOT_PATH=" + $Png + "`r`npowershell -NoProfile -ExecutionPolicy Bypass -File " + $Inner) -Encoding ASCII
schtasks /create /tn $Task /tr "$bat" /sc once /st 00:00 /ru User /it /f | Out-Null
if (Test-Path ($Png + ".txt")) { Remove-Item ($Png + ".txt") -Force }
schtasks /run /tn $Task | Out-Null
for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; if (Test-Path ($Png + ".txt")) { break } }
if (Test-Path ($Png + ".txt")) { Get-Content ($Png + ".txt") } else { Write-Output "SHOT=FAIL" }
