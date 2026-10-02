param([switch]$QuietStartup)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$instance=New-Object Threading.Mutex($false,('Local\ClaudeAccountSwitcherTray-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
try{$ownsInstance=$instance.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsInstance=$true}
if (-not $ownsInstance) { $instance.Dispose(); exit 0 }
$notify=$null
$startupFailed=$false
try {
 . (Join-Path $PSScriptRoot 'AccountCore.ps1')
 . (Join-Path $PSScriptRoot 'TraySupport.ps1')
 . (Join-Path $PSScriptRoot 'TrayUI.ps1')
 . (Join-Path $PSScriptRoot 'TokenUI.ps1')
 . (Join-Path $PSScriptRoot 'UsageCore.ps1')
 . (Join-Path $PSScriptRoot 'TrayRuntime.ps1')
 . (Join-Path $PSScriptRoot 'PreferenceCore.ps1')
 $shutdown=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,('Local\ClaudeAccountSwitcherTrayShutdown-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
 $shutdown.Reset() | Out-Null
 $ready=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,('Local\ClaudeAccountSwitcherTrayReady-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
 Initialize-AccountCore
 $script:busy=$false
 $script:loginProcess=$null
 $script:usageProcess=$null;$script:lastUsageCheck=0L;$script:lastUsagePaint=0L;$script:nextUsageCheck=0L
 $script:usagePath=Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher\usage.json'
 $notify=New-Object Windows.Forms.NotifyIcon
 $notify.Icon=$script:uiIcon
 $notify.Text='Claude - Hesap Secici'
 
 $script:popup=$null
 $script:tooltipIdentity='';$script:tooltipConfigStamp='';$script:lastTooltipHover=0L
 function Update-AccountTooltip([switch]$ResolveIdentity) {
  if($ResolveIdentity){$script:tooltipIdentity=Get-UIActiveIdentity;$script:tooltipConfigStamp=$script:trayJsonCache['identity|'+$configPath].Stamp}
  $known=(Get-UIIdentityStamp) -ne $script:tooltipConfigStamp
  $accounts=Get-UIAccounts;$cache=Get-UsageCache
  $text=Get-AccountTooltip @($accounts['Accounts']) $script:tooltipIdentity $cache['Accounts'] ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) $known
  if($notify.Text -ne $text){$notify.Text=$text}
 }
 function Show-Error($message) { [void][Windows.Forms.MessageBox]::Show($message,'Claude Hesap Secici',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) }
 $confirm={param($count) Show-CloseConfirmation $count}
 function Ask-Name([string]$title) { return Show-NameDialog $title }
 function Run-Action([string]$action,[int]$number,[string]$label) {
  if ($script:busy) {return}
  $script:busy=$true
  try {
   if ($action -eq 'Add') {
    $preparationLock=New-Object Threading.Mutex($false,('Local\ClaudeAccountSwitcher-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    $prepared=$false
    try {
     if (-not $preparationLock.WaitOne(0)) {throw 'Baska bir hesap islemi devam ediyor.'}
     $prepared=$true
     Initialize-AccountCore;Assert-Environment
     if (-not (Close-ClaudeWithConsent $confirm)) {return}
    } finally {if ($prepared) {$preparationLock.ReleaseMutex()};$preparationLock.Dispose()}
    # Login stays in its own interactive console; the tray remains responsive.
    $escapedLabel=$label.Replace("'","''")
    $escapedScript=(Join-Path $PSScriptRoot 'Claude-Hesap.ps1').Replace("'","''")
    $code="& '$escapedScript' -Add -Name '$escapedLabel'; exit `$LASTEXITCODE"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $script:loginProcess=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -WindowStyle Normal -PassThru
    return
   }
   if (Invoke-AccountOperation $action $number $label $confirm) {
    Update-AccountTooltip -ResolveIdentity
    $script:nextUsageCheck=0L
    $notify.ShowBalloonTip(2500,'Claude Hesap Seçici',$(if ($action -eq 'Select') {'Hesap değişti. Sahne senin. Normal claude komutunu kullanabilirsin.'} else {'Hesap kaydedildi. Kulise hoş geldin.'}),[Windows.Forms.ToolTipIcon]::Info)
   }
  } catch {Show-Error $_.Exception.Message}
  finally {if (-not $script:loginProcess) {$script:busy=$false}}
 }
 function Set-Startup([bool]$enabled) {
  Set-TrayStartup $enabled ([Environment]::GetFolderPath('Startup')) $PSScriptRoot
 }
 function Check-UsageAlerts([bool]$baseline=$false) {
  try{
   $accounts=Get-UIAccounts;$cache=Get-UsageCache
   $alerts=@(Get-UsageAlerts @($accounts['Accounts']) (Get-UIActiveIdentity) $cache ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) $baseline)
   if($alerts.Count){$alert=$alerts[0];$period=if($alert.Period -eq 'FiveHour'){'5 saatlik'}else{'Haftalık'};$notify.ShowBalloonTip(5000,'Limit yaklaşırken',[string]$alert.Name+': '+$period+' limitin %'+$alert.Threshold+' eşiği geçildi. Hesap değiştirmek sana bağlı.',[Windows.Forms.ToolTipIcon]::Warning)}
  }catch{# Invalid/busy preferences fail closed: no notification or overwrite.
  }
 }
 function Change-Favorite([string]$id,[bool]$enabled) {
  try{$accounts=Get-UIAccounts;Set-AccountFavorite $id $enabled @($accounts['Accounts']|ForEach-Object {$_['Id']});$script:popupFingerprint='';if($script:popup){$script:popup.Hide()};Show-AccountPanel}catch{Show-Error $_.Exception.Message}
 }
 function Change-Alerts([bool]$enabled) {try{Set-UsageAlerts $enabled;$script:popupFingerprint='';Check-UsageAlerts $true}catch{Show-Error $_.Exception.Message}}
 function Add-TokenAccount {
  if($script:busy){return}
  $script:busy=$true;$data=$null
  try{
   $data=Show-TokenDialog
   if($data){Invoke-TokenImport $data.Kind $data.Token $data.Name $false $data.Validation;$script:nextUsageCheck=0L;$script:popupFingerprint='';Update-AccountTooltip -ResolveIdentity;$notify.ShowBalloonTip(2500,'Token kaydedildi','Etkinleştirmek için listeden seç. Geçerlilik ve süre bilgisi türüne göre sınırlıdır.',[Windows.Forms.ToolTipIcon]::Info)}
  }catch{Show-Error $_.Exception.Message}
  finally{if($data){$data.Token=$null};$data=$null;$script:busy=$false}
 }
 
 function Show-AccountPanel {
  if($script:busy){return}
  if($script:popup -and $script:popup.Visible){$script:popup.Hide();return}
  $uiIndex=Get-UIAccounts;$entries=@($uiIndex['Accounts'])
  $activeId=Get-UIActiveIdentity
  Start-UsageRefresh
  $usage=Get-UsageCache
  Check-UsageAlerts
  $preferences=Read-Preferences
  Update-AccountTooltip -ResolveIdentity
  $startupChecked=Test-OwnedTrayShortcut (Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Hesap Secici.lnk') $PSScriptRoot
  $fingerprint=(Get-TrayJsonStamp $indexPath)+'|'+$activeId+'|'+$startupChecked+'|'+(Get-TrayJsonStamp (Get-PreferencePath))
  if(-not $script:popup -or $script:popupFingerprint -ne $fingerprint){
   if($script:popup){$script:popup.Dispose()}
   $script:popup=New-AccountPopup $entries $activeId {param($number)Run-Action 'Select' $number ''} {$name=Ask-Name 'Mevcut hesabı kaydet';if($name){Run-Action 'Import' 0 $name}} {$name=Ask-Name 'Yeni hesabı ekle';if($name){Run-Action 'Add' 0 $name}} {param($enabled)try{Set-Startup $enabled;$script:popupFingerprint=''}catch{Show-Error $_.Exception.Message}} $startupChecked {[Windows.Forms.Application]::ExitThread()} $usage['Accounts'] ([bool]$script:usageProcess) {Start-UsageRefresh} {Add-TokenAccount} $preferences['Favorites'] {param($id,$enabled)Change-Favorite $id $enabled} $preferences['AlertsEnabled'] {param($enabled)Change-Alerts $enabled}
   $script:popupFingerprint=$fingerprint
   $script:popup.Add_Deactivate({param($sender,$eventArgs)$sender.Hide()})
  }else{Update-PopupUsage $script:popup $usage['Accounts'] ([bool]$script:usageProcess)}
  $script:popup.Show()
  $area=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
  Fit-AccountPopup $script:popup $area
  $x=[Math]::Min($area.Right-$script:popup.Width-8,[Math]::Max($area.Left+8,[Windows.Forms.Cursor]::Position.X-$script:popup.Width+24))
  $y=[Math]::Max($area.Top+8,$area.Bottom-$script:popup.Height-8)
  $script:popup.Location=New-Object Drawing.Point($x,$y);$script:popup.Activate()
 }
 function Get-UsageCache {
  try{$cache=Read-TrayJson $script:usagePath;if(-not $cache.ContainsKey('Accounts')){$cache['Accounts']=@{}};return $cache}catch{return @{Accounts=@{}}}
 }
 function Start-UsageRefresh {
  if($script:usageProcess -or $script:busy){return}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($now -lt $script:nextUsageCheck){return};$script:lastUsageCheck=$now
  $cache=Get-UsageCache
  $uiIndex=Get-UIAccounts
  $script:nextUsageCheck=Get-NextUsageCheck @($uiIndex['Accounts']) $cache $now
  if($now -lt $script:nextUsageCheck){return}
  $script:nextUsageCheck=$now+300000
  $collector=Join-Path $PSScriptRoot 'Usage-Collector.ps1'
  $script:usageProcess=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$collector+'"')) -WindowStyle Hidden -PassThru
 }
 $notify.Add_MouseClick({param($sender,$eventArgs)try{Show-AccountPanel}catch{Show-Error $_.Exception.Message}})
 $notify.Add_MouseMove({$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();if(($now-$script:lastTooltipHover) -ge 3000){$script:lastTooltipHover=$now;try{Update-AccountTooltip}catch{}}})
 
 $timer=New-Object Windows.Forms.Timer;$timer.Interval=2500
 $timer.Add_Tick({
  if($script:tokenCleanups){Complete-TokenCleanup}
  if($shutdown.WaitOne(0)){[Windows.Forms.Application]::ExitThread();return}
  if($script:usageProcess -and $script:usageProcess.HasExited){$code=$script:usageProcess.ExitCode;$script:usageProcess.Dispose();$script:usageProcess=$null;$cache=Get-UsageCache;$uiIndex=Get-UIAccounts;$script:nextUsageCheck=[Math]::Max([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+30000,(Get-NextUsageCheck @($uiIndex['Accounts']) $cache ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())));if($code -ne 0){$script:nextUsageCheck=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()+300000};$script:lastUsagePaint=0L;Update-AccountTooltip;Check-UsageAlerts}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($script:popup -and $script:popup.Visible){
   $timer.Interval=1000;$stamp=Get-TrayJsonStamp $script:usagePath
   if($stamp -ne $script:lastUsageStamp -or ($now-$script:lastUsagePaint) -ge 60000){$script:lastUsagePaint=$now;$script:lastUsageStamp=$stamp;$cache=Get-UsageCache;Update-PopupUsage $script:popup $cache['Accounts'] ([bool]$script:usageProcess)}
   Start-UsageRefresh
  }elseif($script:loginProcess -or $script:usageProcess){$timer.Interval=1000}else{$timer.Interval=2500}
  if ($script:loginProcess -and $script:loginProcess.HasExited) {
   $code=$script:loginProcess.ExitCode;$script:loginProcess.Dispose();$script:loginProcess=$null;$script:busy=$false
   if($code -eq 0){$script:nextUsageCheck=0L;Update-AccountTooltip -ResolveIdentity}
   if ($code -eq 0) {$notify.ShowBalloonTip(2500,'Claude Hesap Secici','Yeni hesap kaydedildi. Listeden secebilirsiniz.',[Windows.Forms.ToolTipIcon]::Info)} else {Show-Error 'Hesap girisi tamamlanamadi. Onceki varsayilan hesap korundu.'}
   
  }
 })
 Update-AccountTooltip -ResolveIdentity
 Check-UsageAlerts $true
 $notify.Visible=$true;$timer.Start();Start-UsageRefresh;$ready.Set()|Out-Null
 [Windows.Forms.Application]::Run()
} catch {$startupFailed=$true;if($QuietStartup){[Console]::Error.WriteLine('Tray initialization failed: '+$_.Exception.GetType().Name)}else{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Claude Hesap Secici')}}
finally {
 if ($timer) {$timer.Stop();$timer.Dispose()}
 if ($notify) {$notify.Visible=$false;$notify.Dispose()}
 
 if ($script:popup) {$script:popup.Dispose()}
 if(Get-Command Dispose-UIResources -ErrorAction SilentlyContinue){Dispose-UIResources}
 if ($script:usageProcess) {$script:usageProcess.Dispose()}
 if ($shutdown) {$shutdown.Dispose()}
 if ($ready) {$ready.Dispose()}
 $instance.ReleaseMutex();$instance.Dispose()
}
if($startupFailed){exit 1}







