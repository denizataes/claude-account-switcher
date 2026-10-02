# UI-only cache. Account mutations continue using fresh JSON in AccountCore.
$script:trayJsonCache=@{}
function Get-TrayJsonStamp([string]$path) {
 try{$file=[IO.FileInfo]::new($path);if(-not $file.Exists){return 'missing'};return $file.LastWriteTimeUtc.Ticks.ToString()+':'+$file.Length.ToString()}catch{return 'missing'}
}
function Read-TrayJson([string]$path) {
 $stamp=Get-TrayJsonStamp $path
 $cached=$script:trayJsonCache[$path]
 if($cached -and $cached.Stamp -eq $stamp){return $cached.Value}
 $value=Read-Json $path
 $script:trayJsonCache[$path]=@{Stamp=$stamp;Value=$value}
 return $value
}
function Get-NextUsageCheck($entries,$cache,[long]$now) {
 if($cache['BackoffUntil'] -and [double]$cache['BackoffUntil'] -gt $now){return [long]$cache['BackoffUntil']}
 if(-not @($entries).Count){return $now+300000}
 $next=[long]::MaxValue
 foreach($entry in @($entries)){
  if($entry['AuthKind'] -and ($entry['AuthKind'] -ne 'OAuthAccess' -or $entry['Validation'] -ne 'validated')){continue}
  $record=$cache['Accounts'][$entry['Id']]
  $due=if($record -and $record['CheckedAt']){[long]$record['CheckedAt']+300000}else{$now}
  $next=[Math]::Min($next,$due)
 }
 return $(if($next -eq [long]::MaxValue){$now+300000}else{$next})
}
function Get-UIAccounts {
 $value=Read-TrayJson $indexPath
 if(-not $value.ContainsKey('Accounts')){$value['Accounts']=@()}
 return $value
}
function Get-UIActiveIdentity {
 $key='identity|'+$configPath
 $stamp=Get-UIIdentityStamp
 $cached=$script:trayJsonCache[$key]
 if($cached -and $cached.Stamp -eq $stamp){return $cached.Value}
 $accounts=Get-UIAccounts
 if($accounts['ActiveRoute']){
  $route=$accounts['ActiveRoute'];$identity=if($route['SettingsStamp'] -eq (Get-TrayJsonStamp (Join-Path $env:USERPROFILE '.claude\settings.json'))){[string]$route['Identity']}else{''}
  $script:trayJsonCache[$key]=@{Stamp=$stamp;Value=$identity};return $identity
 }
 $config=Read-Json $configPath
 $identity=if($config['oauthAccount']){[string]$config['oauthAccount']['accountUuid']}else{''}
 $script:trayJsonCache[$key]=@{Stamp=$stamp;Value=$identity}
 return $identity
}
function Get-UIIdentityStamp {
 return (Get-TrayJsonStamp $configPath)+'|'+(Get-TrayJsonStamp $indexPath)+'|'+(Get-TrayJsonStamp (Join-Path $env:USERPROFILE '.claude\settings.json'))
}
function Get-OrderedUIAccounts($entries,[string]$activeId,$favorites=@()) {
 for($pass=0;$pass -lt 3;$pass++){
  for($i=0;$i -lt @($entries).Count;$i++){
   $active=-not [string]::IsNullOrEmpty($activeId) -and $entries[$i]['Identity'] -eq $activeId
   $favorite=$entries[$i]['Id'] -in @($favorites)
   if(($pass -eq 0 -and $active) -or ($pass -eq 1 -and -not $active -and $favorite) -or ($pass -eq 2 -and -not $active -and -not $favorite)){@{Entry=$entries[$i];Number=$i+1;Active=$active;Favorite=$favorite}}
  }
 }
}
function Limit-NotifyText([string]$text,[int]$limit=63) {
 if($text.Length -le $limit){return $text}
 $length=$limit-1
 if($length -gt 0 -and [char]::IsHighSurrogate($text[$length-1])){$length--}
 return $text.Substring(0,[Math]::Max(0,$length))+[char]0x2026
}
function Get-AccountTooltip($entries,[string]$activeId,$usage,[long]$now,[bool]$lastKnown=$false) {
 if([string]::IsNullOrEmpty($activeId)){return 'Claude | Aktif hesap bilinmiyor'}
 $entry=@($entries|Where-Object {$_['Identity'] -eq $activeId})|Select-Object -First 1
 if(-not $entry){return 'Claude | Aktif hesap kaydedilmemis'}
 $name=([regex]::Replace([string]$entry['Name'],'[\p{Cc}\s]+',' ')).Trim()
 $suffix='';$record=if($usage){$usage[$entry['Id']]}else{$null};$window=if($record){$record['FiveHour']}else{$null}
 if($window -and $null -ne $window['UsedPercentage']){
  $stale=$record['Status'] -ne 'ok' -or $window['Stale'] -or -not $record['UpdatedAt'] -or ($now-[long]$record['UpdatedAt']) -gt 300000
  $reset=[DateTimeOffset]::MinValue
  if($window['ResetsAt'] -and [DateTimeOffset]::TryParse([string]$window['ResetsAt'],[ref]$reset) -and $reset.ToUnixTimeMilliseconds() -le $now){$stale=$true}
  $suffix=' | 5sa %'+([double]$window['UsedPercentage']).ToString('0.#',[Globalization.CultureInfo]::GetCultureInfo('tr-TR'))+$(if($stale){' eski'}else{''})
 }
 $prefix=if($lastKnown){'Claude | Son bilinen: '}else{'Claude | Aktif: '}
 $name=Limit-NotifyText $name (63-$prefix.Length-$suffix.Length)
 return Limit-NotifyText ($prefix+$name+$suffix)
}
