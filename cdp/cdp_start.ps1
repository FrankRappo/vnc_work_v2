# cdp_start.ps1 - start (or reuse) a headless Chrome with a CDP debugging port on THIS machine.
# Isolated profile so the interactive user's own Chrome/profile is never touched.
param([int]$Port = 9222, [string]$ProfileDir = "C:\Users\User\t67cdp", [switch]$Restart)
$ErrorActionPreference = "Continue"
function Test-Cdp([int]$p) {
  try { $r = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/json/version" -f $p) -UseBasicParsing -TimeoutSec 4
        return $r.Content } catch { return $null }
}
if ($Restart) {
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
    Where-Object { $_.CommandLine -like "*$ProfileDir*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 2
}
$v = Test-Cdp $Port
if ($v) { Write-Output "CDP=ALREADY"; Write-Output $v; exit 0 }
# Chrome is NOT always under "Program Files": a 32-bit install (SOCHI11, T229) lands in
# "Program Files (x86)", a per-user install in %LOCALAPPDATA%. Probing one path made cdp_up.sh
# report CDP=NOCHROME on a box where Chrome was installed and running.
$chromeCandidates = @(
  "C:\Program Files\Google\Chrome\Application\chrome.exe",
  "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chrome = $chromeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { Write-Output "CDP=NOCHROME"; exit 1 }
$a = @(
  "--headless=new","--disable-gpu","--no-first-run","--no-default-browser-check",
  "--disable-background-networking","--user-data-dir=$ProfileDir",
  "--remote-debugging-port=$Port","--remote-allow-origins=*",
  "--window-size=1400,1200","about:blank"
)
# schtasks detaches the process from this SSH session (OpenSSH kills session children on exit).
$cmdline = '"' + $chrome + '" ' + ($a -join ' ')
$bat = "$env:TEMP\t67_cdp_launch.bat"
Set-Content -Path $bat -Value ("start `"`" " + $cmdline) -Encoding ASCII
schtasks /create /tn T67CDP /tr "$bat" /sc once /st 00:00 /ru User /it /f | Out-Null
schtasks /run /tn T67CDP | Out-Null
for ($i=0; $i -lt 30; $i++) {
  Start-Sleep -Seconds 1
  $v = Test-Cdp $Port
  if ($v) { Write-Output "CDP=UP"; Write-Output $v; exit 0 }
}
Write-Output "CDP=FAIL"
exit 1
