$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeTokenTest-'+[guid]::NewGuid().ToString('N'))
$oldUser=$env:USERPROFILE;$oldLocal=$env:LOCALAPPDATA
try{
 $env:USERPROFILE=Join-Path $temp 'user';$env:LOCALAPPDATA=Join-Path $temp 'local'
 [IO.Directory]::CreateDirectory((Join-Path $env:USERPROFILE '.claude'))|Out-Null
 . (Join-Path $PSScriptRoot 'AccountCore.ps1');Initialize-AccountCore
 function Get-Process {param($Name)return @()}
 $credentials=$json.DeserializeObject('{"claudeAiOauth":{"accessToken":"fake-browser","refreshToken":"fake-refresh"},"mcpOAuth":{"keep":1}}')
 $config=$json.DeserializeObject('{"oauthAccount":{"accountUuid":"browser"},"projects":{"C:/A":1,"c:/a":2}}')
 Write-Json $credentialsPath $credentials;Write-Json $configPath $config
 Write-Json $settingsPath ($json.DeserializeObject('{"env":{"UNRELATED":"keep","case":"one","Case":"two"},"theme":"keep"}'))
 Save-Account (Get-State) 'Browser'
 $oldHost=$env:CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST
 try{$env:CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST='1';$rejected=$false;try{Assert-Environment}catch{$rejected=$true};if(-not $rejected){throw 'Host-managed settings override accepted'}}finally{$env:CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST=$oldHost}
 $hash=(Get-FileHash $credentialsPath).Hash
 foreach($kind in @('SetupToken','OAuthAccess','ApiKey')){
  $token=if($kind -eq 'ApiKey'){'sk-ant-api03-fixture'}else{'sk-ant-oat01-fixture'}
  Save-TokenAccount $kind $token $kind $false
 }
 if((Get-FileHash $credentialsPath).Hash -ne $hash -or (Get-ManagedRoute)){throw 'Import modified active account'}
 foreach($kind in @('SetupToken','OAuthAccess')){try{Assert-TokenSnapshot @{AuthKind=$kind;Token='sk-ant-api03-wrong';Identity='token-fixture'};throw 'Wrong type accepted'}catch{if($_.Exception.Message -eq 'Wrong type accepted'){throw}}}
 Switch-Account 2
 $settings=Read-Json $settingsPath
 if($settings['env']['CLAUDE_CODE_OAUTH_TOKEN'] -cne 'sk-ant-oat01-fixture' -or (Get-State).Account.accountUuid -ne 'browser'){throw 'Native route/backing OAuth mismatch'}
 if($settings['env']['case'] -ne 'one' -or $settings['env']['Case'] -ne 'two' -or $settings['theme'] -ne 'keep'){throw 'Unrelated/case-sensitive settings lost'}
 Save-CurrentToken 'Renamed';if($index['Accounts'][1].Name -ne 'Renamed' -or $index['Accounts'].Count -ne 4){throw 'Current token saved backing browser instead'}
 Switch-Account 4
 $settings=Read-Json $settingsPath
 if($settings['env']['ANTHROPIC_API_KEY'] -cne 'sk-ant-api03-fixture' -or $settings['env'].ContainsKey('CLAUDE_CODE_OAUTH_TOKEN')){throw 'API route switch not exclusive'}
 $fake=Join-Path $temp 'fake-claude.cmd';[IO.File]::WriteAllText($fake,"@echo off`r`nexit /b 7`r`n")
 function Get-Command {param($Name,$CommandType)[pscustomobject]@{Source=$fake}}
 try{Add-Account 'Failed browser';throw 'Failed login accepted'}catch{if($_.Exception.Message -eq 'Failed login accepted'){throw}}
 if((Get-ActiveManagedRoute).Key -ne 'ANTHROPIC_API_KEY'){throw 'Failed browser login did not restore selected token'}
 $restore=Get-State;$restore['AllowedRoutes']=@($restore.ManagedRoute);Write-Secret $journalPath $restore
 [IO.File]::Delete($routePath)
 Assert-Environment;Restore-Pending
 if((Get-ActiveManagedRoute).Key -ne 'ANTHROPIC_API_KEY'){throw 'Browser Add restore-before-ledger crash not recovered'}
 $writeOriginal=${function:Write-Json};$script:failSettings=$true
 function Write-Json($path,$value){if($script:failSettings -and $path -eq $settingsPath){$script:failSettings=$false;throw 'Injected settings failure'};& $writeOriginal $path $value}
 try{Switch-Account 1;throw 'Failure injection did not fail'}catch{if($_.Exception.Message -eq 'Failure injection did not fail'){throw}}
 if((Get-ActiveManagedRoute).Key -ne 'ANTHROPIC_API_KEY' -or (Get-State).Account.accountUuid -ne 'browser'){throw 'Failure rollback did not restore auth route/native fields'}
 Set-Item Function:\Write-Json $writeOriginal
 $secretOriginal=${function:Write-Secret}
 foreach($faultPath in @($credentialsPath,$configPath,$settingsPath,$indexPath,$routePath,$journalPath)){
  $script:injectedPath=$faultPath;$script:injected=$false
  function Write-Json($path,$value){if(-not $script:injected -and $path -eq $script:injectedPath){$script:injected=$true;throw 'Injected transaction failure'};& $writeOriginal $path $value}
  function Write-Secret($path,$value){if(-not $script:injected -and $path -eq $script:injectedPath){$script:injected=$true;throw 'Injected transaction failure'};& $secretOriginal $path $value}
  try{Switch-Account 2;throw 'Fault phase did not fail'}catch{if($_.Exception.Message -eq 'Fault phase did not fail'){throw}}
  if(-not $script:injected -or (Get-ActiveManagedRoute).Key -ne 'ANTHROPIC_API_KEY' -or (Get-State).Account.accountUuid -ne 'browser'){throw 'Transaction phase failed to preserve original route'}
 }
 Set-Item Function:\Write-Json $writeOriginal;Set-Item Function:\Write-Secret $secretOriginal
 $previous=Get-State;$target=@{Key='CLAUDE_CODE_OAUTH_TOKEN';Value='sk-ant-oat01-fixture';Identity=$index['Accounts'][1].Identity}
 $previous['AllowedRoutes']=@($previous.ManagedRoute,$target);Write-Secret $journalPath $previous
 $settings['env'].Remove('ANTHROPIC_API_KEY');$settings['env']['CLAUDE_CODE_OAUTH_TOKEN']=$target.Value;Write-Json $settingsPath $settings
 Assert-Environment;Restore-Pending
 if((Read-Json $settingsPath)['env']['ANTHROPIC_API_KEY'] -cne 'sk-ant-api03-fixture'){throw 'Partial settings-before-ledger recovery failed'}
 Switch-Account 1
 if((Read-Json $settingsPath)['env'].ContainsKey('ANTHROPIC_API_KEY') -or (Get-ManagedRoute)){throw 'Browser switch retained token route'}
 Switch-Account 2;$settings=Read-Json $settingsPath;[void]$settings['env'].Remove('CLAUDE_CODE_OAUTH_TOKEN');Write-Json $settingsPath $settings
 if((Get-State).ManagedRoute){throw 'Removed owned token still reported active'}
 try{Save-CurrentToken 'Wrong';throw 'Missing env accepted as active token'}catch{if($_.Exception.Message -eq 'Missing env accepted as active token'){throw}}
 Save-Outgoing;Switch-Account 1
 $settings=Read-Json $settingsPath;$settings['env']['ANTHROPIC_API_KEY']='sk-ant-api03-external';Write-Json $settingsPath $settings
 try{Switch-Account 2;throw 'External route overwritten'}catch{if($_.Exception.Message -eq 'External route overwritten'){throw}}
 if((Read-Json $settingsPath)['env']['ANTHROPIC_API_KEY'] -cne 'sk-ant-api03-external'){throw 'External token modified'}
 . (Join-Path $PSScriptRoot 'TrayRuntime.ps1')
 $now=1000000L
 if((Get-NextUsageCheck @(@{AuthKind='ApiKey'},@{AuthKind='SetupToken'}) @{Accounts=@{}} $now) -ne $now+300000){throw 'Unsupported token scheduled collector'}
 if((Read-Json $configPath)['projects'].Count -ne 2 -or (Read-Json $credentialsPath)['mcpOAuth']['keep'] -ne 1){throw 'Native unrelated state changed'}
 Write-Host 'PASS: 3 typed token imports, no active import writes, original browser backing, exclusive native env routes, DPAPI ownership, case preservation, token SaveCurrent, partial-journal recovery, external conflict rejection, unsupported quota scheduling. No real token/network/Claude process used.'
}finally{
 $env:USERPROFILE=$oldUser;$env:LOCALAPPDATA=$oldLocal
 if([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue}
}
