$ErrorActionPreference='Stop'
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:library /optimize+ ("/out:"+(Join-Path $PSScriptRoot 'VisualControls.dll')) /reference:System.Windows.Forms.dll /reference:System.Drawing.dll (Join-Path $PSScriptRoot 'VisualControls.cs')
if($LASTEXITCODE -ne 0){throw 'Visual controls compile failed.'}
