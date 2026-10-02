$ErrorActionPreference='Stop'
$testFolder=Join-Path (Join-Path $PSScriptRoot 'dist') ('ClaudeStandaloneTest-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Split-Path $testFolder) -Force|Out-Null
New-Item -ItemType Directory -Path $testFolder|Out-Null
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'previews') -Force|Out-Null
$testExe=Join-Path $testFolder 'Setup.exe'
try{
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Claude-Hesap-Setup.exe') -Destination $testExe
 $process=Start-Process -FilePath $testExe -ArgumentList '/test' -PassThru;$process.WaitForExit()
 if($process.ExitCode -ne 0){throw 'Standalone self-test failed'}
 $process=Start-Process -FilePath $testExe -ArgumentList '/preview',(Join-Path $PSScriptRoot 'previews\setup.png') -PassThru;$process.WaitForExit()
 if($process.ExitCode -ne 0){throw 'Standalone warm preview failed'}
 if(Test-Path -LiteralPath (Join-Path $testFolder 'VisualControls.dll')){throw 'Testfolder unexpectedly contains DLL'}
 Write-Host 'PASS: Setup.exe alone installs/test-renders without companion DLL; isolated data preserved.'
}finally{
 if([IO.File]::Exists($testExe)){[IO.File]::Delete($testExe)}
 if([IO.Directory]::Exists($testFolder)){[IO.Directory]::Delete($testFolder)}
}
