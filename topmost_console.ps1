# topmost_console.ps1 — сделать ТЕКУЩУЮ консоль PowerShell always-on-top (HWND_TOPMOST).
# Запускать ДОТ-СОРСОМ в интерактивном PS: `Set-ExecutionPolicy Bypass -Scope Process -Force; . topmost_console.ps1`
# (если запустить как `powershell -File`, topmost получит окно дочернего процесса, а не интерактивное).
# Нужно на кассе КСО: окно РМК-«Продажа» (автозапуск user КСО) постоянно ворует фокус и накрывает консоль.
$s = '[DllImport("user32.dll")]public static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int cx,int cy,uint f);[DllImport("kernel32.dll")]public static extern IntPtr GetConsoleWindow();'
$t = Add-Type -MemberDefinition $s -Name WTop -PassThru
[void]$t::SetWindowPos($t::GetConsoleWindow(),[IntPtr]-1,0,0,0,0,0x43)   # -1=HWND_TOPMOST, 0x43=NOMOVE|NOSIZE|SHOWWINDOW
'TOPMOST-SET'
