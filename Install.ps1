param([switch]$NoLaunch,[switch]$NoStartup,[switch]$DesktopShortcut)
$ErrorActionPreference='Stop'
$setup=Join-Path $PSScriptRoot 'Claude-Hesap-Setup.exe'
if(-not(Test-Path -LiteralPath $setup)){throw 'Setup.exe bulunamadi. Release paketini indirin veya Build-Setup.ps1 ile derleyin.'}
$arguments=@('/install','/quiet')
if($NoLaunch){$arguments+='/no-launch'}
if($NoStartup){$arguments+='/no-startup'}
if($DesktopShortcut){$arguments+='/desktop'}
$process=Start-Process -FilePath $setup -ArgumentList $arguments -WindowStyle Hidden -PassThru
try{$process.WaitForExit();$code=$process.ExitCode}finally{$process.Dispose()}
if($code -eq 2){Write-Warning 'Kurulum tamamlandi, ancak uygulama baslangici dogrulanamadi.'}elseif($code -ne 0){throw 'Kurulum basarisiz. Ayrintilar icin setup.log dosyasini kontrol edin.'}
exit $code
