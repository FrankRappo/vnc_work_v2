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
  # 🔴 SELF-DELETE THE SHIPPED SCRIPT, SERVER-SIDE, ALWAYS (T194, 2026-08-07).
  # The shipped script routinely carries SUBSTITUTED SECRETS: the kso pwrun wrappers replace
  # @@P1C@@ / @@PKSO@@ / @@PPG@@ with real passwords before upload. Until now the only cleanup was
  # the `cmd /c del` at the end of rps.sh — i.e. CLIENT-side, AFTER the output pull. Any run that
  # outlived the caller (SSH drop, agent Bash timeout, Ctrl-C) therefore left a plaintext-password
  # .ps1 sitting on the remote machine forever. Found on the live 1C server DESKTOP-VGVHEOU:
  # three such files from 06.08, ~24 hours old, 2689 bytes each.
  # Deleting here means the cleanup survives whatever happens to the caller. This is the same
  # rule the kso side calls T137 ("the script that puts a cred file on the server must remove it
  # itself"), now enforced by the transport instead of by every caller remembering to.
  try { Remove-Item -LiteralPath $Script -Force -ErrorAction Stop } catch {}
}
Write-Output ("RPS_OK bytes=" + (Get-Item $Out).Length)
Write-Output ("RPS_SCRIPT_DELETED=" + (-not (Test-Path -LiteralPath $Script)))
