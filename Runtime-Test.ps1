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
 $indexPath=Join-Path $temp 'missing-index.json'
 if(@((Get-UIAccounts)['Accounts']).Count){throw 'Empty index produced phantom account'}
 $now=1000000L;$cache=@{Accounts=@{a=@{CheckedAt=$now}}}
 if((Get-NextUsageCheck @(@{Id='a'}) $cache $now) -ne ($now+300000)){throw 'TTL scheduling wrong'}
 if((Get-NextUsageCheck @(@{Id='a'},@{Id='new'}) $cache $now) -ne $now){throw 'New account not immediately due'}
 $cache.BackoffUntil=$now+600000
 if((Get-NextUsageCheck @(@{Id='new'}) $cache $now) -ne $cache.BackoffUntil){throw 'New account bypassed global backoff'}
 Write-Host 'PASS: JSON parse reuse, exact metadata invalidation, active identity changes, empty index, existing TTL/new account scheduling/global backoff.'
}finally{if((Split-Path $temp -Leaf) -like 'ClaudeRuntimeTest-*' -and [IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force}}
