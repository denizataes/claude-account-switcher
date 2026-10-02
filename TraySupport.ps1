function Get-TrayStartupArguments([string]$app) { return '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $app 'Claude-Tray.ps1')+'" -QuietStartup' }
function Test-OwnedTrayShortcut([string]$path,[string]$app) {
 if(-not(Test-Path -LiteralPath $path)){return $false}
 $shell=$null;$link=$null
 try{
  $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($path)
  $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe';$legacy=Join-Path $env:WINDIR 'System32\wscript.exe'
  return ($link.TargetPath -ieq $powershell -and $link.Arguments -ieq (Get-TrayStartupArguments $app)) -or ($link.TargetPath -ieq $legacy -and $link.Arguments -eq ('"'+(Join-Path $app 'Claude-Tray.vbs')+'"'))
 }finally{if($link){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)};if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}}
}
function Set-TrayStartup([bool]$enabled,[string]$folder,[string]$app) {
 $path=Join-Path $folder 'Claude Hesap Secici.lnk'
 if((Test-Path -LiteralPath $path) -and -not(Test-OwnedTrayShortcut $path $app)){throw 'Ayni isimde baska bir kisayol var; degistirilmedi.'}
 if(-not $enabled){if(Test-Path -LiteralPath $path){[IO.File]::Delete($path)};return}
 $shell=$null;$link=$null
 try{
  [IO.Directory]::CreateDirectory($folder)|Out-Null
  $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($path)
  $link.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe';$link.Arguments=Get-TrayStartupArguments $app
  $link.WorkingDirectory=$app;$link.WindowStyle=7;$link.IconLocation=(Join-Path $app 'Claude-Switch.ico')+',0';$link.Save()
 }finally{if($link){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($link)};if($shell){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}}
}
function Test-ApprovedClaudeProcess($process,[string[]]$allowedPaths) {
 if ($process.ProcessName -ne 'claude' -or -not $process.Path -or [IO.Path]::GetFileName($process.Path) -ine 'claude.exe') { return $false }
 foreach ($allowed in $allowedPaths) { if ([IO.Path]::GetFullPath($process.Path) -ieq [IO.Path]::GetFullPath($allowed)) { return $true } }
 return $false
}
function Get-ClaudeProcessList {
 $allowed=@(Get-Command claude.exe -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object {$_.Source})
 $allowed+=Join-Path $env:USERPROFILE '.local\bin\claude.exe'
 $processes=@(Get-Process -Name claude -ErrorAction SilentlyContinue)
 foreach ($process in $processes) {
  if (-not (Test-ApprovedClaudeProcess $process $allowed)) { throw 'Calisan Claude process yolunu dogrulayamadim. Guvenli kapatma icin bu oturumu elle kapatin.' }
 }
 return $processes
}
function Close-ClaudeWithConsent([scriptblock]$confirm) {
 $processes=@(Get-ClaudeProcessList)
 if (-not $processes.Count) { return $true }
 if (-not (& $confirm $processes.Count)) { return $false }
 foreach ($process in $processes) {
  $fresh=Get-Process -Id $process.Id -ErrorAction SilentlyContinue
  if ($fresh) {
   if ($fresh.ProcessName -ne 'claude' -or $fresh.Path -ine $process.Path -or $fresh.StartTime -ne $process.StartTime) { throw 'Process kimligi degisti; kapatma iptal edildi.' }
   Stop-Process -Id $fresh.Id -Force -ErrorAction Stop
  }
 }
 $deadline=[DateTime]::UtcNow.AddSeconds(5)
 while ((Get-Process -Name claude -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
 if (Get-Process -Name claude -ErrorAction SilentlyContinue) { throw 'Claude oturumlari tamamen kapanmadi. Islem yapilmadi.' }
 return $true
}
function Invoke-AccountOperation([string]$Action,[int]$Number,[string]$Label,[scriptblock]$Confirm) {
 $lock=New-Object Threading.Mutex($false,('Local\ClaudeAccountSwitcher-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
 $acquired=$false
 try {
  if (-not $lock.WaitOne(0)) { throw 'Baska bir hesap islemi devam ediyor.' }
  $acquired=$true
  Initialize-AccountCore
  Assert-Environment
  if ($Action -eq 'Select') {
   $entries=@($index['Accounts'])
   if ($Number -lt 1 -or $Number -gt $entries.Count) {throw 'Gecersiz hesap numarasi.'}
   Assert-Account (Read-Secret (Join-Path $store ($entries[$Number-1]['Id']+'.bin')))
  }
  if ($Action -eq 'Import' -and -not(Get-State)['ManagedRoute']) {Assert-Account (Get-State)}
  if ($Action -in @('Add','Import') -and [string]::IsNullOrWhiteSpace($Label)) {throw 'Hesap adi bos olamaz.'}
  if($Action -eq 'Import') {
   if(Test-Path -LiteralPath $journalPath){throw 'Yarim kalan bir hesap islemi var. Once hesap secimini tamamlayin.'}
   if((Get-State)['ManagedRoute']){Save-CurrentToken $Label;return $true}
   $stable=$false
   for($attempt=0;$attempt -lt 3;$attempt++){
    $first=Get-State;$second=Get-State
    if($json.Serialize($first) -eq $json.Serialize($second)){Assert-Account $second;Save-Account $second $Label;$stable=$true;break}
   }
   if(-not $stable){throw 'Hesap yenileniyor. Biraz sonra tekrar deneyin.'}
   return $true
  }
  if (-not (Close-ClaudeWithConsent $Confirm)) { return $false }
  Assert-Safe
  Restore-Pending
  switch ($Action) {
   'Select' { Switch-Account $Number }
   'Add' { Add-Account $Label }
   default { throw 'Bilinmeyen islem.' }
  }
  return $true
 } finally { if ($acquired) { $lock.ReleaseMutex() }; $lock.Dispose() }
}
