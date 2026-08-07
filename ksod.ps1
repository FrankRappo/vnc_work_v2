# ksod.ps1 — clipboard command daemon for the cash. Focus-independent channel over RustDesk clipboard sync.
# Reads KSOCMD::<id>::<powershell>, runs it, writes KSORES::<id>::<output> back to the clipboard.
Add-Type -AssemblyName System.Windows.Forms
$OutputEncoding=[Text.UTF8Encoding]::new()
$lastId=""
[IO.File]::WriteAllText("C:\kso\ksod.alive", (Get-Date).ToString("s"))
while($true){
  try{
    $c=$null
    try{ $c=[Windows.Forms.Clipboard]::GetText() }catch{}
    if($c -and $c.StartsWith("KSOCMD::")){
      $rest=$c.Substring(8)
      $sep=$rest.IndexOf("::")
      if($sep -gt 0){
        $id=$rest.Substring(0,$sep)
        if($id -ne $lastId){
          $lastId=$id
          $cmd=$rest.Substring($sep+2)
          $out=""
          try{ $out=(Invoke-Expression $cmd 2>&1 | Out-String) }catch{ $out="EXC: "+$_.Exception.Message }
          $res="KSORES::"+$id+"::"+$out
          for($k=0;$k -lt 5;$k++){ try{ [Windows.Forms.Clipboard]::SetText($res); break }catch{ Start-Sleep -Milliseconds 120 } }
          [IO.File]::WriteAllText("C:\kso\ksod.alive", (Get-Date).ToString("s")+" id="+$id)
        }
      }
    }
  }catch{}
  Start-Sleep -Milliseconds 350
}
