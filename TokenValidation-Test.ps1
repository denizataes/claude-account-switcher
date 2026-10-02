$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Web.Extensions
$json=[Web.Script.Serialization.JavaScriptSerializer]::new()
. (Join-Path $PSScriptRoot 'TokenCore.ps1')
$script:body='{"account":{"uuid":"00000000-0000-0000-0000-000000000001","email":"fixture@example.invalid"}}';$script:status=200;$script:calls=0
function New-TokenReadRequest([string]$url) {
 $script:calls++;$script:url=$url
 $request=[pscustomobject]@{Method='';AllowAutoRedirect=$true;Timeout=0;ReadWriteTimeout=0;UserAgent='';ContentType='';Headers=@{}}
 $request|Add-Member ScriptMethod Abort {}
 $request|Add-Member ScriptMethod GetResponse {
  $response=[pscustomobject]@{StatusCode=$script:status}
  $response|Add-Member ScriptMethod GetResponseStream {return [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($script:body))}
  $response|Add-Member ScriptMethod Close {}
  return $response
 }
 $script:request=$request;return $request
}
$result=Invoke-TokenReadCheck 'OAuthAccess' 'fixture-secret'
if($result.Status -ne 'validated' -or $result.AccountUuid -ne '00000000-0000-0000-0000-000000000001'){throw 'Profile identity validation failed'}
if($script:url -ne 'https://api.anthropic.com/api/oauth/profile' -or $script:request.Method -ne 'GET' -or $script:request.AllowAutoRedirect){throw 'OAuth fixed readonly route/redirect guard failed'}
$script:body='{"data":[]}'
if((Invoke-TokenReadCheck 'ApiKey' 'fixture-secret').Status -ne 'validated' -or $script:url -ne 'https://api.anthropic.com/v1/models?limit=1' -or $script:request.Headers['anthropic-version'] -ne '2023-06-01'){throw 'API readonly validation failed'}
$before=$script:calls;if((Invoke-TokenReadCheck 'SetupToken' 'fixture-secret').Status -ne 'unverified' -or $script:calls -ne $before){throw 'Setup token triggered unsupported validation'}
foreach($case in @(@{Status=302;Body='{}'},@{Status=401;Body='{}'},@{Status=200;Body='{"account":{}}'},@{Status=200;Body=('a'*131073)})){
 $script:status=$case.Status;$script:body=$case.Body;$rejected=$false
 try{[void](Invoke-TokenReadCheck 'OAuthAccess' 'fixture-secret')}catch{$rejected=$true;if($_.Exception.Message -like '*fixture-secret*'){throw 'Validation error exposed token'}}
 if(-not $rejected){throw 'Redirect/auth/missing scope/oversized response accepted'}
}
Write-Host 'PASS: fixed HTTPS readonly profile/models routes, correct API headers, no redirects, setup token unverified/no requests, rejected HTTP/auth/malformed/oversized responses, sanitized errors. Mock requests only.'
