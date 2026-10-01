param([string]$Select,[switch]$SaveCurrent,[switch]$Add,[string]$Name)
$ErrorActionPreference='Stop'
try {
 . (Join-Path $PSScriptRoot 'AccountCore.ps1')
 . (Join-Path $PSScriptRoot 'TraySupport.ps1')
 $confirm={param($count) (Read-Host "$count Claude oturumu kapatilacak; kaydedilmemis calisma kesilebilir. Devam? (E/H)") -ieq 'E'}
 if ($Select) {[void](Invoke-AccountOperation 'Select' ([int]$Select) '' $confirm);exit 0}
 if ($SaveCurrent) {[void](Invoke-AccountOperation 'Import' 0 $Name $confirm);exit 0}
 if ($Add) {[void](Invoke-AccountOperation 'Add' 0 $Name $confirm);exit 0}
 while ($true) {
  Initialize-AccountCore
  Write-Host "`nClaude Code - Hesap Secici"
  $entries=@($index['Accounts']);$current=Get-State
  for ($i=0;$i -lt $entries.Count;$i++) {
   $active=if ($current.AccountPresent -and $entries[$i]['Identity'] -eq $current.Account['accountUuid']) {' [aktif]'} else {''}
   Write-Host ("{0} - {1}{2}" -f ($i+1),$entries[$i]['Name'],$active)
  }
  Write-Host 'K - Mevcut hesabi kaydet | E - Yeni hesap ekle | 0 - Cikis'
  $choice=(Read-Host 'Secim').Trim()
  if ($choice -eq '0') {break}
  try {
   if ($choice -match '^\d+$') {[void](Invoke-AccountOperation 'Select' ([int]$choice) '' $confirm)}
   elseif ($choice -ieq 'K') {[void](Invoke-AccountOperation 'Import' 0 (Read-Host 'Hesap adi') $confirm)}
   elseif ($choice -ieq 'E') {[void](Invoke-AccountOperation 'Add' 0 (Read-Host 'Hesap adi') $confirm)}
  } catch {Write-Host ('Hata: '+$_.Exception.Message) -ForegroundColor Red}
 }
 exit 0
} catch {Write-Host ('Hata: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
