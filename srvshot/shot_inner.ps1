# Runs INSIDE the interactive session (session 1) and captures that session's own screen.
# A process started from an SSH session lives in session 0 and would capture a BLACK frame,
# so this file is always launched through a scheduled task with /ru <user> /it.
param([string]$Out = "C:\Users\User\srvshot.png", [string]$FocusTitle = "", [int]$SettleSec = 3)
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class SrvShotW {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@
$titles = New-Object System.Collections.ArrayList
$script:hit = [IntPtr]::Zero
$cb = [SrvShotW+EnumWindowsProc]{
  param($h, $l)
  if ([SrvShotW]::IsWindowVisible($h)) {
    $sb = New-Object System.Text.StringBuilder 512
    [void][SrvShotW]::GetWindowText($h, $sb, 512)
    $t = $sb.ToString()
    if ($t.Length -gt 0) {
      [void]$titles.Add($t)
      if ($FocusTitle -ne "" -and $t -like ("*" + $FocusTitle + "*")) { $script:hit = $h }
    }
  }
  return $true
}
[void][SrvShotW]::EnumWindows($cb, [IntPtr]::Zero)
if ($script:hit -ne [IntPtr]::Zero) {
  [void][SrvShotW]::ShowWindow($script:hit, 3)      # SW_MAXIMIZE
  [void][SrvShotW]::SetForegroundWindow($script:hit)
  Start-Sleep -Seconds $SettleSec
}
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
# 🔴 TIME= (часы САМОЙ машины, снимок момента записи файла) — без него кадр невозможно отличить от
# вчерашнего: картинка правдоподобна всегда (kso-anydesk-stale-frame, 2026-08-05).
$info = @("SHOT=" + (Get-Item $Out).Length + " TIME=" + (Get-Item $Out).LastWriteTime.ToString('yyyy-MM-dd_HH:mm:ss') +
          " SIZE=" + $b.Width + "x" + $b.Height +
          " FOCUSED=" + $($script:hit -ne [IntPtr]::Zero))
$info += ($titles | ForEach-Object { "WIN " + $_ })
$info | Out-File -FilePath ($Out + ".txt") -Encoding ascii
