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
  if ($Action -eq 'Import') {Assert-Account (Get-State)}
  if ($Action -in @('Add','Import') -and [string]::IsNullOrWhiteSpace($Label)) {throw 'Hesap adi bos olamaz.'}
  if($Action -eq 'Import') {
   if(Test-Path -LiteralPath $journalPath){throw 'Yarim kalan bir hesap islemi var. Once hesap secimini tamamlayin.'}
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
