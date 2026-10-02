$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TrayUI.ps1')
$form=New-Object Windows.Forms.Form;$form.BackColor=$Palette.Paper
$panel=New-Object Windows.Forms.Panel;$panel.BackColor=[Drawing.Color]::Transparent;$form.Controls.Add($panel)
$button=New-UIButton 'Test' 0 0 160 40 $true;$panel.Controls.Add($button)
if([WarmRegions]::Background($panel).ToArgb() -ne $Palette.Paper.ToArgb()){throw 'Transparent ancestor background failed'}
if($button -is [Windows.Forms.Button]){throw 'Native themed button still used'}
$script:clicks=0;$button.Add_Click({$script:clicks++});$button.PerformClick();if($script:clicks -ne 1){throw 'Click failed'}
$button.Enabled=$false;$button.PerformClick();if($script:clicks -ne 1){throw 'Disabled click fired'};$button.Enabled=$true
$button.DialogResult='OK';$form.AcceptButton=$button;$button.PerformClick();if($form.DialogResult -ne 'OK'){throw 'Dialog result failed'}
$method=[WarmRoundedButton].GetMethod('ProcessDialogKey',[Reflection.BindingFlags]'Instance,NonPublic');$method.Invoke($button,[object[]]@([Windows.Forms.Keys]::Enter))|Out-Null;if($script:clicks -ne 3){throw 'Enter click failed'}
$keyDown=[WarmRoundedButton].GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic');$keyUp=[WarmRoundedButton].GetMethod('OnKeyUp',[Reflection.BindingFlags]'Instance,NonPublic');$lostFocus=[WarmRoundedButton].GetMethod('OnLostFocus',[Reflection.BindingFlags]'Instance,NonPublic')
$key=New-Object Windows.Forms.KeyEventArgs([Windows.Forms.Keys]::Space)
$keyUp.Invoke($button,[object[]]@($key.PSObject.BaseObject))|Out-Null;if($script:clicks -ne 3){throw 'Unmatched Space release clicked'}
$keyDown.Invoke($button,[object[]]@($key.PSObject.BaseObject))|Out-Null;$lostFocus.Invoke($button,[object[]]@([EventArgs]::Empty))|Out-Null;$keyUp.Invoke($button,[object[]]@($key.PSObject.BaseObject))|Out-Null;if($script:clicks -ne 3){throw 'Space release after focus loss clicked'}
$form.Dispose();Dispose-UIResources
'PASS: opaque ancestor color; no native Button theme; click, disabled, accept-dialog, Enter semantics.'
