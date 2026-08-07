# T09 session-1 helper: switch kiosk window to EN + verify active layout + inject a scan sequence
# through the (kiosk's) active keyboard layout, exactly as the fixed scanner's vk/scancode stream would.
# Reads command from C:\kso\_t10\t09_cmd.txt (line1=cmd, line2=payload for sendcode). Writes C:\kso\_t10\t09_out.txt.
# Runs in session-1 interactive (scheduled task KSOLAYOUT). Non-fiscal: only keyboard input into the kiosk UI.
$ErrorActionPreference = 'Continue'
$base = 'C:\kso\_t10'
$cmdFile = Join-Path $base 't09_cmd.txt'
$outFile = Join-Path $base 't09_out.txt'
function OutW($m){ Add-Content -Path $outFile -Value $m -Encoding UTF8 }

$src = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class T09U {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("user32.dll")] public static extern IntPtr GetKeyboardLayout(uint idThread);
  [DllImport("user32.dll")] public static extern IntPtr LoadKeyboardLayout(string pwszKLID, uint Flags);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
  [DllImport("user32.dll")] public static extern short VkKeyScanEx(char ch, IntPtr dwhkl);
  [DllImport("user32.dll")] public static extern uint MapVirtualKeyEx(uint uCode, uint uMapType, IntPtr dwhkl);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
  [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  public struct RECT { public int L, T, R, B; }
  public const uint KEYEVENTF_KEYUP = 0x2;
  public const uint WM_INPUTLANGCHANGEREQUEST = 0x50;
  public static IntPtr FoundKiosk = IntPtr.Zero;
  public static int FoundArea = 0;
  public static bool EnumCb(IntPtr h, IntPtr l){
    if(!IsWindowVisible(h)) return true;
    uint pid; GetWindowThreadProcessId(h, out pid);
    string pname = "";
    try { pname = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch {}
    if(pname.ToLower()=="electron"){
      RECT r; GetWindowRect(h, out r);
      int area = (r.R-r.L)*(r.B-r.T);
      if(area > FoundArea){ FoundArea=area; FoundKiosk=h; }
    }
    return true;
  }
  public static IntPtr FindKiosk(){ FoundKiosk=IntPtr.Zero; FoundArea=0; EnumWindows(EnumCb, IntPtr.Zero); return FoundKiosk; }
  public static uint ThreadOf(IntPtr h){ uint pid; return GetWindowThreadProcessId(h, out pid); }
  public static uint PidOf(IntPtr h){ uint pid; GetWindowThreadProcessId(h, out pid); return pid; }
  public static string TitleOf(IntPtr h){ var sb=new StringBuilder(256); GetWindowText(h, sb, 256); return sb.ToString(); }
  // Tap a physical key (vk + US scancode), optionally with Shift/Ctrl held. Char translation is done by the
  // FOREGROUND (kiosk) thread's active layout — the whole point of the test.
  public static void Tap(byte vk, IntPtr hklEN, bool shift, bool ctrl){
    uint sc = MapVirtualKeyEx(vk, 0, hklEN);
    if(ctrl)  keybd_event(0x11, 0, 0, UIntPtr.Zero);
    if(shift) keybd_event(0x10, 0, 0, UIntPtr.Zero);
    keybd_event(vk, (byte)sc, 0, UIntPtr.Zero);
    keybd_event(vk, (byte)sc, KEYEVENTF_KEYUP, UIntPtr.Zero);
    if(shift) keybd_event(0x10, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    if(ctrl)  keybd_event(0x11, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp | Out-Null

if(-not (Test-Path $cmdFile)){ OutW "NO CMD FILE"; exit }
$raw = Get-Content $cmdFile -Raw
$raw = $raw -replace "^﻿",""
$parts = $raw -split "`r?`n"
$cmd = ($parts[0] -replace '[^A-Za-z]','')
$payload = if($parts.Count -ge 2){ $parts[1] } else { "" }

$hklEN = [T09U]::LoadKeyboardLayout("00000409", 1)  # KLF_ACTIVATE (affects only THIS task thread)

function LayoutStr($h){
  if($h -eq [IntPtr]::Zero){ return "hwnd=0 (none)" }
  $tid = [T09U]::ThreadOf($h)
  $pid = [T09U]::PidOf($h)
  $hkl = [T09U]::GetKeyboardLayout($tid)
  $lang = ([int64]$hkl) -band 0xFFFF
  $title = [T09U]::TitleOf($h)
  return ("hwnd=0x{0:X} pid={1} tid={2} hkl=0x{3:X} lang=0x{4:X4} title='{5}'" -f ([int64]$h),$pid,$tid,([int64]$hkl),$lang,$title)
}

$k = [T09U]::FindKiosk()
$stamp = (Get-Date).ToString('HH:mm:ss')
OutW ("==== RUN $stamp cmd=[$cmd] ====")
OutW ("hklEN loaded = 0x{0:X}" -f [int64]$hklEN)
OutW ("KIOSK " + (LayoutStr $k))
OutW ("FG    " + (LayoutStr ([T09U]::GetForegroundWindow())))

switch($cmd){
  'report' { }
  'seten' {
    $HWND_BROADCAST = [IntPtr]0xFFFF
    if($k -ne [IntPtr]::Zero){ [void][T09U]::PostMessage($k, [T09U]::WM_INPUTLANGCHANGEREQUEST, [IntPtr]0, $hklEN) }
    [void][T09U]::PostMessage([T09U]::GetForegroundWindow(), [T09U]::WM_INPUTLANGCHANGEREQUEST, [IntPtr]0, $hklEN)
    [void][T09U]::PostMessage($HWND_BROADCAST, [T09U]::WM_INPUTLANGCHANGEREQUEST, [IntPtr]0, $hklEN)
    Start-Sleep -Milliseconds 700
    OutW ("AFTER KIOSK " + (LayoutStr $k))
    OutW ("AFTER FG    " + (LayoutStr ([T09U]::GetForegroundWindow())))
  }
  'sendcode' {
    $target = if($k -ne [IntPtr]::Zero){ $k } else { [T09U]::GetForegroundWindow() }
    OutW ("SENDCODE target " + (LayoutStr $target) + "  payloadLen=" + $payload.Length)
    Start-Sleep -Milliseconds 300
    $i = 0
    while($i -lt $payload.Length){
      if(($i+4) -le $payload.Length -and $payload.Substring($i,4) -eq '~GS~'){
        [T09U]::Tap(0xDD, $hklEN, $false, $true)   # Ctrl+OEM_6 => GS 0x1D under EN
        $i += 4
      } else {
        $ch = $payload[$i]
        $vks = [T09U]::VkKeyScanEx($ch, $hklEN)
        if($vks -eq -1){ OutW ("  SKIP untypeable U+{0:X4}" -f [int]$ch); $i++; continue }
        $vk = [byte]($vks -band 0xFF)
        $shift = ((($vks -shr 8) -band 1) -eq 1)
        $ctrl  = ((($vks -shr 8) -band 2) -eq 2)
        [T09U]::Tap($vk, $hklEN, $shift, $ctrl)
        $i++
      }
      Start-Sleep -Milliseconds 6
    }
    [T09U]::Tap(0x0D, $hklEN, $false, $false)   # Enter terminator
    OutW "SENDCODE done (+Enter)"
  }
  default { OutW "UNKNOWN CMD" }
}
OutW "==== END ===="
