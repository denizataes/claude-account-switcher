# Nonsecret UI preferences. Authentication state uses a separate mutex/journal.
$script:alertSessionSeen=@{}
function Get-PreferencePath {return Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher\preferences.json'}
function Read-Preferences {
 $value=Read-Json (Get-PreferencePath)
 if(-not $value.ContainsKey('Favorites')){$value['Favorites']=@()}
 if(-not $value.ContainsKey('AlertsEnabled')){$value['AlertsEnabled']=$true}
 if(-not $value.ContainsKey('AlertWindows')){$value['AlertWindows']=@{}}
 if(-not $value.ContainsKey('Hotkeys')){$value['Hotkeys']=@{}}
 if(-not ($value['Favorites'] -is [Collections.IList]) -or -not ($value['AlertsEnabled'] -is [bool]) -or -not ($value['AlertWindows'] -is [Collections.IDictionary]) -or -not ($value['Hotkeys'] -is [Collections.IDictionary])){throw 'Preference file is invalid. It was left unchanged.'}
 return $value
}
function Invoke-PreferenceUpdate($update,$rollback=$null) {
 $mutex=[Threading.Mutex]::new($false,('Local\ClaudeAccountSwitcherPreferences-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
 $owned=$false
 try{
  try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
  if(-not $owned){throw 'Another preference update is in progress.'}
  $value=Read-Preferences
  $before=$json.Serialize($value)
  try{
   $result=& $update $value
   if($before -cne $json.Serialize($value)){Write-Json (Get-PreferencePath) $value}
   return $result
  }catch{if($rollback){& $rollback};throw}
 }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Set-AccountFavorite([string]$id,[bool]$enabled,$liveIds) {
 if([string]::IsNullOrEmpty($id) -or $id -notin @($liveIds)){throw 'Account is no longer saved.'}
 Invoke-PreferenceUpdate {
  param($value)
  $favorites=[Collections.Generic.List[string]]::new()
  foreach($favorite in $value['Favorites']){if($favorite -in @($liveIds) -and $favorite -ne $id){$favorites.Add([string]$favorite)}}
  if($enabled){$favorites.Add($id)};$value['Favorites']=$favorites.ToArray()
 }|Out-Null
}
function Set-UsageAlerts([bool]$enabled) {Invoke-PreferenceUpdate {param($value)$value['AlertsEnabled']=$enabled}|Out-Null}
function Get-UsageAlerts($entries,[string]$activeIdentity,$cache,[long]$now,[bool]$baseline=$false) {
 # Existing successful cache only. Never fetch or refresh credentials here.
 return @(Invoke-PreferenceUpdate {
  param($value)
  $liveIds=@($entries|ForEach-Object {$_['Id']})
  $favorites=[Collections.Generic.List[string]]::new();foreach($favorite in $value['Favorites']){if($favorite -in $liveIds){$favorites.Add([string]$favorite)}};$value['Favorites']=$favorites.ToArray()
  $windows=$value['AlertWindows']
  foreach($key in @($script:alertSessionSeen.Keys)){if(($key -replace '\|(?:FiveHour|SevenDay)$','') -notin $liveIds){[void]$script:alertSessionSeen.Remove($key)}}
  foreach($key in @($windows.Keys)){if(($windows[$key]['AccountId']) -notin $liveIds -or $key -notin @(([string]$windows[$key]['AccountId']+'|FiveHour'),([string]$windows[$key]['AccountId']+'|SevenDay'))){[void]$windows.Remove($key)}}
  $candidates=@()
  foreach($entry in @($entries)){
   if($entry['AuthKind'] -and ($entry['AuthKind'] -ne 'OAuthAccess' -or $entry['Validation'] -ne 'validated')){continue}
   $record=$cache['Accounts'][$entry['Id']]
   if(-not $record -or $record['Status'] -ne 'ok' -or -not $record['UpdatedAt']){continue}
   $age=$now-[long]$record['UpdatedAt'];if($age -lt -60000 -or $age -gt 300000){continue}
   foreach($period in @('FiveHour','SevenDay')){
    $window=$record[$period];if(-not $window -or $window['Stale'] -or $null -eq $window['UsedPercentage']){continue}
    if(-not $window['ObservedAt'] -or ($now-[long]$window['ObservedAt']) -lt -60000 -or ($now-[long]$window['ObservedAt']) -gt 300000){continue}
    $used=0.0;if(-not [double]::TryParse([string]$window['UsedPercentage'],[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$used) -or [double]::IsNaN($used) -or [double]::IsInfinity($used) -or $used -lt 0 -or $used -gt 100){continue}
    $reset=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$window['ResetsAt'],[ref]$reset) -or $reset.ToUnixTimeMilliseconds() -le $now){continue}
    $key=[string]$entry['Id']+'|'+$period;$resetKey=$reset.ToUnixTimeMilliseconds().ToString()
    $firstInSession=-not $script:alertSessionSeen.ContainsKey($key)
    $script:alertSessionSeen[$key]=$true
    $state=$windows[$key]
    $firstObservation=-not $state
    if(-not $state -or $state['Reset'] -ne $resetKey){$state=@{AccountId=$entry['Id'];Reset=$resetKey;Threshold=0};$windows[$key]=$state}
    $threshold=if($used -ge 95){95}elseif($used -ge 80){80}else{0}
    if($threshold -gt [int]$state['Threshold']){
     $state['Threshold']=$threshold
     if(-not $baseline -and -not $firstObservation -and -not $firstInSession -and $value['AlertsEnabled'] -and -not [string]::IsNullOrEmpty($activeIdentity) -and $entry['Identity'] -eq $activeIdentity){$candidates+=,@{AccountId=$entry['Id'];Name=$entry['Name'];Period=$period;Threshold=$threshold;Used=$used}}
    }
   }
  }
  # One balloon per refresh avoids a two-window burst; both windows are consumed.
  if($candidates.Count){$candidates|Sort-Object Threshold -Descending|Select-Object -First 1}
 })
}
