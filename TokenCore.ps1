# Token routes use Claude's documented user-settings env support. No token is passed as an argument.
function Initialize-TokenCore {
 $script:settingsPath=Join-Path $env:USERPROFILE '.claude\settings.json'
 $script:routePath=Join-Path $store 'route.bin'
}
function Get-RouteKey([string]$kind) {
 if($kind -eq 'ApiKey'){return 'ANTHROPIC_API_KEY'}
 if($kind -in @('SetupToken','OAuthAccess')){return 'CLAUDE_CODE_OAUTH_TOKEN'}
 throw 'Desteklenmeyen token turu.'
}
function Get-RouteStamp {
 $file=[IO.FileInfo]::new($settingsPath)
 if(-not $file.Exists){return 'missing'}
 return $file.LastWriteTimeUtc.Ticks.ToString()+':'+$file.Length.ToString()
}
function Get-ManagedRoute {
 if(Test-Path -LiteralPath $routePath){$route=Read-Secret $routePath;if($route['Key'] -cnotin @('ANTHROPIC_API_KEY','CLAUDE_CODE_OAUTH_TOKEN') -or -not $route['Value'] -or [string]$route['Identity'] -notlike 'token-*'){throw 'Korumali token sahiplik kaydi gecersiz.'};return $route}
 return $null
}
function Get-ActiveManagedRoute {
 $route=Get-ManagedRoute
 if(-not $route){return $null}
 $settings=Read-Json $settingsPath
 if($settings['env'] -and $settings['env'].ContainsKey($route['Key']) -and [string]$settings['env'][$route['Key']] -ceq [string]$route['Value']){return $route}
 return $null
}
function Test-AllowedRoute([string]$key,$value,$routes) {
 if($key -cnotin @('ANTHROPIC_API_KEY','CLAUDE_CODE_OAUTH_TOKEN')){return $false}
 foreach($route in @($routes)){if($route -and $route['Key'] -ceq $key -and [string]$route['Value'] -ceq [string]$value){return $true}}
 return $false
}
function Assert-RouteOwnership($settings,$routes) {
 if($settings['env']){
  foreach($key in $settings['env'].Keys){
   if($key -match '^(ANTHROPIC_|CLAUDE_CONFIG_DIR|CLAUDE_CODE_OAUTH_|CLAUDE_CODE_USE_)' -and -not(Test-AllowedRoute $key $settings['env'][$key] $routes)){throw 'Claude settings.env baska bir kimlik dogrulama ayari iceriyor; degistirilmedi.'}
  }
 }
}
function Set-ManagedRoute($route,$allowedRoutes) {
 $settings=Read-Json $settingsPath
 $old=Get-ManagedRoute
 $allowed=@($old)+@($allowedRoutes)
 Assert-RouteOwnership $settings $allowed
 if(-not $settings.ContainsKey('env')){$settings['env']=$json.DeserializeObject('{}')}
 foreach($key in @($settings['env'].Keys)){
  if(Test-AllowedRoute $key $settings['env'][$key] $allowed){[void]$settings['env'].Remove($key)}
 }
 if($route){$settings['env'][$route['Key']]=$route['Value']}
 # Avoid creating/modifying user settings when no token route exists.
 if($route -or $old -or @($allowedRoutes|Where-Object {$_}).Count){
  Write-Json $settingsPath $settings
  if($route){Write-Secret $routePath $route}else{if(Test-Path -LiteralPath $routePath){[IO.File]::Delete($routePath)}}
  if($route){
   $before=Get-RouteStamp;$written=Read-Json $settingsPath;$after=Get-RouteStamp
   $verified=$before -eq $after -and $written['env'] -and $written['env'].ContainsKey($route['Key']) -and [string]$written['env'][$route['Key']] -ceq [string]$route['Value']
   $script:index['ActiveRoute']=@{Identity=$(if($verified){$route['Identity']}else{''});SettingsStamp=$(if($verified){$after}else{'uncertain'})}
  }else{$script:index['ActiveRoute']=$null}
  Write-Json $indexPath $index
 }
}
function Assert-TokenSnapshot($state) {
 $kind=[string]$state['AuthKind'];$key=Get-RouteKey $kind
 $token=[string]$state['Token']
 if([string]::IsNullOrWhiteSpace($token) -or $token.Length -gt 16384 -or $token -match '\s'){throw 'Token bos, cok uzun veya bosluk iceriyor.'}
 if($kind -eq 'ApiKey'){
  if($token -notmatch '^sk-ant-api[0-9]{2}-[A-Za-z0-9_-]+$'){throw 'Claude API anahtari bicimi bekleniyor.'}
 }elseif($token -notmatch '^sk-ant-oat[0-9]{2}-[A-Za-z0-9_-]+$'){throw 'Claude OAuth access/setup-token bicimi bekleniyor; refresh token veya API anahtari kullanmayin.'}
 if(-not $state['Identity'] -or [string]$state['Identity'] -notlike 'token-*'){throw 'Token kayit kimligi gecersiz.'}
}
function New-TokenReadRequest([string]$url) {return [Net.HttpWebRequest]::Create($url)}
function Invoke-TokenReadCheck([string]$kind,[string]$token,$cancelContext=$null) {
 if($kind -eq 'SetupToken'){return @{Status='unverified'}}
 [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
 $url=if($kind -eq 'ApiKey'){'https://api.anthropic.com/v1/models?limit=1'}else{'https://api.anthropic.com/api/oauth/profile'}
 $request=New-TokenReadRequest $url;$request.Method='GET';$request.AllowAutoRedirect=$false;$request.Timeout=10000;$request.ReadWriteTimeout=1000;$request.UserAgent='ClaudeAccountSwitcher/1.7';$request.ContentType='application/json'
 if($kind -eq 'ApiKey'){$request.Headers['x-api-key']=$token;$request.Headers['anthropic-version']='2023-06-01'}else{$request.Headers['Authorization']='Bearer '+$token}
 $response=$null;$reader=$null
 $deadline=[DateTime]::UtcNow.AddSeconds(10)
 try{
  if($cancelContext){$cancelContext['Request']=$request;if($cancelContext['Cancelled']){$request.Abort();throw 'cancelled'}}
  $response=$request.GetResponse()
  if([int]$response.StatusCode -ne 200){throw 'unexpected'}
  $reader=[IO.StreamReader]::new($response.GetResponseStream());$buffer=[char[]]::new(131073);$length=0
  while($length -lt $buffer.Length){if([DateTime]::UtcNow -gt $deadline){$request.Abort();throw 'timeout'};$read=$reader.Read($buffer,$length,$buffer.Length-$length);if(-not $read){break};$length+=$read}
  if($length -ge $buffer.Length){throw 'oversized'}
  $body=[string]::new($buffer,0,$length)
  $data=$json.DeserializeObject($body)
  if($kind -eq 'ApiKey'){
   if(-not $data.ContainsKey('data') -or $data['data'] -isnot [Collections.IList]){throw 'shape'}
   return @{Status='validated'}
  }
  $uuid=[string]$data['account']['uuid']
  $parsed=[guid]::Empty
  if(-not [guid]::TryParse($uuid,[ref]$parsed)){throw 'profile'}
  return @{Status='validated';AccountUuid=$uuid}
 }catch [Net.WebException]{
  $status=if($_.Exception.Response){[int]$_.Exception.Response.StatusCode}else{0}
  if($_.Exception.Response){$_.Exception.Response.Close()}
  if($status -in @(401,403)){throw 'Token reddedildi veya profil yetkisi yok. Token kaydedilmedi.'}
  throw 'Sunucu kontrolu tamamlanamadi. Token kaydedilmedi; sonra tekrar deneyin veya kontrolu kapatin.'
 }catch{throw 'Sunucu yaniti dogrulanamadi. Token kaydedilmedi.'}
 finally{if($reader){$reader.Dispose()};if($response){$response.Close()};if($cancelContext){$cancelContext['Request']=$null};$token=$null;$body=$null;$data=$null;$buffer=$null}
}
function Save-TokenAccount([string]$kind,[string]$token,[string]$label,[bool]$check,$validation=$null) {
 if([string]::IsNullOrWhiteSpace($label)){throw 'Hesap adi bos olamaz.'}
 $state=@{AuthKind=$kind;Token=$token;Identity='token-'+[guid]::NewGuid().ToString('N');Validation='unverified'}
 Assert-TokenSnapshot $state
 if($check){$validation=Invoke-TokenReadCheck $kind $token}
 if($validation){$state['Validation']=$validation.Status;if($validation.AccountUuid){$state['VerifiedAccountUuid']=$validation.AccountUuid}}
 $entry=@{Id=[guid]::NewGuid().ToString('N');Identity=$state.Identity;Name=$label;AuthKind=$kind;Validation=$state.Validation}
 if($state.VerifiedAccountUuid){$entry['VerifiedAccountUuid']=$state.VerifiedAccountUuid}
 Write-Secret (Join-Path $store ($entry.Id+'.bin')) $state
 $index['Accounts']=@($index['Accounts'])+@($entry);Write-Json $indexPath $index
}
function Invoke-TokenImport([string]$kind,[string]$token,[string]$label,[bool]$check,$validation=$null) {
 $lock=[Threading.Mutex]::new($false,('Local\ClaudeAccountSwitcher-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value));$held=$false
 try{
  $held=$lock.WaitOne(0);if(-not $held){throw 'Baska bir hesap islemi devam ediyor.'}
  Initialize-AccountCore;Assert-Environment
  if(Test-Path -LiteralPath $journalPath){throw 'Yarim kalan hesap islemi var; once hesap secimini tamamlayin.'}
  Save-TokenAccount $kind $token $label $check $validation
 }finally{if($held){$lock.ReleaseMutex()};$lock.Dispose();$token=$null}
}
function Save-CurrentToken([string]$label) {
 $route=Get-ActiveManagedRoute
 if(-not $route){throw 'Token kaydi mevcut ama etkin settings.env ile eslesmiyor; kaydedilmedi.'}
 Assert-RouteOwnership (Read-Json $settingsPath) @($route)
 foreach($entry in @($index['Accounts'])){
  if($entry['Identity'] -eq $route['Identity']){
   $snapshot=Read-Secret (Join-Path $store ($entry['Id']+'.bin'));Assert-TokenSnapshot $snapshot
   if($snapshot['Token'] -cne $route['Value']){throw 'Aktif token kaydi degisti; kaydedilmedi.'}
   $entry['Name']=$label;Write-Json $indexPath $index;return
  }
 }
 throw 'Aktif token kaydi bulunamadi.'
}
