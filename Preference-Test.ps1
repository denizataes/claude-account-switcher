$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudePreferencesTest-'+[guid]::NewGuid().ToString('N'))
$oldLocal=$env:LOCALAPPDATA
try{
 $env:LOCALAPPDATA=$temp
 . (Join-Path $PSScriptRoot 'AccountCore.ps1');Initialize-AccountCore
 . (Join-Path $PSScriptRoot 'PreferenceCore.ps1')
 . (Join-Path $PSScriptRoot 'TrayRuntime.ps1')
 $entries=@(@{Id='a';Identity='a';Name='First'},@{Id='b';Identity='b';Name='Active'},@{Id='c';Identity='c';Name='Favorite'})
 Set-AccountFavorite 'c' $true @('a','b','c')
 $value=Read-Preferences;$value['FutureField']=@{Keep=1};Write-Json (Get-PreferencePath) $value
 $ordered=@(Get-OrderedUIAccounts $entries 'b' $value.Favorites)
 if(($ordered.Number -join ',') -ne '2,3,1'){throw 'Active/favorite order lost selection index'}
 Set-AccountFavorite 'a' $true @('a','b','c');Set-AccountFavorite 'c' $false @('a','b','c')
 if((Read-Preferences).FutureField.Keep -ne 1 -or ((Read-Preferences).Favorites -join ',') -ne 'a'){throw 'Persistence/unknown fields failed'}
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$reset=[DateTimeOffset]::FromUnixTimeMilliseconds($now+3600000).ToString('o')
 $window=@{UsedPercentage=79;ResetsAt=$reset;ObservedAt=$now;Stale=$false}
 $record=@{Status='ok';UpdatedAt=$now;FiveHour=$window};$cache=@{Accounts=@{b=$record}}
 $startup=@{Accounts=@{a=@{Status='ok';UpdatedAt=$now;FiveHour=@{UsedPercentage=95;ResetsAt=$reset;ObservedAt=$now;Stale=$false}}}}
 if(@(Get-UsageAlerts $entries 'a' $startup $now).Count){throw 'First fresh observation emitted startup spam'}
 if(@(Get-UsageAlerts $entries 'b' $cache $now $true).Count){throw 'Startup emitted alert'}
 $window.UsedPercentage=80;$alerts=@(Get-UsageAlerts $entries 'b' $cache $now)
 if($alerts.Count -ne 1 -or $alerts[0].Threshold -ne 80){throw '80 threshold missing'}
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Repeated/restarted alert'}
 $window.UsedPercentage=95;if(@(Get-UsageAlerts $entries 'b' $cache $now)[0].Threshold -ne 95){throw '95 threshold missing'}
 $window.UsedPercentage=79;$window.ResetsAt=[DateTimeOffset]::FromUnixTimeMilliseconds($now+5400000).ToString('o');Get-UsageAlerts $entries 'b' $cache $now|Out-Null
 $script:alertSessionSeen=@{};$window.ObservedAt=$now-300001
 Get-UsageAlerts $entries 'b' $cache $now $true|Out-Null
 $window.ObservedAt=$now;$window.UsedPercentage=95
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Persisted low threshold plus stale startup cache caused startup alert'}
 $window.ResetsAt=[DateTimeOffset]::FromUnixTimeMilliseconds($now+7200000).ToString('o')
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count -ne 1){throw 'New reset did not permit alert'}
 $window.ResetsAt=[DateTimeOffset]::FromUnixTimeMilliseconds($now+10800000).ToString('o');$window.Stale=$true
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Stale window alert'};$window.Stale=$false
 $record.Status='auth';if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Error alert'};$record.Status='ok'
 $window.ObservedAt=$now-300001;if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Stale observed window alert'};$window.ObservedAt=$now
 if(@(Get-UsageAlerts $entries '' $cache $now).Count){throw 'Unknown active account alert'}
 $window.ResetsAt=[DateTimeOffset]::FromUnixTimeMilliseconds($now+14400000).ToString('o');Set-UsageAlerts $false
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Opt out ignored'};Set-UsageAlerts $true
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Opt-in replayed old threshold'}
 $window.ResetsAt=[DateTimeOffset]::FromUnixTimeMilliseconds($now-1).ToString('o');if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Past reset alert'}
 $window.ResetsAt='unknown';if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Missing reset alert'}
 $window.ResetsAt=[DateTimeOffset]::FromUnixTimeMilliseconds($now+18000000).ToString('o');$entries[1]['AuthKind']='SetupToken'
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Unsupported token alert'};$entries[1].Remove('AuthKind')
 $record.SevenDay=@{UsedPercentage=99;ResetsAt=$window.ResetsAt;ObservedAt=$now;Stale=$false}
 if(@(Get-UsageAlerts $entries 'b' $cache $now).Count -ne 1 -or @(Get-UsageAlerts $entries 'b' $cache $now).Count){throw 'Multiple period burst/dedupe failed'}
 Get-UsageAlerts @($entries[1]) 'b' $cache $now|Out-Null
 if((Read-Preferences).Favorites.Count -ne 0 -or (Read-Preferences).AlertWindows.Count -gt 2){throw 'Deleted account state not pruned'}
 $value=Read-Preferences;$value['Favorites']='invalid';Write-Json (Get-PreferencePath) $value
 $before=(Get-FileHash (Get-PreferencePath)).Hash;$failed=$false;try{Read-Preferences}catch{$failed=$true}
 if(-not $failed -or (Get-FileHash (Get-PreferencePath)).Hash -ne $before){throw 'Malformed prefs overwritten'}
 Write-Host 'PASS: favorites stable original-index order, persistence/pruning/unknown fields; active-only 80/95 alerts, reset/restart dedupe, opt-out, startup baseline, freshness/unsupported/unknown suppression, bounded state. Fake profiles/cache only.'
}finally{$env:LOCALAPPDATA=$oldLocal;if([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}}
$global:LASTEXITCODE=0
