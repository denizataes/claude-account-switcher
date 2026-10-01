$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TraySupport.ps1')
$fakePath='C:\FakeClaude\claude.exe'
$fake=[pscustomobject]@{Id=42;ProcessName='claude';Path=$fakePath;StartTime=[datetime]'2026-01-01'}
if (-not (Test-ApprovedClaudeProcess $fake @($fakePath))) {throw 'Approved path rejected'}
if (Test-ApprovedClaudeProcess $fake @('C:\Other\claude.exe')) {throw 'Unrelated path allowed'}
if (Test-ApprovedClaudeProcess ([pscustomobject]@{ProcessName='node';Path='C:\FakeClaude\node.exe'}) @('C:\FakeClaude\node.exe')) {throw 'Unrelated executable allowed'}
$script:stopped=$false;$script:stopCount=0;$script:identityMismatch=$false
function Get-ClaudeProcessList {return $fake}
function Get-Process {
 [CmdletBinding()]param([string[]]$Name,[int]$Id)
 if ($script:stopped) {return $null}
 if ($script:identityMismatch -and $Id) {return [pscustomobject]@{Id=42;ProcessName='claude';Path='C:\Other\claude.exe';StartTime=$fake.StartTime}}
 return $fake
}
function Stop-Process {[CmdletBinding()]param([int]$Id,[switch]$Force) if ($Id -ne 42) {throw 'Wrong process id'};$script:stopCount++;$script:stopped=$true}
if (Close-ClaudeWithConsent {param($count) $false}) {throw 'No consent should cancel'}
if ($script:stopCount) {throw 'Stopped without consent'}
if (-not (Close-ClaudeWithConsent {param($count) $count -eq 1})) {throw 'Yes consent failed'}
if ($script:stopCount -ne 1) {throw 'Expected single approved process stop'}
$script:stopped=$false;$script:identityMismatch=$true
$rejected=$false
try {[void](Close-ClaudeWithConsent {$true})} catch {$rejected=$true}
if (-not $rejected -or $script:stopCount -ne 1) {throw 'Changed identity was not rejected'}
Add-Type -AssemblyName System.Web.Extensions
function Initialize-AccountCore {$script:json=New-Object System.Web.Script.Serialization.JavaScriptSerializer;$script:journalPath=Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N')+'.missing')}
function Assert-Environment {}
function Get-State {return @{CredentialPresent=$true;AccountPresent=$true;Credential=@{accessToken='fake';refreshToken='fake'};Account=@{accountUuid='fake'}}}
function Assert-Account($state) {}
$script:imported=0
function Save-Account($state,$label) {$script:imported++}
$beforeStops=$script:stopCount
if(-not (Invoke-AccountOperation 'Import' 0 'fake label' {throw 'Import requested consent'})){throw 'Import failed'}
if($script:imported -ne 1 -or $script:stopCount -ne $beforeStops){throw 'Import stopped process or did not save'}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeTrayTest-'+[guid]::NewGuid().ToString('N'))
try {
 $install=Join-Path $temp 'app';$startup=Join-Path $temp 'startup'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Install.ps1') -NoLaunch -InstallDirectory $install -StartupDirectory $startup
 if ($LASTEXITCODE -ne 0) {throw 'Isolated install failed'}
 $shell=New-Object -ComObject WScript.Shell
 $shortcut=$shell.CreateShortcut((Join-Path $startup 'Claude Hesap Secici.lnk'))
 if ($shortcut.Arguments -ne ('"'+(Join-Path $install 'Claude-Tray.vbs')+'"') -or $shortcut.TargetPath -ine (Join-Path $env:WINDIR 'System32\wscript.exe')) {throw 'Startup shortcut wrong'}
 if (-not (Test-Path -LiteralPath (Join-Path $install 'AccountCore.ps1')) -or (Test-Path -LiteralPath (Join-Path $install 'accounts'))) {throw 'Installed assets/state boundary wrong'}
 Add-Type -AssemblyName System.Drawing
 $icon=New-Object Drawing.Icon((Join-Path $install 'Claude-Switch.ico'))
 $icon.Dispose()
 foreach ($file in @('AccountCore.ps1','TraySupport.ps1','TrayUI.ps1','UsageCore.ps1','Usage-Collector.ps1','Claude-Tray.ps1','Claude-Hesap.ps1','Install.ps1')) {
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $file),[ref]$tokens,[ref]$errors)
  if ($errors.Count) {throw "Parse failure: $file"}
 }
 Write-Host 'PASS: consent yes/no, approved executable/path, changed process identity rejection, isolated install/startup shortcut, icon load, script parsing.' -ForegroundColor Green
} finally {
 $resolved=[IO.Path]::GetFullPath($temp);$root=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if ($resolved.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'ClaudeTrayTest-*') {Remove-Item -LiteralPath $resolved -Recurse -Force}
}
