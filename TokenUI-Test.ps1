$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TrayUI.ps1')
. (Join-Path $PSScriptRoot 'TokenCore.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeTokenUITest-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
try{
 Copy-Item (Join-Path $PSScriptRoot 'TokenUI.ps1') (Join-Path $temp 'TokenUI.ps1')
 [IO.File]::WriteAllText((Join-Path $temp 'AccountCore.ps1'),'function Initialize-AccountCore {}; function Invoke-TokenReadCheck { param($kind,$token,$cancel); Start-Sleep -Seconds 10; return @{Status="validated"} }')
 . (Join-Path $temp 'TokenUI.ps1')
 $script:step=0;$script:masked=$false;$script:began=$false
 $driver=[Windows.Forms.Timer]::new();$driver.Interval=150
 $driver.Add_Tick({
  $form=@([Windows.Forms.Application]::OpenForms|Where-Object {$_.Text -eq 'Token ile hesap ekle'})[0]
  if(-not $form){return}
  if($script:step -eq 0){
   $name=@($form.Controls|Where-Object {$_.AccessibleName -eq 'Hesap adı'})[0];$name.Text='Fixture'
   $kind=@($form.Controls|Where-Object {$_.AccessibleName -eq 'Token türü'})[0];$kind.SelectedIndex=2
   $token=@($form.Controls|Where-Object {$_.AccessibleName -eq 'Gizli token'})[0];$script:masked=$token.UseSystemPasswordChar;$token.Text='sk-ant-api03-fixture'
   $ok=@($form.Controls|Where-Object {$_.Text -eq 'Kaydet'})[0];$ok.PerformClick();$script:began=-not $ok.Enabled;$script:step=1
  }else{$form.DialogResult='Cancel';$driver.Stop()}
 })
 $watch=[Diagnostics.Stopwatch]::StartNew();$driver.Start();$result=Show-TokenDialog;$watch.Stop();$driver.Dispose()
 if($result -or -not $script:masked -or -not $script:began -or $watch.Elapsed.TotalSeconds -gt 2){throw 'Masked asynchronous validation cancel failed or blocked UI'}
 $deadline=[DateTime]::UtcNow.AddSeconds(3)
 while($script:tokenCleanups -and [DateTime]::UtcNow -lt $deadline){Complete-TokenCleanup;Start-Sleep -Milliseconds 50}
 if($script:tokenCleanups){throw 'Cancelled validator runspace not disposed'}
 Write-Host ('PASS: masked input, async mock validation, cancellation {0:N0}ms with no saved result; runspace disposed. No real token/network.' -f $watch.Elapsed.TotalMilliseconds)
}finally{Remove-Item -LiteralPath $temp -Force -Recurse;Dispose-UIResources}
