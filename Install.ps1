param([switch]$NoLaunch,[string]$InstallDirectory,[string]$StartupDirectory)
$ErrorActionPreference='Stop'
try {
 if (-not $InstallDirectory) {$InstallDirectory=Join-Path $env:LOCALAPPDATA 'ClaudeAccountSwitcher\app'}
 if (-not $StartupDirectory) {$StartupDirectory=[Environment]::GetFolderPath('Startup')}
 New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
 foreach ($name in @('AccountCore.ps1','TraySupport.ps1','TrayUI.ps1','TrayRuntime.ps1','VisualControls.dll','UsageCore.ps1','Usage-Collector.ps1','Claude-Hesap.ps1','Claude-Hesap.bat','Claude-Tray.ps1','Claude-Tray.vbs','Claude-Switch.ico','README.md','LICENSE')) {
  $source=Join-Path $PSScriptRoot $name
  $destination=Join-Path $InstallDirectory $name
  if ([IO.Path]::GetFullPath($source) -ine [IO.Path]::GetFullPath($destination)) {Copy-Item -LiteralPath $source -Destination $destination -Force}
 }
 New-Item -ItemType Directory -Path $StartupDirectory -Force | Out-Null
 $shell=New-Object -ComObject WScript.Shell
 $shortcut=$shell.CreateShortcut((Join-Path $StartupDirectory 'Claude Hesap Secici.lnk'))
 $shortcut.TargetPath=Join-Path $env:WINDIR 'System32\wscript.exe'
 $shortcut.Arguments='"'+(Join-Path $InstallDirectory 'Claude-Tray.vbs')+'"'
 $shortcut.WorkingDirectory=$InstallDirectory
 $shortcut.IconLocation=(Join-Path $InstallDirectory 'Claude-Switch.ico')+',0'
 $shortcut.Save()
 if (-not $NoLaunch) {Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"'+(Join-Path $InstallDirectory 'Claude-Tray.vbs')+'"') -WindowStyle Hidden}
 Write-Host 'Kurulum tamamlandi. Windows acilisinda otomatik baslar. Simge gizliyse bildirim alanindaki yukari oka bakin.'
 exit 0
} catch {Write-Host ('Hata: '+$_.Exception.Message) -ForegroundColor Red;exit 1}

