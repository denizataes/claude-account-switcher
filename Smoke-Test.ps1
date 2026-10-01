$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Web.Extensions
$json=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeSwitcherTest-'+[guid]::NewGuid().ToString('N'))
$variables=@('USERPROFILE','LOCALAPPDATA','PATH','ANTHROPIC_API_KEY','SWITCHER_FAKE_FAIL')
$original=@{}
foreach ($key in $variables) { $original[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$script=Join-Path $PSScriptRoot 'AccountCore.ps1'
function Run([string[]]$arguments,[int]$expected=0) {
 $code=0
 try {
  Assert-Safe
  Restore-Pending
  if ($arguments[0] -eq '-SaveCurrent') { Save-Account (Get-State) $arguments[2] }
  elseif ($arguments[0] -eq '-Add') { Add-Account $arguments[2] }
  elseif ($arguments[0] -eq '-Select') { Switch-Account ([int]$arguments[1]) }
 } catch { $code=1; Write-Host ('Expected/test error: '+$_.Exception.Message) }
 if ($code -ne $expected) { throw "Unexpected exit: $code expected $expected" }
}
function Write-Current([string]$id,[string]$token) {
 $credential=@{ claudeAiOauth=@{ accessToken=$token; refreshToken='fake-refresh'; expiresAt=999999 }; mcpOAuth=@{ retained='yes' } }
 $config=$json.DeserializeObject('{"projects":{"C:/A":{"keep":1},"c:/a":{"keep":2}},"unrelated":"preserved"}')
 $config['oauthAccount']=@{ accountUuid=$id; emailAddress='fake@example.invalid' }
 [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.claude\.credentials.json'),$json.Serialize($credential))
 [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.claude.json'),$json.Serialize($config))
}
function Assert-Current([string]$id,[string]$token) {
 $c=$json.DeserializeObject([IO.File]::ReadAllText((Join-Path $env:USERPROFILE '.claude\.credentials.json')))
 $s=$json.DeserializeObject([IO.File]::ReadAllText((Join-Path $env:USERPROFILE '.claude.json')))
 if ($c['claudeAiOauth']['accessToken'] -ne $token -or $s['oauthAccount']['accountUuid'] -ne $id) { throw 'Wrong restored account/token' }
 if ($c['mcpOAuth']['retained'] -ne 'yes' -or $s['projects'].Count -ne 2 -or $s['projects']['C:/A']['keep'] -ne 1 -or $s['projects']['c:/a']['keep'] -ne 2 -or $s['unrelated'] -ne 'preserved') { throw 'Unrelated credentials/config changed' }
}
try {
 New-Item -ItemType Directory -Path $temp -Force | Out-Null
 $wrapper=Join-Path $temp 'test-wrapper.ps1'
 $escaped=$script.Replace("'","''")
 $wrapperText=@'
function Get-Process {
 [CmdletBinding()]param([string[]]$Name)
 Microsoft.PowerShell.Management\Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith((Split-Path $env:USERPROFILE -Parent),[StringComparison]::OrdinalIgnoreCase) }
}
& 'SCRIPT_PATH' @args
exit $LASTEXITCODE
'@
 $wrapperText.Replace('SCRIPT_PATH',$escaped) | Set-Content -LiteralPath $wrapper -Encoding ASCII
 $env:USERPROFILE=Join-Path $temp 'user'
 $env:LOCALAPPDATA=Join-Path $temp 'local'
 $env:PATH="$temp;$($original['PATH'])"
 $json.MaxJsonLength=67108864
 Add-Type -AssemblyName System.Security
 $store=Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher\accounts'
 $indexPath=Join-Path $store 'index.json'
 $journalPath=Join-Path $store 'pending.bin'
 $credentialsPath=Join-Path $env:USERPROFILE '.claude\.credentials.json'
 $configPath=Join-Path $env:USERPROFILE '.claude.json'
 $index=$json.DeserializeObject('{"Accounts":[]}')
 $tokens=$null; $errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($script,[ref]$tokens,[ref]$errors)
 if ($errors.Count) { throw 'Production script parse error' }
 foreach ($definition in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) { Invoke-Expression $definition.Extent.Text }
 function Get-Process {
  [CmdletBinding()]param([string[]]$Name)
  Microsoft.PowerShell.Management\Get-Process -Name $Name -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) }
 }
 New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE '.claude') -Force | Out-Null
 $fake=@'
Add-Type -AssemblyName System.Web.Extensions
$j=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$cp=Join-Path $env:USERPROFILE '.claude\.credentials.json'
$sp=Join-Path $env:USERPROFILE '.claude.json'
$c=$j.DeserializeObject([IO.File]::ReadAllText($cp))
$s=$j.DeserializeObject([IO.File]::ReadAllText($sp))
$c['claudeAiOauth']=@{accessToken='fake-login';refreshToken='fake-refresh'}
$s['oauthAccount']=@{accountUuid='login-account'}
[IO.File]::WriteAllText($cp,$j.Serialize($c))
[IO.File]::WriteAllText($sp,$j.Serialize($s))
if ($env:SWITCHER_FAKE_FAIL) {exit 7}
exit 0
'@
 $fake | Set-Content -LiteralPath (Join-Path $temp 'fake.ps1') -Encoding ASCII
 @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0fake.ps1"
exit /b %errorlevel%
'@ | Set-Content -LiteralPath (Join-Path $temp 'claude.cmd') -Encoding ASCII
 foreach ($i in 1..5) { Write-Current "id-$i" "fake-$i"; Run @('-SaveCurrent','-Name',"Account $i") }
 $index=$json.DeserializeObject([IO.File]::ReadAllText((Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher\accounts\index.json')))
 if ($index['Accounts'].Count -ne 5) { throw 'Dynamic accounts failed' }
 Run @('-Select','1'); Assert-Current 'id-1' 'fake-1'
 Write-Current 'id-1' 'fake-refreshed'
 Run @('-Select','2'); Assert-Current 'id-2' 'fake-2'
 Run @('-Select','1'); Assert-Current 'id-1' 'fake-refreshed'
 Run @('-Select','1'); Assert-Current 'id-1' 'fake-refreshed'
 Write-Current 'outside-account' 'fake-external'
 Run @('-Select','2'); Assert-Current 'id-2' 'fake-2'
 Run @('-Select','1'); Assert-Current 'id-1' 'fake-refreshed'
 $env:SWITCHER_FAKE_FAIL='yes'
 Run @('-Add','-Name','Fail') 1
 Assert-Current 'id-1' 'fake-refreshed'
 $env:SWITCHER_FAKE_FAIL=$null
 Run @('-Add','-Name','Login')
 Assert-Current 'id-1' 'fake-refreshed'
 Run @('-Select','6'); Assert-Current 'login-account' 'fake-login'
 $env:ANTHROPIC_API_KEY='fake-env-key'
 Run @('-Select','1') 1
 Assert-Current 'login-account' 'fake-login'
 $env:ANTHROPIC_API_KEY=$original['ANTHROPIC_API_KEY']
 Run @('-Select','99') 1
 $exe=Join-Path $temp 'claude.exe'
 Add-Type -TypeDefinition 'public class GuardProcess { public static void Main() { System.Threading.Thread.Sleep(30000); } }' -OutputAssembly $exe -OutputType ConsoleApplication
 $guard=Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
 try { Run @('-Select','1') 1; Assert-Current 'login-account' 'fake-login' }
 finally { if (-not $guard.HasExited) { $guard.Kill(); $guard.WaitForExit() } }
 Write-Host 'PASS: 5 accounts, import/add/select, outgoing refresh, external identity, same account, failed login rollback, case-distinct projects/MCP, env/process guards.' -ForegroundColor Green
} finally {
 foreach ($key in $variables) { [Environment]::SetEnvironmentVariable($key,$original[$key],'Process') }
 $resolved=[IO.Path]::GetFullPath($temp)
 $root=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if ($resolved.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'ClaudeSwitcherTest-*') { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
