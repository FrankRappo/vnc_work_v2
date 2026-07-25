# rps_run.ps1 -Script <path> -Out <path> — remote half of rps.sh.
# Runs the shipped script and writes EVERY stream to a UTF-8 file.
#
# Why a wrapper file instead of `powershell -Command "..."` over ssh: the ssh command line on
# Windows is parsed by cmd.exe, so a -Command body containing  * > & |  invites cmd to eat the
# redirections (`*>&1` became a cmd redirect and PowerShell got a syntax error). A file has no
# such layer. It also forces UTF-8 on BOTH sides so Cyrillic survives.
param(
  [Parameter(Mandatory=$true)][string]$Script,
  [Parameter(Mandatory=$true)][string]$Out
)
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$PSDefaultParameterValues['*:Encoding'] = 'utf8'
# Stream every object to the file AS IT ARRIVES. Buffering the whole run through Out-String loses
# everything printed before a terminating error (one missing native .exe used to blank the file and
# the probe read as "nothing works"). Partial output + the exception text is far more useful.
$sw = New-Object IO.StreamWriter($Out, $false, (New-Object Text.UTF8Encoding $false))
try {
  # Out-String -Stream formats tables properly AND emits line by line (per-object Out-String throws
  # a NullReferenceException on the null items Format-Table interleaves).
  & $Script 2>&1 | Out-String -Stream -Width 400 | ForEach-Object { $sw.WriteLine([string]$_) }
} catch {
  $sw.WriteLine("RPS_EXCEPTION: $($_.Exception.Message)")
  $sw.WriteLine($_.ScriptStackTrace)
} finally {
  $sw.Flush(); $sw.Close()
}
Write-Output ("RPS_OK bytes=" + (Get-Item $Out).Length)
