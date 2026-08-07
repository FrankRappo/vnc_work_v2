# onboard_new_machine.ps1 — завести машину на НАШ RustDesk-сервер без GUI.
# Запускать НА новой машине от имени администратора:
#   powershell -NoProfile -ExecutionPolicy Bypass -File onboard_new_machine.ps1 -Password "<пароль>"
#
# Что делает: пишет служебный конфиг RustDesk (наш ID-сервер + ключ), задаёт ПОСТОЯННЫЙ пароль
# (unattended — без подтверждения на той стороне), перезапускает службу и печатает ID машины.
# Ничего не устанавливает и не качает: RustDesk уже должен быть на машине (обычная установка или
# портативный exe). GUI не трогается — поэтому киоск-окно, отсутствие мыши и залоченные настройки
# помехой не являются.
param(
  [Parameter(Mandatory = $true)][string]$Password,
  [string]$Server = '178.253.55.128',
  [string]$Key    = 'OS6FFMq66QzmnraQDy+cy+fdryWDXA0fBVZTbYqc7Lk='
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

function Say($m) { Write-Output ("[onboard] " + $m) }

# --- 1. найти исполняемый файл RustDesk ---
$cand = @(
  'C:\Program Files\RustDesk\RustDesk.exe',
  'C:\Program Files (x86)\RustDesk\RustDesk.exe',
  "$env:USERPROFILE\Desktop\rustdesk.exe",
  "$env:USERPROFILE\Downloads\rustdesk.exe"
) + (Get-ChildItem 'C:\','D:\' -Filter 'rustdesk*.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | ForEach-Object FullName)
$exe = $cand | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $exe) { Say 'RustDesk.exe не найден — положи exe на рабочий стол и запусти скрипт снова'; exit 2 }
Say ("exe: " + $exe)

# --- 2. конфиг ---
# 🔴 Боевой конфиг читает СЛУЖБА, а не пользовательский профиль (грабля из README §4.2).
$toml = @"
rendezvous_server = '$Server`:21116'

[options]
custom-rendezvous-server = '$Server'
key = '$Key'
"@

$dirs = @(
  'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config',  # служба (боевой)
  (Join-Path $env:APPDATA 'RustDesk\config')                                   # GUI/трей текущего пользователя
)
foreach ($d in $dirs) {
  try {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    $f = Join-Path $d 'RustDesk2.toml'
    if (Test-Path $f) { Copy-Item $f ($f + '.bak_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) -Force }
    Set-Content -Path $f -Value $toml -Encoding UTF8
    Say ("конфиг записан: " + $f)
  } catch { Say ("не смог записать " + $d + " -> " + $_.Exception.Message) }
}

# --- 3. постоянный пароль (unattended) ---
try {
  & $exe --password $Password 2>&1 | Out-Null
  Say 'постоянный пароль задан (--password)'
} catch { Say ('--password не отработал: ' + $_.Exception.Message + ' — задать вручную в Настройки -> Безопасность') }

# --- 4. перезапуск службы, чтобы конфиг перечитался ---
$svc = Get-Service -Name 'rustdesk' -ErrorAction SilentlyContinue
if ($svc) {
  try { Stop-Service rustdesk -Force -ErrorAction SilentlyContinue; Start-Sleep 2; Start-Service rustdesk; Say 'служба rustdesk перезапущена' }
  catch { Say ('служба не перезапустилась: ' + $_.Exception.Message) }
  # автовосстановление службы, как на первой кассе (T110)
  & sc.exe failure rustdesk reset= 86400 actions= restart/60000/restart/60000/restart/120000 | Out-Null
  & sc.exe failureflag rustdesk 1 | Out-Null
} else {
  Say 'службы rustdesk нет (портативный режим) — запусти rustdesk.exe вручную один раз, чтобы он поднялся'
}

# --- 5. ID машины ---
Start-Sleep 3
$id = ''
try { $id = (& $exe --get-id 2>&1 | Select-Object -First 1).ToString().Trim() } catch {}
if (-not $id) {
  $cfg = 'C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk.toml'
  if (Test-Path $cfg) { $id = ([regex]::Match((Get-Content $cfg -Raw), "id\s*=\s*'([^']+)'")).Groups[1].Value }
}
Say ("RustDesk ID: " + $(if ($id) { $id } else { 'не определился — посмотри в окне RustDesk' }))
Say ("сервер: " + $Server + "   пароль: задан скриптом (передать в CREDENTIALS.md, в чат не писать)")
Say 'проверка регистрации: в логе машины ...\RustDesk\log\server\ должны появиться строки Latency of 178.253.55.128'
