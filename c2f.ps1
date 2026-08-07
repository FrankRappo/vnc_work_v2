param([string]$dest)
$ErrorActionPreference='Stop'
$b = Get-Clipboard -Raw
$b = ($b -replace '\s','')
[IO.File]::WriteAllBytes($dest, [Convert]::FromBase64String($b))
$h = (Get-FileHash $dest -Algorithm SHA256).Hash
Set-Content -Path 'C:\kso\c2f.out' -Value ($h + ' ' + (Get-Item $dest).Length) -Encoding ASCII
