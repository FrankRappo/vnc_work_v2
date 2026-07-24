# cdp_get.ps1 - navigate a CDP-driven real browser to a URL and dump the RESULT AS TEXT.
#
# Why this exists: sites behind a JS anti-bot challenge (atol.ru, fs.atol.ru) hand curl /
# Invoke-WebRequest a ~13 KB stub page, so a shell-only probe wrongly concludes "nothing there".
# A real browser executes the challenge; CDP returns the resulting DOM as TEXT -> the driving
# agent never has to look at a screenshot (0 vision tokens) and the result is greppable.
#
#   powershell -File cdp_get.ps1 -Url https://fs.atol.ru/ -Out C:\Users\User\o.html
#   powershell -File cdp_get.ps1 -Url ... -Out ... -ExprFile C:\Users\User\links.js
#
# GOTCHA (cost a debugging round): System.Net.WebSockets.ClientWebSocket allows only ONE
# outstanding ReceiveAsync. A drain loop that issues a receive, gives up on timeout and then
# issues another one faults the socket -> AggregateException on .Wait(). The pending task is
# therefore held in $script:pending and RESUMED on the next call, never re-issued.
param(
  [string]$Url = "",
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Port = 9222,
  [int]$SettleMs = 9000,
  [string]$ExprFile = "",
  [string]$Expr = "document.documentElement.outerHTML",
  [switch]$NoNav
)
$ErrorActionPreference = "Stop"
if ($ExprFile -ne "" -and (Test-Path $ExprFile)) { $Expr = [IO.File]::ReadAllText($ExprFile) }

$list = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/json/list" -f $Port) -UseBasicParsing -TimeoutSec 8
$targets = $list.Content | ConvertFrom-Json
$page = $targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1
if (-not $page) {
  $n = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/json/new?about:blank" -f $Port) -Method Put -UseBasicParsing -TimeoutSec 8
  $page = $n.Content | ConvertFrom-Json
}

$script:ct      = [System.Threading.CancellationToken]::None
$script:pending = $null
$script:pendBuf = $null
$script:ws      = $null

function Connect-Cdp([string]$wsUrl, [int]$port) {
  for ($try = 1; $try -le 3; $try++) {
    try {
      $script:pending = $null
      $script:ws = New-Object System.Net.WebSockets.ClientWebSocket
      $script:ws.Options.SetRequestHeader("Origin", "http://127.0.0.1:$port")
      $script:ws.ConnectAsync([Uri]$wsUrl, $script:ct).Wait(15000) | Out-Null
      if ($script:ws.State -eq "Open") { return $true }
    } catch { Start-Sleep -Seconds 2 }
  }
  return $false
}
function Get-PageWs([int]$port) {
  $l = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/json/list" -f $port) -UseBasicParsing -TimeoutSec 8
  $t = $l.Content | ConvertFrom-Json
  $pg = $t | Where-Object { $_.type -eq "page" } | Select-Object -First 1
  if ($pg) { return $pg.webSocketDebuggerUrl } else { return $null }
}
if (-not (Connect-Cdp $page.webSocketDebuggerUrl $Port)) { Write-Output "WS=FAIL"; exit 1 }

function Send-Cdp([string]$json) {
  $b = [System.Text.Encoding]::UTF8.GetBytes($json)
  $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$b)
  $script:ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $script:ct).Wait(10000) | Out-Null
}
function Recv-Cdp([int]$timeoutMs = 30000) {
  $sb = New-Object System.Text.StringBuilder
  do {
    if ($script:pending -eq $null) {
      $script:pendBuf = New-Object byte[] 262144
      $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$script:pendBuf)
      $script:pending = $script:ws.ReceiveAsync($seg, $script:ct)
    }
    try { $ok = $script:pending.Wait($timeoutMs) } catch { $script:pending = $null; return $null }
    if (-not $ok) { return $null }          # keep the task pending; resume it next call
    $r = $script:pending.Result
    $script:pending = $null
    [void]$sb.Append([System.Text.Encoding]::UTF8.GetString($script:pendBuf, 0, $r.Count))
  } while (-not $r.EndOfMessage)
  return $sb.ToString()
}

if (-not $NoNav) {
  if ($Url -eq "") { Write-Output "URL=EMPTY"; exit 3 }
  Send-Cdp ('{"id":2,"method":"Page.navigate","params":{"url":' + (ConvertTo-Json $Url) + '}}')
}
Start-Sleep -Milliseconds $SettleMs      # let the anti-bot challenge solve itself / the postback land

$evalReq = @{ id = 9; method = "Runtime.evaluate"; params = @{ expression = $Expr; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Depth 6 -Compress
$val = $null
# A page still mid-reload tears the execution context down and swallows the reply. Retry on a
# fresh socket instead of reporting a false "nothing there".
for ($attempt = 1; $attempt -le 3 -and $val -eq $null; $attempt++) {
  if ($attempt -gt 1) {
    Start-Sleep -Seconds 4
    $u = Get-PageWs $Port
    if ($u -eq $null) { continue }
    if (-not (Connect-Cdp $u $Port)) { continue }
  }
  try { Send-Cdp $evalReq } catch { continue }
  for ($i = 0; $i -lt 80; $i++) {
    $m = Recv-Cdp 20000
    if ($m -eq $null) { break }
    if ($m -like '*"id":9*') {
      $o = $m | ConvertFrom-Json
      if ($o.result -and $o.result.result) { $val = $o.result.result.value }
      if ($o.result -and $o.result.exceptionDetails) { Write-Output ("JSERR=" + $o.result.exceptionDetails.text) }
      break
    }
  }
}
try { $script:ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "bye", $script:ct).Wait(3000) | Out-Null } catch {}
if ($val -eq $null) { Write-Output "EVAL=NULL"; exit 2 }
[IO.File]::WriteAllText($Out, [string]$val, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("OK LEN=" + ([string]$val).Length + " OUT=" + $Out)
