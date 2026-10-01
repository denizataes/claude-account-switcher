function Initialize-AccountCore {
 if ($PSVersionTable.PSEdition -eq 'Core') { throw 'Windows PowerShell 5.1 gerekli.' }
 if(-not $script:json){
  Add-Type -AssemblyName System.Web.Extensions
  Add-Type -AssemblyName System.Security
  $script:json=New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $script:json.MaxJsonLength=67108864
 }
 $script:store=Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher\accounts'
 $script:indexPath=Join-Path $store 'index.json'
 $script:journalPath=Join-Path $store 'pending.bin'
 $script:credentialsPath=Join-Path $env:USERPROFILE '.claude\.credentials.json'
 $script:configPath=Join-Path $env:USERPROFILE '.claude.json'
 $script:index=Read-Json $indexPath
 if (-not $index.ContainsKey('Accounts')) { $index['Accounts']=@() }
}
function Read-Json($path) {
  if (Test-Path -LiteralPath $path) { return $json.DeserializeObject([IO.File]::ReadAllText($path)) }
  return $json.DeserializeObject('{}')
 }
function Write-Atomic($path,[byte[]]$bytes) {
  $parent=Split-Path $path -Parent
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  $temp=Join-Path $parent ([guid]::NewGuid().ToString('N')+'.tmp')
  try {
   [IO.File]::WriteAllBytes($temp,$bytes)
   if ([IO.File]::Exists($path)) { [IO.File]::Replace($temp,$path,[System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($temp,$path) }
  } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
 }
function Write-Json($path,$value) { Write-Atomic $path ([Text.Encoding]::UTF8.GetBytes($json.Serialize($value))) }
function Write-Secret($path,$value) {
  $bytes=[Text.Encoding]::UTF8.GetBytes($json.Serialize($value))
  Write-Atomic $path ([Security.Cryptography.ProtectedData]::Protect($bytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))
 }
function Read-Secret($path) {
  $bytes=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($path),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  return $json.DeserializeObject([Text.Encoding]::UTF8.GetString($bytes))
 }
function Assert-Safe {
  foreach ($variable in @('CLAUDE_CONFIG_DIR','ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN','ANTHROPIC_PROFILE','ANTHROPIC_BASE_URL','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY')) {
   foreach ($scope in @('Process','User','Machine')) {
    if ([Environment]::GetEnvironmentVariable($variable,$scope)) { throw "Ortam ayari varsayilan hesabi gecersiz kilabilir: $variable ($scope). Once bu ayari kaldirin." }
   }
  }
  if (Get-Process -Name claude -ErrorAction SilentlyContinue) { throw 'Claude Code acik. Tum Claude oturumlarini kapatip tekrar deneyin.' }
  foreach ($path in @((Join-Path $env:USERPROFILE '.claude\settings.json'),(Join-Path $env:ProgramFiles 'ClaudeCode\managed-settings.json'))) {
   $settings=Read-Json $path
   if ($settings.ContainsKey('apiKeyHelper') -or $settings.ContainsKey('forceLoginMethod') -or $settings.ContainsKey('forceLoginOrgUUID')) { throw 'Kimlik dogrulamayi yoneten Claude ayarlari bulundu. Arac bu ayarlari degistirmez.' }
   if ($settings.ContainsKey('env')) {
    foreach ($key in $settings['env'].Keys) { if ($key -match '^(ANTHROPIC_|CLAUDE_CONFIG_DIR|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_)') { throw 'Claude settings.env kimlik dogrulamayi yonetiyor.' } }
   }
  }
 }
function Get-State {
  $credentials=Read-Json $credentialsPath
  $config=Read-Json $configPath
  return @{ CredentialPresent=$credentials.ContainsKey('claudeAiOauth'); Credential=$credentials['claudeAiOauth']; AccountPresent=$config.ContainsKey('oauthAccount'); Account=$config['oauthAccount'] }
 }
function Assert-Account($state) {
  if (-not $state.CredentialPresent -or -not $state.AccountPresent -or -not $state.Credential['accessToken'] -or -not $state.Credential['refreshToken'] -or -not $state.Account['accountUuid']) { throw 'Desteklenen claude.ai abonelik oturumu bulunamadi. Once normal Claude girisini tamamlayin.' }
 }
function Merge-State($state) {
  $credentials=Read-Json $credentialsPath
  $config=Read-Json $configPath
  if ($state.CredentialPresent) { $credentials['claudeAiOauth']=$state.Credential } else { [void]$credentials.Remove('claudeAiOauth') }
  if ($state.AccountPresent) { $config['oauthAccount']=$state.Account } else { [void]$config.Remove('oauthAccount') }
  Write-Json $credentialsPath $credentials
  Write-Json $configPath $config
  $check=Get-State
  if ($json.Serialize($check.Credential) -ne $json.Serialize($state.Credential) -or $json.Serialize($check.Account) -ne $json.Serialize($state.Account)) { throw 'Yazilan oturum dogrulanamadi.' }
 }
function Restore-Pending {
  if (Test-Path -LiteralPath $journalPath) { Merge-State (Read-Secret $journalPath); [IO.File]::Delete($journalPath); Write-Host 'Yarim kalan islemden onceki oturum geri yuklendi.' }
 }
function Save-Outgoing {
  $current=Get-State
  if ($current.AccountPresent -and $current.CredentialPresent) {
   foreach ($entry in $index['Accounts']) {
    if ($entry['Identity'] -eq $current.Account['accountUuid']) { Assert-Account $current; Write-Secret (Join-Path $store ($entry['Id']+'.bin')) $current; break }
   }
  }
 }
function Save-Account($state,[string]$label) {
  Assert-Account $state
  if ([string]::IsNullOrWhiteSpace($label)) { throw 'Hesap adi bos olamaz.' }
  $entry=$null
  foreach ($candidate in $index['Accounts']) { if ($candidate['Identity'] -eq $state.Account['accountUuid']) { $entry=$candidate; break } }
  if (-not $entry) {
   $entry=@{ Id=[guid]::NewGuid().ToString('N'); Identity=$state.Account['accountUuid']; Name=$label }
   $index['Accounts']=@($index['Accounts'])+@($entry)
  }
  $entry['Name']=$label
  Write-Secret (Join-Path $store ($entry['Id']+'.bin')) $state
  Write-Json $indexPath $index
 }
function Switch-Account([int]$number) {
  Assert-Safe
  Restore-Pending
  $entries=@($index['Accounts'])
  if ($number -lt 1 -or $number -gt $entries.Count) { throw 'Gecersiz hesap numarasi.' }
  Save-Outgoing
  $target=Read-Secret (Join-Path $store ($entries[$number-1]['Id']+'.bin'))
  Assert-Account $target
  $previous=Get-State
  Write-Secret $journalPath $previous
  try { Merge-State $target; [IO.File]::Delete($journalPath) }
  catch { Merge-State $previous; [IO.File]::Delete($journalPath); throw }
  Write-Host ('Varsayilan hesap: '+$entries[$number-1]['Name']) -ForegroundColor Green
  Write-Host 'Artik herhangi bir klasorde claude yazabilirsiniz. Claude icinde /status ile dogrulayin.'
 }
function Add-Account([string]$label) {
  if ([string]::IsNullOrWhiteSpace($label)) { throw 'Hesap adi bos olamaz.' }
  Assert-Safe
  Restore-Pending
  Save-Outgoing
  $previous=Get-State
  Write-Secret $journalPath $previous
  try {
   $command=Get-Command claude -CommandType Application -ErrorAction Stop | Select-Object -First 1
   & $command.Source auth login --claudeai
   if ($LASTEXITCODE -ne 0) { throw 'Claude girisi tamamlanamadi.' }
   Assert-Safe
   $new=Get-State
   Assert-Account $new
   Save-Account $new $label
   Write-Host 'Hesap kaydedildi. Onceki varsayilan hesap geri yukleniyor.'
  } finally { Merge-State $previous; [IO.File]::Delete($journalPath) }
 }
function Assert-Environment {
  foreach ($variable in @('CLAUDE_CONFIG_DIR','ANTHROPIC_API_KEY','ANTHROPIC_AUTH_TOKEN','CLAUDE_CODE_OAUTH_TOKEN','ANTHROPIC_PROFILE','ANTHROPIC_BASE_URL','CLAUDE_CODE_USE_BEDROCK','CLAUDE_CODE_USE_VERTEX','CLAUDE_CODE_USE_FOUNDRY')) {
   foreach ($scope in @('Process','User','Machine')) {
    if ([Environment]::GetEnvironmentVariable($variable,$scope)) { throw "Ortam ayari varsayilan hesabi gecersiz kilabilir: $variable ($scope). Once bu ayari kaldirin." }
   }
  }

  foreach ($path in @((Join-Path $env:USERPROFILE '.claude\settings.json'),(Join-Path $env:ProgramFiles 'ClaudeCode\managed-settings.json'))) {
   $settings=Read-Json $path
   if ($settings.ContainsKey('apiKeyHelper') -or $settings.ContainsKey('forceLoginMethod') -or $settings.ContainsKey('forceLoginOrgUUID')) { throw 'Kimlik dogrulamayi yoneten Claude ayarlari bulundu. Arac bu ayarlari degistirmez.' }
   if ($settings.ContainsKey('env')) {
    foreach ($key in $settings['env'].Keys) { if ($key -match '^(ANTHROPIC_|CLAUDE_CONFIG_DIR|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_)') { throw 'Claude settings.env kimlik dogrulamayi yonetiyor.' } }
   }
  }
 }
