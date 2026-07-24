# Runs INSIDE the interactive session (session 1) and captures that session's own screen.
# A process started from an SSH session lives in session 0 and would capture a black frame,
# so this file is always launched through a scheduled task with /ru <user> /it.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
$out = $env:T67_SHOT_PATH
if (-not $out) { $out = "C:\Users\User\srvshot.png" }
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
("SHOT=" + (Get-Item $out).Length + " SIZE=" + $b.Width + "x" + $b.Height) | Out-File -FilePath ($out + ".txt") -Encoding ascii
