$ErrorActionPreference='Stop'
$lock=$null;$acquired=$false
try {
 . (Join-Path $PSScriptRoot 'AccountCore.ps1')
 . (Join-Path $PSScriptRoot 'UsageCore.ps1')
 Initialize-AccountCore
 $lock=New-Object Threading.Mutex($false,('Local\ClaudeAccountSwitcherUsage-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
 try{$acquired=$lock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$acquired=$true}
 if(-not $acquired){exit 0}
 $path=Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher\usage.json'
 $cache=Read-Json $path
 if(-not $cache.ContainsKey('Accounts')){$cache['Accounts']=$json.DeserializeObject('{}')}
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 if($cache['BackoffUntil'] -and [double]$cache['BackoffUntil'] -gt $now){exit 0}
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $deadline=$now+60000
 foreach($entry in @($index['Accounts'])) {
  if($entry['AuthKind'] -and ($entry['AuthKind'] -ne 'OAuthAccess' -or $entry['Validation'] -ne 'validated')){continue}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($now -gt $deadline){break}
  $id=[string]$entry['Id'];if($id -notmatch '^[0-9a-f]{32}$'){continue}
  $record=$cache['Accounts'][$id]
  if(-not (Test-UsageDue $record $now $cache['BackoffUntil'])){continue}
  $credential=$null
  try{
   $selection=Get-UsageCredential $entry
   if($selection['Busy']){continue}
   $credential=$selection['Credential']
   if(-not $credential -or -not $credential['accessToken'] -or (-not $credential['ExpiryUnknown'] -and (-not $credential['expiresAt'] -or [double]$credential['expiresAt'] -le ($now+30000)))){$result=@{Status='expired'}}
   else{$result=Read-UsageResponse $credential}
  }catch{$result=@{Status='unavailable'}}
  finally{$credential=$null;$snapshot=$null;$current=$null}
  $cache['Accounts'][$id]=Update-UsageRecord $record $result $now
  if($result['Status'] -eq 'rate_limited'){$cache['BackoffUntil']=Get-UsageRetryAt $result['RetryAfter'] $now}
  Write-Json $path $cache
  if($result['Status'] -eq 'rate_limited'){break}
 }
 exit 0
}catch{exit 1}
finally{if($acquired){$lock.ReleaseMutex()};if($lock){$lock.Dispose()}}
