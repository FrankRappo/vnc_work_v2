param([string]$Png = "C:\Users\User\srvshot.png", [string]$Inner = "C:\Users\User\srvshot_inner.ps1",
      [string]$Task = "SRVSHOT", [string]$FocusTitle = "", [int]$SettleSec = 3, [string]$RunAs = "")
# NOTE: run the capture through a HIDDEN powershell (no .bat) - a bat launcher shows a cmd.exe
# window ON TOP of the target and ruins the frame.
#
# 🔴 kso-anydesk-stale-frame (2026-08-05): the PNG itself must be deleted before the run, not just
# its .txt marker. Otherwise a capture that never happened (locked session, task refused to start)
# leaves last time's picture under the same path, the puller fetches it and the reader reasons about
# a screen that is hours old. No picture is far better than an old picture.
#
# 🔴 -RunAs (T194, 2026-08-07). The account was HARDCODED as `/ru User`, which is the login on the
# OFD box this tool was written against. On any other machine the task registers against a user who
# is not the one holding the interactive session, so it either refuses to register or runs in a
# session with no desktop — and the failure looks identical to "capture timed out". The 1C server
# DESKTOP-VGVHEOU logs in as `Админ`, not `User`. Empty -RunAs now AUTO-DETECTS the account that
# actually owns the interactive session (owner of explorer.exe), so the tool stops being pinned to
# one machine and the chosen account is printed as evidence.
if (-not $RunAs) {
  try {
    $ex = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'")
    foreach ($p in $ex) {
      $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner
      if ($o.User) { $RunAs = $o.User; break }
    }
  } catch { }
  if (-not $RunAs) { $RunAs = $env:USERNAME }
}
Write-Output ("SHOT_RUNAS=" + $RunAs)
$tr = "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Inner`" -Out `"$Png`" -FocusTitle `"$FocusTitle`" -SettleSec $SettleSec"
schtasks /create /tn $Task /tr $tr /sc once /st 00:00 /ru $RunAs /it /f | Out-Null
if (Test-Path ($Png + ".txt")) { Remove-Item ($Png + ".txt") -Force }
if (Test-Path $Png)            { Remove-Item $Png -Force }
schtasks /run /tn $Task | Out-Null
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Seconds 1; if (Test-Path ($Png + ".txt")) { break } }
if (Test-Path ($Png + ".txt")) {
  Get-Content ($Png + ".txt")
  # подстраховка: маркер есть, а файла нет = кадр не сохранился (диск/права) — это тоже провал
  if (-not (Test-Path $Png)) { Write-Output "SHOT=FAIL NOPNG" }
} else {
  Write-Output ("SHOT=FAIL TIMEOUT TIME=" + (Get-Date -Format 'yyyy-MM-dd_HH:mm:ss'))
}
