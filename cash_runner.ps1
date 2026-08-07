# cash_runner.ps1 — file-queue executor on the cash. Watches C:\kso\q for *.job (PowerShell scripts
# ending with the sentinel line '#EOJ'), runs each, writes <id>.out, and pushes the result to the
# clipboard as "JDONE_<id>`r`n<output>" so the /work side can read it WITHOUT typing anything (RustDesk
# syncs the cash clipboard back to :99). Payloads arrive as files via clipboard-base64 (zput), never
# typed → immune to the keystroke-scrambling/focus problems of the interactive console.
$ErrorActionPreference = 'Continue'
$Q = 'C:\kso\q'
New-Item -ItemType Directory -Force -Path $Q | Out-Null
Set-Content -Path (Join-Path $Q 'runner.alive') -Value ("started " + (Get-Date -Format o)) -Encoding ASCII
Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
function Set-Clip([string]$t){
  try { [System.Windows.Forms.Clipboard]::SetText($t) } catch { try { $t | Set-Clipboard } catch {} }
}
while ($true) {
  try {
    $jobs = Get-ChildItem -Path $Q -Filter *.job -ErrorAction SilentlyContinue | Sort-Object LastWriteTime
    foreach ($j in $jobs) {
      $id = $j.BaseName
      $body = ''
      try { $body = Get-Content -LiteralPath $j.FullName -Raw -ErrorAction Stop } catch { continue }
      if ($body -notmatch '(?m)^\#EOJ\s*$') { continue }   # not fully written yet — wait
      # move to .run so we never execute twice
      $run = Join-Path $Q ($id + '.run')
      try { Move-Item -LiteralPath $j.FullName -Destination $run -Force } catch { continue }
      $out = ''
      try {
        $sb = [scriptblock]::Create($body)
        $out = (& $sb *>&1 | Out-String)
      } catch {
        $out = "JOB EXCEPTION: " + $_.Exception.Message
      }
      $outfile = Join-Path $Q ($id + '.out')
      try { Set-Content -LiteralPath $outfile -Value $out -Encoding UTF8 } catch {}
      $clip = "JDONE_$id`r`n$out"
      if ($clip.Length -gt 120000) { $clip = $clip.Substring(0,120000) + "`r`n<TRUNCATED>" }
      Set-Clip $clip
      try { Move-Item -LiteralPath $run -Destination (Join-Path $Q ($id + '.done')) -Force } catch {}
    }
  } catch {}
  Start-Sleep -Milliseconds 700
}
