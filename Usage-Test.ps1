$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Web.Extensions
$json=New-Object System.Web.Script.Serialization.JavaScriptSerializer
. (Join-Path $PSScriptRoot 'UsageCore.ps1')
. (Join-Path $PSScriptRoot 'TrayUI.ps1')
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$reset=[DateTimeOffset]::UtcNow.AddHours(4).ToString('o')
$window=Convert-UsageWindow @{utilization=5.5;resets_at=$reset}
if($window.UsedPercentage -ne 5.5 -or -not $window.ResetsAt){throw 'Exact window parse failed'}
foreach($bad in @($null,@{utilization=$null},@{utilization='5'},@{utilization=-1},@{utilization=[double]::NaN})){if($null -ne (Convert-UsageWindow $bad)){throw 'Invalid quota became a number'}}
if((Convert-UsageWindow @{utilization=0;resets_at=$null}).UsedPercentage -ne 0){throw 'Real zero rejected'}
if((Convert-UsageWindow @{utilization=100;resets_at=$null}).UsedPercentage -ne 100){throw 'Real 100 rejected'}
if(Test-UsageDue @{CheckedAt=$now-299999} $now $null){throw 'TTL bypass'}
if(-not (Test-UsageDue @{CheckedAt=$now-300000} $now $null)){throw 'TTL boundary failed'}
if(Test-UsageDue $null $now ($now+60000)){throw 'Global backoff bypass'}
if((Get-UsageRetryAt '3600' $now) -ne ($now+3600000)){throw 'Retry-After seconds not respected'}
if((Get-UsageRetryAt '0' $now) -lt ($now+300000)){throw '429 minimum backoff failed'}
if((Get-UsageRetryAt ([DateTimeOffset]::UtcNow.AddHours(2).ToString('r')) $now) -lt ($now+7100000)){throw 'Retry-After date failed'}
$record=Update-UsageRecord $null @{Status='ok';FiveHour=$window;SevenDay=$null} $now
foreach($status in @('auth','forbidden','rate_limited','unavailable','expired')){$record=Update-UsageRecord $record @{Status=$status} ($now+1);if($record.FiveHour.UsedPercentage -ne 5.5 -or $record.UpdatedAt -ne $now){throw 'Last known quota lost'}}
$partial=Update-UsageRecord $record @{Status='ok';FiveHour=$null;SevenDay=@{UsedPercentage=22;ResetsAt=$reset}} ($now+2)
if($partial.FiveHour.UsedPercentage -ne 5.5 -or -not $partial.FiveHour.Stale){throw 'Missing period erased last known or lost stale marker'}
$script:busyLock=$true;$script:disposed=0
function New-UsageAccountLock {$fake=New-Object psobject;$fake|Add-Member ScriptMethod WaitOne {param($timeout) return (-not $script:busyLock)};$fake|Add-Member ScriptMethod ReleaseMutex {};$fake|Add-Member ScriptMethod Dispose {$script:disposed++};return $fake}
function Get-State {if($script:busyLock){throw 'Read during account operation'};return @{AccountPresent=$true;Account=@{accountUuid='active'};Credential=@{accessToken='fake-live'}}}
function Read-Secret($path) {return @{Account=@{accountUuid='inactive'};Credential=@{accessToken='fake-snapshot'}}}
$journalPath=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N')+'.missing');$store='C:\FakeStore'
if(-not (Get-UsageCredential @{Identity='active';Id='id'}).Busy){throw 'Busy operation not skipped'}
$script:busyLock=$false
if((Get-UsageCredential @{Identity='active';Id='id'}).Credential.accessToken -ne 'fake-live'){throw 'Fresh active credential not preferred'}
if((Get-UsageCredential @{Identity='inactive';Id='id'}).Credential.accessToken -ne 'fake-snapshot'){throw 'Inactive snapshot not selected'}
if($null -ne (Get-UsageCredential @{Identity='wrong';Id='id'}).Credential){throw 'Snapshot identity mismatch accepted'}
$script:selected=0
$entries=@(@{Name='Fixture A';Identity='a';Id='a'},@{Name='Fixture B';Identity='b';Id='b'})
$usage=@{a=@{Status='ok';UpdatedAt=$now;FiveHour=$window;SevenDay=$null};b=@{Status='auth';UpdatedAt=$now-600000;FiveHour=$window;SevenDay=$null}}
$form=New-AccountPopup $entries 'b' {param($number)$script:selected=$number} {} {} {} $true {} $usage $false {}
try{
 $form.TopMost=$false;$form.Location=New-Object Drawing.Point(-32000,-32000);$form.Show();[Windows.Forms.Application]::DoEvents()
 $list=@($form.Controls|Where-Object {$_.Tag -is [string] -and $_.Tag -eq 'AccountList'})[0]
 $card=$list.Controls[0];if($card.Tag.Number -ne 2 -or $card.AccessibleName -notmatch 'Fixture B'){throw 'Active original second account not first'};$meter=@($card.Controls|Where-Object {$_.Tag -is [Collections.IDictionary] -and $_.Tag.Key -eq 'FiveHour'})[0]
 $title=@($meter.Controls|Where-Object {$_.Tag -eq 'MeterTitle'})[0]
 if($title.Text -notmatch 'son okuma'){throw 'Stale percentage presented as fresh'}
 $track=@($meter.Controls|Where-Object {$_.Tag -eq 'MeterTrack'})[0];$fill=$track.Controls[0]
 $method=[Windows.Forms.Control].GetMethod('OnClick',[Reflection.BindingFlags]'Instance,NonPublic');[void]$method.Invoke($fill,@([EventArgs]::Empty))
 if($script:selected -ne 2){throw 'Nested progress click selected wrong account'}
 Write-Host 'PASS: exact/nullable quotas, TTL/backoff, Retry-After, stale preservation, busy operation skip, credential identity, nested card click. No network or real credentials used.'
}finally{$form.Dispose()}

