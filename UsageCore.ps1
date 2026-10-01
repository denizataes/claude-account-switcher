function Convert-UsageWindow($value) {
 if($null -eq $value -or -not ($value -is [Collections.IDictionary]) -or -not $value.ContainsKey('utilization')) {return $null}
 $percent=$value['utilization']
 if($null -eq $percent -or $percent -is [string] -or $percent -is [bool]) {return $null}
 $number=[double]$percent
 if([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0 -or $number -gt 100) {return $null}
 $reset=$null
 if($value['resets_at']) {$date=[DateTimeOffset]::MinValue;if([DateTimeOffset]::TryParse([string]$value['resets_at'],[ref]$date)){$reset=$date.ToUniversalTime().ToString('o')}}
 return @{UsedPercentage=$number;ResetsAt=$reset}
}
function Get-UsageRetryAt([string]$header,[long]$now) {
 $delay=900000L
 $seconds=0.0
 if([double]::TryParse($header,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$seconds) -and $seconds -gt 0){$delay=[Math]::Max(300000L,$seconds*1000)}
 else {$date=[DateTimeOffset]::MinValue;if([DateTimeOffset]::TryParse($header,[ref]$date)){$delay=[Math]::Max(300000L,$date.ToUnixTimeMilliseconds()-$now)}}
 return [long]($now+$delay)
}
function Read-UsageResponse($credential) {
 # Fixed official host. No redirects, model calls, login, or refresh requests.
 $request=[Net.HttpWebRequest]::Create('https://api.anthropic.com/api/oauth/usage')
 $request.Method='GET';$request.AllowAutoRedirect=$false;$request.Timeout=8000;$request.ReadWriteTimeout=8000
 $request.UserAgent='ClaudeAccountSwitcher/1.3 (Windows; Claude Code 2.1.286)';$request.ContentType='application/json'
 $request.Headers['Authorization']='Bearer '+$credential['accessToken'];$request.Headers['anthropic-beta']='oauth-2025-04-20'
 $response=$null
 try {
  $response=$request.GetResponse()
  if([int]$response.StatusCode -ne 200){return @{Status='unavailable'}}
  $reader=New-Object IO.StreamReader($response.GetResponseStream())
  try{$buffer=New-Object char[] 131073;$length=0;while($length -lt $buffer.Length){$read=$reader.Read($buffer,$length,$buffer.Length-$length);if(-not $read){break};$length+=$read};if($length -ge $buffer.Length){return @{Status='invalid_response'}};$data=$json.DeserializeObject((New-Object string($buffer,0,$length)))}finally{$reader.Dispose()}
  $five=Convert-UsageWindow $data['five_hour'];$week=Convert-UsageWindow $data['seven_day']
  return @{Status=$(if($null -eq $five -and $null -eq $week){'unsupported'}else{'ok'});FiveHour=$five;SevenDay=$week}
 }catch [Net.WebException]{
  $response=$_.Exception.Response
  if($response){switch([int]$response.StatusCode){401{return @{Status='auth'}};403{return @{Status='forbidden'}};429{return @{Status='rate_limited';RetryAfter=$response.Headers['Retry-After']}}}}
  return @{Status='unavailable'}
 }catch{return @{Status='invalid_response'}}
 finally{if($response){$response.Dispose()};$request=$null}
}
function Update-UsageRecord($record,$result,[long]$now) {
 if($null -eq $record){$record=@{FiveHour=$null;SevenDay=$null;UpdatedAt=$null}}
 $record['Status']=$result['Status'];$record['CheckedAt']=$now
 if($result['Status'] -eq 'ok') {
  foreach($key in @('FiveHour','SevenDay')){
   if($null -ne $result[$key]){$result[$key]['ObservedAt']=$now;$result[$key]['Stale']=$false;$record[$key]=$result[$key]}
   elseif($null -ne $record[$key]){$record[$key]['Stale']=$true;if(-not $record[$key]['ObservedAt']){$record[$key]['ObservedAt']=$record['UpdatedAt']}}
  }
  $record['UpdatedAt']=$now
 }
 return $record
}
function Get-UsageCredential($entry) {
 $accountLock=New-UsageAccountLock
 $owned=$false
 try{
  try{$owned=$accountLock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
  if(-not $owned -or (Test-Path -LiteralPath $journalPath)){return @{Busy=$true}}
  $first=Get-State;$second=Get-State
  if($json.Serialize($first) -ne $json.Serialize($second)){return @{Busy=$true}}
  if($second.AccountPresent -and $second.Account['accountUuid'] -eq $entry['Identity']){return @{Credential=$second.Credential}}
  $snapshot=Read-Secret (Join-Path $store ($entry['Id']+'.bin'))
  if($snapshot.Account['accountUuid'] -ne $entry['Identity']){return @{Credential=$null}}
  return @{Credential=$snapshot.Credential}
 }finally{if($owned){$accountLock.ReleaseMutex()};$accountLock.Dispose()}
}
function New-UsageAccountLock {return New-Object Threading.Mutex($false,('Local\ClaudeAccountSwitcher-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))}
function Test-UsageDue($record,[long]$now,$backoffUntil) {
 if($backoffUntil -and [double]$backoffUntil -gt $now){return $false}
 return (-not $record -or -not $record['CheckedAt'] -or ($now-[double]$record['CheckedAt']) -ge 300000)
}
