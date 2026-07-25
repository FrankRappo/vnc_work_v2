# cdp_net.ps1 - record the page's NETWORK traffic (XHR/fetch/doc) and dump it AS TEXT.
#
# Why: a modern LK renders its data through XHR/JSON. Digging the same numbers back out of the
# rendered DOM is lossy (values get formatted, blocks stay collapsed, iframes hide the payload).
# Reading the RESPONSE the server actually sent is exact and cheap.
#
#   powershell -File cdp_net.ps1 -Out C:\Users\User\net.txt -Seconds 12 -Click "76,123" -Bodies
#   powershell -File cdp_net.ps1 -Out ... -ExprFile trigger.js -UrlFilter "uidl" -Bodies
#
# Output = one text block per request:  #<n> METHOD status mime url   then the body (if -Bodies).
#
# GOTCHAS (same family as cdp_get.ps1):
#  1. ClientWebSocket allows ONE outstanding ReceiveAsync -> the pending task is held and RESUMED.
#  2. Response bodies live in the renderer only until the page navigates away or the buffer
#     evicts them: fetch them in the SAME session, right after the capture window.
#  3. Network.enable must be sent BEFORE the action that triggers the traffic.
param(
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Port = 9222,
  [int]$Seconds = 12,
  [string]$UrlFilter = "",
  [switch]$Bodies,
  [int]$MaxBody = 40000,
  [string]$Click = "",
  [ValidateSet("left","right")][string]$ClickBtn = "left",
  [int]$ClickCount = 1,
  [string]$ExprFile = "",
  [string]$Nav = ""
)
$ErrorActionPreference = "Stop"

$script:ct      = [System.Threading.CancellationToken]::None
$script:pending = $null
$script:pendBuf = $null
$script:ws      = $null
$script:msgId   = 100

function Get-PageWs([int]$port) {
  $l = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/json/list" -f $port) -UseBasicParsing -TimeoutSec 8
  $t = $l.Content | ConvertFrom-Json
  $pg = $t | Where-Object { $_.type -eq "page" } | Select-Object -First 1
  if ($pg) { return $pg.webSocketDebuggerUrl } else { return $null }
}
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
function Send-Cdp([string]$json) {
  $b = [System.Text.Encoding]::UTF8.GetBytes($json)
  $seg = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$b)
  $script:ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $script:ct).Wait(10000) | Out-Null
}
function Recv-Cdp([int]$timeoutMs = 3000) {
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

$wsUrl = Get-PageWs $Port
if ($wsUrl -eq $null) { Write-Output "WS=NOPAGE"; exit 1 }
if (-not (Connect-Cdp $wsUrl $Port)) { Write-Output "WS=FAIL"; exit 1 }

Send-Cdp '{"id":1,"method":"Network.enable","params":{"maxTotalBufferSize":40000000,"maxResourceBufferSize":20000000}}'
Start-Sleep -Milliseconds 300

if ($Nav -ne "") { Send-Cdp ('{"id":2,"method":"Page.navigate","params":{"url":' + (ConvertTo-Json $Nav) + '}}') }

if ($ExprFile -ne "" -and (Test-Path $ExprFile)) {
  $expr = [IO.File]::ReadAllText($ExprFile)
  $req = @{ id = 3; method = "Runtime.evaluate"; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Depth 6 -Compress
  Send-Cdp $req
}

if ($Click -ne "") {
  $xy = $Click -split ','
  if ($xy.Count -eq 2) {
    $cx = [int]$xy[0]; $cy = [int]$xy[1]
    $btnMask = 1; if ($ClickBtn -eq "right") { $btnMask = 2 }
    $pos = '"x":' + $cx + ',"y":' + $cy + ',"button":"' + $ClickBtn + '","buttons":' + $btnMask
    Send-Cdp ('{"id":4,"method":"Input.dispatchMouseEvent","params":{"type":"mouseMoved","x":' + $cx + ',"y":' + $cy + '}}')
    Start-Sleep -Milliseconds 120
    for ($n = 1; $n -le $ClickCount; $n++) {
      $b = $pos + ',"clickCount":' + $n
      Send-Cdp ('{"id":' + (20 + $n * 2) + ',"method":"Input.dispatchMouseEvent","params":{"type":"mousePressed",' + $b + '}}')
      Start-Sleep -Milliseconds 60
      Send-Cdp ('{"id":' + (21 + $n * 2) + ',"method":"Input.dispatchMouseEvent","params":{"type":"mouseReleased",' + $b + '}}')
      Start-Sleep -Milliseconds 60
    }
    Write-Output ("CLICK=" + $cx + "," + $cy + " btn=" + $ClickBtn + " n=" + $ClickCount)
  }
}

# ---- capture window -------------------------------------------------------
$reqs = @{}
$order = New-Object System.Collections.ArrayList
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
  $m = Recv-Cdp 1500
  if ($m -eq $null) { continue }
  if ($m -notlike '*"method":"Network.*') { continue }
  try { $o = $m | ConvertFrom-Json } catch { continue }
  $meth = $o.method
  $p = $o.params
  if ($meth -eq "Network.requestWillBeSent") {
    $id = $p.requestId
    if (-not $reqs.ContainsKey($id)) {
      $reqs[$id] = @{ url = $p.request.url; verb = $p.request.method; type = $p.type; status = ""; mime = ""; post = $p.request.postData }
      [void]$order.Add($id)
    }
  } elseif ($meth -eq "Network.responseReceived") {
    $id = $p.requestId
    if ($reqs.ContainsKey($id)) { $reqs[$id].status = $p.response.status; $reqs[$id].mime = $p.response.mimeType; $reqs[$id].type = $p.type }
  }
}
Write-Output ("CAPTURED=" + $order.Count)

# ---- bodies ---------------------------------------------------------------
$sbOut = New-Object System.Text.StringBuilder
$n = 0
foreach ($id in $order) {
  $r = $reqs[$id]
  if ($UrlFilter -ne "" -and $r.url -notlike ("*" + $UrlFilter + "*")) { continue }
  $n++
  [void]$sbOut.AppendLine("### #$n $($r.verb) $($r.status) $($r.type) $($r.mime)")
  [void]$sbOut.AppendLine("URL $($r.url)")
  if ($r.post) { [void]$sbOut.AppendLine("POST " + $r.post.Substring(0, [Math]::Min(2000, $r.post.Length))) }
  if ($Bodies) {
    $bid = $script:msgId; $script:msgId++
    Send-Cdp ('{"id":' + $bid + ',"method":"Network.getResponseBody","params":{"requestId":"' + $id + '"}}')
    $body = $null
    for ($i = 0; $i -lt 40; $i++) {
      $m = Recv-Cdp 4000
      if ($m -eq $null) { break }
      if ($m -like ('*"id":' + $bid + ',*') -or $m -like ('*"id":' + $bid + '}*')) {
        try { $o = $m | ConvertFrom-Json } catch { break }
        if ($o.result -and $o.result.body -ne $null) { $body = [string]$o.result.body }
        elseif ($o.error) { $body = "(getResponseBody error: " + $o.error.message + ")" }
        break
      }
    }
    if ($body -ne $null) {
      if ($body.Length -gt $MaxBody) { $body = $body.Substring(0, $MaxBody) + "`n...(truncated at $MaxBody)" }
      [void]$sbOut.AppendLine("BODY " + $body.Length)
      [void]$sbOut.AppendLine($body)
    } else { [void]$sbOut.AppendLine("BODY (unavailable)") }
  }
  [void]$sbOut.AppendLine("")
}
try { $script:ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "bye", $script:ct).Wait(3000) | Out-Null } catch {}
[IO.File]::WriteAllText($Out, $sbOut.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("OK MATCHED=" + $n + " OUT=" + $Out)
