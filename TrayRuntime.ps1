# UI-only cache. Account mutations continue using fresh JSON in AccountCore.
$script:trayJsonCache=@{}
function Get-TrayJsonStamp([string]$path) {
 $file=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
 if(-not $file){return 'missing'}
 return $file.LastWriteTimeUtc.Ticks.ToString()+':'+$file.Length.ToString()
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
  $record=$cache['Accounts'][$entry['Id']]
  $due=if($record -and $record['CheckedAt']){[long]$record['CheckedAt']+300000}else{$now}
  $next=[Math]::Min($next,$due)
 }
 return $next
}
function Get-UIAccounts {
 $value=Read-TrayJson $indexPath
 if(-not $value.ContainsKey('Accounts')){$value['Accounts']=@()}
 return $value
}
function Get-UIActiveIdentity {
 $key='identity|'+$configPath
 $stamp=Get-TrayJsonStamp $configPath
 $cached=$script:trayJsonCache[$key]
 if($cached -and $cached.Stamp -eq $stamp){return $cached.Value}
 $config=Read-Json $configPath
 $identity=if($config['oauthAccount']){[string]$config['oauthAccount']['accountUuid']}else{''}
 $script:trayJsonCache[$key]=@{Stamp=$stamp;Value=$identity}
 return $identity
}
