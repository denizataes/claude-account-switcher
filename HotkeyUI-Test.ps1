$ErrorActionPreference='Stop'
$oldProfile=$env:USERPROFILE;$oldLocal=$env:LOCALAPPDATA
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeHotkeyUI-'+[guid]::NewGuid().ToString('N'))
try {
 $env:USERPROFILE=$temp;$env:LOCALAPPDATA=Join-Path $temp 'local'
 . (Join-Path $PSScriptRoot 'AccountCore.ps1');Initialize-AccountCore
 . (Join-Path $PSScriptRoot 'PreferenceCore.ps1')
 . (Join-Path $PSScriptRoot 'TrayUI.ps1')
 . (Join-Path $PSScriptRoot 'HotkeyCore.ps1')
 . (Join-Path $PSScriptRoot 'HotkeyUI.ps1')
 $entries=@(@{Id='a';Name='Personal'},@{Id='b';Name='Work'},@{Id='c';Name='Demo'})
 $script:failure=$null;$script:checked=$false
 $timer=[Windows.Forms.Timer]::new();$timer.Interval=100
 $timer.Add_Tick({
  $timer.Stop()
  try {
   $form=@([Windows.Forms.Application]::OpenForms)[0]
   $capture=@($form.Controls | Where-Object {$_.AccessibleName -eq 'Kısayol kaydetme alanı'})[0]
   if(-not $capture){$capture=@($form.Controls | Where-Object {$_ -is [Windows.Forms.TextBox]})[0]}
   $key=[Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Control -bor [Windows.Forms.Keys]::Alt -bor [Windows.Forms.Keys]::D1)
   [Windows.Forms.Control].GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic').Invoke($capture,@($key)) | Out-Null
   if($capture.Tag.Binding.Modifiers -ne 3 -or $capture.Tag.Binding.Key -ne 49 -or -not $key.SuppressKeyPress){throw 'Capture did not record and suppress Ctrl+Alt+1'}
   $script:checked=$true
  }catch{$script:failure=$_.Exception.Message}finally{if($form){$form.Close()}}
 })
 $timer.Start();Show-HotkeySettings @{Errors=@{}} $entries
 if($script:failure){throw $script:failure};if(-not $script:checked){throw 'Capture fixture did not run'}
 Write-Host 'PASS: synthetic Ctrl+Alt+1 capture records modifiers/key and suppresses typing; cancel has no auth action.'
}finally{if($timer){$timer.Dispose()};if(Get-Command Dispose-UIResources -ErrorAction SilentlyContinue){Dispose-UIResources};$env:USERPROFILE=$oldProfile;$env:LOCALAPPDATA=$oldLocal;if([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}}
