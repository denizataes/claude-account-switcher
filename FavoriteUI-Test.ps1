$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TrayUI.ps1')
$entries=@(@{Id='a';Identity='a';Name='First'},@{Id='b';Identity='b';Name='Active'},@{Id='c';Identity='c';Name='Favorite'})
$script:selected=0;$script:favoriteCalls=0
$form=New-AccountPopup $entries 'b' {param($number)$script:selected=$number} {return} {return} {return} $false {return} @{} $false {return} {return} @('c') {param($id,$enabled)$script:favoriteCalls++;$script:favoriteId=$id;$script:favoriteEnabled=$enabled} $true {return}
try{
 $list=@($form.Controls|Where-Object {$_.Tag -eq 'AccountList'})[0]
 if(($list.Controls|ForEach-Object {$_.Tag.Number}) -join ',' -ne '2,3,1'){throw 'Visual order/index mismatch'}
 $card=$list.Controls[1];$star=@($card.Controls|Where-Object {$_.Tag -is [Collections.IDictionary] -and $_.Tag.Kind -eq 'Favorite'})[0]
 if(-not $star.AccessibleName){throw 'Favorite accessible label missing'}
 $star.PerformClick()
 if($script:selected -ne 0 -or $script:favoriteCalls -ne 1 -or $script:favoriteId -ne 'c' -or $script:favoriteEnabled){throw 'Star mouse click selected account or wrong favorite'}
 $enter=[WarmRoundedButton].GetMethod('ProcessDialogKey',[Reflection.BindingFlags]'Instance,NonPublic');$enter.Invoke($star,[object[]]@([Windows.Forms.Keys]::Enter))|Out-Null
 if($script:selected -ne 0 -or $script:favoriteCalls -ne 2){throw 'Star Enter bubbled to account'}
 $down=[WarmRoundedButton].GetMethod('OnKeyDown',[Reflection.BindingFlags]'Instance,NonPublic');$up=[WarmRoundedButton].GetMethod('OnKeyUp',[Reflection.BindingFlags]'Instance,NonPublic');$key=[Windows.Forms.KeyEventArgs]::new([Windows.Forms.Keys]::Space)
 $down.Invoke($star,[object[]]@($key.PSObject.BaseObject))|Out-Null;$up.Invoke($star,[object[]]@($key.PSObject.BaseObject))|Out-Null
 if($script:selected -ne 0 -or $script:favoriteCalls -ne 3){throw 'Star Space bubbled to account'}
 $card.PerformClick();if($script:selected -ne 3){throw 'Account card lost original index'}
 Write-Host 'PASS: active/favorites card order, original selection index, independent star mouse/Enter/Space input and accessible names.'
}finally{$form.Dispose();Dispose-UIResources}
