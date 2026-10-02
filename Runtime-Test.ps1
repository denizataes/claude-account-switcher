$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Web.Extensions
$json=New-Object System.Web.Script.Serialization.JavaScriptSerializer
. (Join-Path $PSScriptRoot 'TrayRuntime.ps1')
$script:reads=0
function Read-Json($path){$script:reads++;if(Test-Path -LiteralPath $path){return $json.DeserializeObject([IO.File]::ReadAllText($path))};return $json.DeserializeObject('{}')}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeRuntimeTest-'+[guid]::NewGuid().ToString('N'))
try{
 New-Item -ItemType Directory -Path $temp|Out-Null
 $path=Join-Path $temp 'fixture.json';[IO.File]::WriteAllText($path,'{"oauthAccount":{"accountUuid":"a"}}')
 $first=Read-TrayJson $path;$second=Read-TrayJson $path
 if($script:reads -ne 1 -or -not [object]::ReferenceEquals($first,$second)){throw 'Unchanged file reparsed'}
 [IO.File]::WriteAllText($path,'{"oauthAccount":{"accountUuid":"b"}}');[IO.File]::SetLastWriteTimeUtc($path,[DateTime]::UtcNow.AddSeconds(1))
 if((Read-TrayJson $path)['oauthAccount']['accountUuid'] -ne 'b' -or $script:reads -ne 2){throw 'Same-size changed metadata ignored'}
 $configPath=Join-Path $temp 'large-config.json';[IO.File]::WriteAllText($configPath,'{"oauthAccount":{"accountUuid":"projected"},"projects":{"C:/A":{"large":"unrelated"}}}')
 if((Get-UIActiveIdentity) -ne 'projected' -or (Get-UIActiveIdentity) -ne 'projected'){throw 'Identity projection failed'}
 if($script:trayJsonCache['identity|'+$configPath].Value -isnot [string] -or $script:trayJsonCache.ContainsKey($configPath)){throw 'UI retained entire config dictionary'}
 $indexPath=Join-Path $temp 'missing-index.json'
 if(@((Get-UIAccounts)['Accounts']).Count){throw 'Empty index produced phantom account'}
 $now=1000000L;$cache=@{Accounts=@{a=@{CheckedAt=$now}}}
 if((Get-NextUsageCheck @(@{Id='a'}) $cache $now) -ne ($now+300000)){throw 'TTL scheduling wrong'}
 if((Get-NextUsageCheck @(@{Id='a'},@{Id='new'}) $cache $now) -ne $now){throw 'New account not immediately due'}
 $cache.BackoffUntil=$now+600000
 if((Get-NextUsageCheck @(@{Id='new'}) $cache $now) -ne $cache.BackoffUntil){throw 'New account bypassed global backoff'}
 $entries=@(@{Id='a';Identity='a';Name='Personal'},@{Id='b';Identity='b';Name='Work'},@{Id='c';Identity='c';Name='Demo'})
 $ordered=@(Get-OrderedUIAccounts $entries 'b')
 if(($ordered.Number -join ',') -ne '2,1,3' -or ($entries.Id -join ',') -ne 'a,b,c'){throw 'Ordering changed saved selection numbers/index'}
 if((@(Get-OrderedUIAccounts $entries 'unknown').Number -join ',') -ne '1,2,3'){throw 'Unknown identity incorrectly promoted account'}
 $quota=@{b=@{Status='ok';UpdatedAt=$now;FiveHour=@{UsedPercentage=0;ResetsAt=[DateTimeOffset]::FromUnixTimeMilliseconds($now+600000).ToString('o')}}}
 if((Get-AccountTooltip $entries 'b' $quota $now) -notlike '*Work*5sa %0'){throw 'Fresh zero tooltip missing'}
 if((Get-AccountTooltip $entries 'b' $quota ($now+300001)) -notlike '*eski'){throw 'Stale tooltip misleading'}
 if((Get-AccountTooltip $entries 'b' $quota $now $true) -notlike '*Son bilinen*'){throw 'External change not marked last-known'}
 if((Get-AccountTooltip $entries 'unknown' $quota $now) -like '*Personal*'){throw 'Unknown active fell back to first account'}
 if((Get-AccountTooltip $entries 'b' @{} $now) -like '*5sa*'){throw 'Missing quota fabricated'}
 $entries[1].Name=('long '+[char]0xD83D+[char]0xDE80)*30
 $tooltip=Get-AccountTooltip $entries 'b' $quota $now
 if($tooltip.Length -gt 63 -or $tooltip -match '[\uD800-\uDBFF](?![\uDC00-\uDFFF])'){throw 'Unicode tooltip limit split surrogate'}
 $before=$script:reads;$watch=[Diagnostics.Stopwatch]::StartNew()
 for($i=0;$i -lt 1000;$i++){[void](Get-TrayJsonStamp $configPath);[void](Get-AccountTooltip $entries 'b' $quota $now)}
 $watch.Stop();if($script:reads -ne $before){throw 'Tooltip path parsed account config'}
 Write-Host ('PASS: runtime cache, active-first original-index mapping, unknown/fresh zero/stale/last-known/missing/Unicode tooltip; 1000 metadata+format calls {0:N1}ms, zero JSON reads.' -f $watch.Elapsed.TotalMilliseconds)
}finally{if((Split-Path $temp -Leaf) -like 'ClaudeRuntimeTest-*' -and [IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force}}
