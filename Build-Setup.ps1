$ErrorActionPreference='Stop'
$root=$PSScriptRoot
& (Join-Path $root 'Build-Visuals.ps1')
$files=@('AccountCore.ps1','TraySupport.ps1','TrayUI.ps1','TrayRuntime.ps1','VisualControls.dll','UsageCore.ps1','Usage-Collector.ps1','Claude-Hesap.ps1','Claude-Hesap.bat','Claude-Tray.ps1','Claude-Tray.vbs','Claude-Switch.ico','README.md','LICENSE') | ForEach-Object {Join-Path $root $_}
$payload=Join-Path $root 'AppPayload.zip'
Compress-Archive -LiteralPath $files -DestinationPath $payload -Force
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$manifestArgument='/win32manifest:'+(Join-Path $root 'Setup.manifest')
& $compiler $manifestArgument /nologo /target:winexe /platform:anycpu /optimize+ ("/out:"+(Join-Path $root 'Claude-Hesap-Setup.exe')) ("/win32icon:"+(Join-Path $root 'Claude-Switch.ico')) ("/resource:"+$payload+',AppPayload.zip') ("/resource:"+(Join-Path $root 'Claude-Switch.ico')+',AppIcon.ico') ("/resource:"+(Join-Path $root 'Icon-Preview.png')+',AppLogo.png') /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll /reference:System.Management.dll /reference:Microsoft.CSharp.dll /reference:System.Core.dll (Join-Path $root 'Setup.cs') (Join-Path $root 'VisualControls.cs')
if($LASTEXITCODE -ne 0){throw 'Setup derlenemedi.'}


