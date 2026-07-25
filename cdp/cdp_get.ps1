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
  [switch]$NoNav,
  # TRUSTED input (Input.dispatchMouseEvent). Synthetic el.click() is enough for plain buttons,
  # but component frameworks (Vaadin Grid rows, menus) ignore untrusted events -> the page looks
  # "dead" and you debug the wrong thing. -Click "x,y" sends a REAL click at viewport coords.
  [string]$Click = "",
  [ValidateSet("left","right")][string]$ClickBtn = "left",
  [int]$ClickCount = 1,
  # Poll a JS predicate until it is truthy instead of betting on a fixed -SettleMs.
  [string]$WaitFor = "",
  [int]$WaitMs = 20000,
  # Evaluate INSIDE an iframe: substring of that frame's URL. Uses the frame's MAIN world, so the
  # page's own JS globals are visible (an isolated world would give you the DOM but no variables).
  [string]$Frame = ""
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

# Trusted mouse click BEFORE the settle wait, so the settle covers the app's reaction to it.
if ($Click -ne "") {
  $xy = $Click -split ','
  if ($xy.Count -ne 2) { Write-Output "CLICK=BADARG" } else {
    $cx = [int]$xy[0]; $cy = [int]$xy[1]
    $btnMask = 1; if ($ClickBtn -eq "right") { $btnMask = 2 }
    $pos = '"x":' + $cx + ',"y":' + $cy + ',"button":"' + $ClickBtn + '","buttons":' + $btnMask
    Send-Cdp ('{"id":3,"method":"Input.dispatchMouseEvent","params":{"type":"mouseMoved","x":' + $cx + ',"y":' + $cy + '}}')
    Start-Sleep -Milliseconds 120
    # A dblclick is TWO press/release pairs with clickCount 1 then 2 — a single event with
    # clickCount:2 does NOT make Chrome emit `dblclick`, and a UI that opens a card on
    # double-click stays silent (looks like "the click does not reach the app").
    for ($n = 1; $n -le $ClickCount; $n++) {
      $b = $pos + ',"clickCount":' + $n
      Send-Cdp ('{"id":' + (10 + $n * 2) + ',"method":"Input.dispatchMouseEvent","params":{"type":"mousePressed",' + $b + '}}')
      Start-Sleep -Milliseconds 60
      Send-Cdp ('{"id":' + (11 + $n * 2) + ',"method":"Input.dispatchMouseEvent","params":{"type":"mouseReleased",' + $b + '}}')
      Start-Sleep -Milliseconds 60
    }
    Write-Output ("CLICK=" + $cx + "," + $cy + " btn=" + $ClickBtn + " n=" + $ClickCount)
  }
}

Start-Sleep -Milliseconds $SettleMs      # let the anti-bot challenge solve itself / the postback land

# ---- WaitFor: poll a predicate instead of guessing a settle time ------------------------------
# A fixed -SettleMs is a bet on how fast the app answers. When it loses you read the page BEFORE
# the dialog/grid arrived and conclude "the click did nothing" — the single most expensive wrong
# turn with this tool. -WaitFor '<js>' polls until the expression is truthy (or -WaitMs elapses)
# and prints WAIT=OK/TIMEOUT so the miss is visible instead of silent.
function Eval-Once([string]$expr, [int]$id, [int]$timeoutMs = 15000) {
  $req = @{ id = $id; method = "Runtime.evaluate"; params = @{ expression = $expr; returnByValue = $true; awaitPromise = $true } } | ConvertTo-Json -Depth 6 -Compress
  try { Send-Cdp $req } catch { return $null }
  for ($i = 0; $i -lt 60; $i++) {
    $m = Recv-Cdp $timeoutMs
    if ($m -eq $null) { return $null }
    if ($m -like ('*"id":' + $id + ',*') -or $m -like ('*"id":' + $id + '}*')) {
      try { $o = $m | ConvertFrom-Json } catch { return $null }
      if ($o.result -and $o.result.result) { return $o.result.result.value }
      return $null
    }
  }
  return $null
}
if ($WaitFor -ne "") {
  $wDeadline = (Get-Date).AddMilliseconds($WaitMs)
  $wid = 500
  $hit = $false
  while ((Get-Date) -lt $wDeadline) {
    $v = Eval-Once ("(() => { try { return !!(" + $WaitFor + ") } catch(e) { return false } })()") $wid 8000
    $wid++
    if ($v -eq $true) { $hit = $true; break }
    Start-Sleep -Milliseconds 500
  }
  if ($hit) { Write-Output "WAIT=OK" } else { Write-Output "WAIT=TIMEOUT" }
}

# ---- Frame: run the expression in an iframe's own execution context ---------------------------
# Same-origin frames can be reached from the top document (iframe.contentWindow), cross-origin ones
# cannot -- and even same-origin ones lose their JS globals if you evaluate in an isolated world.
# Runtime.enable replays executionContextCreated for the contexts that already exist; match the one
# whose auxData.frameId belongs to a frame whose URL contains -Frame.
$ctxId = $null
if ($Frame -ne "") {
  $frameIds = @{}
  Send-Cdp '{"id":40,"method":"Page.enable","params":{}}'
  Send-Cdp '{"id":41,"method":"Page.getFrameTree","params":{}}'
  Send-Cdp '{"id":42,"method":"Runtime.enable","params":{}}'
  $tEnd = (Get-Date).AddSeconds(8)
  $ctxs = @()
  while ((Get-Date) -lt $tEnd) {
    $m = Recv-Cdp 1500
    if ($m -eq $null) { continue }
    if ($m -like '*"frameTree"*') {
      foreach ($mm in [regex]::Matches($m, '"id"\s*:\s*"([0-9A-F]{8,})"\s*,\s*"(?:parentId|loaderId)"[^}]*?"url"\s*:\s*"([^"]*)"')) {
        $frameIds[$mm.Groups[1].Value] = $mm.Groups[2].Value
      }
      # frames whose json order differs: fall back to a looser pass
      foreach ($mm in [regex]::Matches($m, '"frame"\s*:\s*\{[^}]*?"id"\s*:\s*"([0-9A-F]{8,})"[^}]*?"url"\s*:\s*"([^"]*)"')) {
        $frameIds[$mm.Groups[1].Value] = $mm.Groups[2].Value
      }
    }
    if ($m -like '*executionContextCreated*') {
      try { $o = $m | ConvertFrom-Json } catch { continue }
      $c = $o.params.context
      if ($c) { $ctxs += ,@($c.id, $c.origin, $c.name, $c.auxData.frameId) }
    }
  }
  foreach ($c in $ctxs) {
    $fid = $c[3]
    $furl = ""
    if ($fid -and $frameIds.ContainsKey($fid)) { $furl = $frameIds[$fid] }
    if (($furl -like ("*" + $Frame + "*")) -or ($c[1] -like ("*" + $Frame + "*")) -or ($c[2] -like ("*" + $Frame + "*"))) {
      $ctxId = $c[0]; break
    }
  }
  if ($ctxId -eq $null) { Write-Output ("FRAME=NOTFOUND ctxs=" + $ctxs.Count + " frames=" + $frameIds.Count) }
  else { Write-Output ("FRAME=CTX" + $ctxId) }
}

$evalParams = @{ expression = $Expr; returnByValue = $true; awaitPromise = $true }
if ($ctxId -ne $null) { $evalParams["contextId"] = $ctxId }
$evalReq = @{ id = 9; method = "Runtime.evaluate"; params = $evalParams } | ConvertTo-Json -Depth 6 -Compress
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
