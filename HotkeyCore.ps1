function Assert-HotkeyBinding($binding) {
 if(-not ($binding -is [Collections.IDictionary])){throw 'Invalid hotkey binding.'}
 $mod=0;$key=0
 if(-not [int]::TryParse([string]$binding['Modifiers'],[ref]$mod) -or -not [int]::TryParse([string]$binding['Key'],[ref]$key)){throw 'Invalid shortcut values.'}
 $functionKey=($key -ge 112 -and $key -le 135 -and $key -ne 123)
 $letterOrDigit=($key -ge 48 -and $key -le 57) -or ($key -ge 65 -and $key -le 90)
 $count=0;foreach($bit in @(1,2,4)){if($mod -band $bit){$count++}}
 if($mod -lt 1 -or $mod -gt 7 -or -not ($mod -band 3) -or ($key -eq 115 -and ($mod -band 1)) -or (-not $functionKey -and -not ($letterOrDigit -and $count -ge 2))){throw 'Use Ctrl/Alt with an F key (except F12 / Alt+F4), or two modifiers with A-Z / 0-9. Windows shortcuts are not supported.'}
}
function Format-AccountHotkey($binding) {
 if(-not $binding){return '—'}
 $parts=@();$mod=[int]$binding['Modifiers'];if($mod -band 2){$parts+='Ctrl'};if($mod -band 1){$parts+='Alt'};if($mod -band 4){$parts+='Shift'}
 $key=[int]$binding['Key'];$parts+=if($key -ge 48 -and $key -le 57){[string][char]$key}else{[string][Windows.Forms.Keys]$key};return $parts -join '+'
}
function New-HotkeyManager($registrar) {return @{Registrar=$registrar;Registered=@{};Bindings=@{};Errors=@{};NextId=1;Suspended=$false}}
function Stop-AccountHotkeys($manager) {
 foreach($id in @($manager.Registered.Keys)){if(-not $manager.Registrar.Unregister([int]$id)){throw 'A shortcut could not be released. Restart the app before editing shortcuts.'};[void]$manager.Registered.Remove($id)}
 $manager.Bindings=@{}
}
function Register-AccountHotkeys($manager,$bindings,$entries,[bool]$strict=$false) {
 $manager.Errors=@{};$combos=@{};$live=@($entries|ForEach-Object {$_['Id']})
 foreach($accountId in $bindings.Keys){
  try{
   if($accountId -notin $live){throw 'Saved account no longer exists.'}
   $binding=$bindings[$accountId];Assert-HotkeyBinding $binding
   $combo=[string]$binding['Modifiers']+':'+[string]$binding['Key'];if($combos.ContainsKey($combo)){throw 'Two saved accounts cannot use the same shortcut.'};$combos[$combo]=$true
   $nativeId=[int]$manager.NextId;$manager.NextId++
   if($nativeId -gt 49151){throw 'Shortcut IDs exhausted. Restart the app.'}
   if(-not $manager.Registrar.Register($nativeId,[int]$binding['Modifiers'],[int]$binding['Key'])){throw 'Shortcut is reserved or already in use by another app.'}
   $manager.Registered[$nativeId]=[string]$accountId;$manager.Bindings[[string]$accountId]=@{Modifiers=[int]$binding['Modifiers'];Key=[int]$binding['Key']}
  }catch{$manager.Errors[[string]$accountId]=$_.Exception.Message;if($strict){throw}}
 }
}
function Save-AccountHotkey($manager,[string]$accountId,$binding,$entries,[bool]$clearAll=$false) {
 $old=$manager.Bindings;$suspended=[bool]$manager.Suspended
 try{Invoke-PreferenceUpdate {
  param($value)
  $live=@($entries|ForEach-Object {$_['Id']});if(-not $clearAll -and $accountId -notin $live){throw 'Account is no longer saved.'}
  $candidate=$json.DeserializeObject($json.Serialize($value['Hotkeys']))
  foreach($id in @($candidate.Keys)){if($id -notin $live){[void]$candidate.Remove($id)}}
  if($clearAll){$candidate=@{}}elseif($binding){Assert-HotkeyBinding $binding;$candidate[$accountId]=@{Modifiers=[int]$binding['Modifiers'];Key=[int]$binding['Key']}}else{[void]$candidate.Remove($accountId)}
  Stop-AccountHotkeys $manager;Register-AccountHotkeys $manager $candidate $entries $true
  $value['Hotkeys']=$candidate
 } {
  Stop-AccountHotkeys $manager
  if(-not $suspended){Register-AccountHotkeys $manager $old $entries;if($manager.Errors.Count){throw 'Previous shortcuts could not all be restored; reopen Settings.'}}
 }|Out-Null}finally{if($suspended){Stop-AccountHotkeys $manager}}
}
function Resolve-AccountHotkey($manager,[int]$nativeId,$entries,[string]$activeIdentity,[bool]$busy) {
 if($busy -or $manager.Suspended -or [string]::IsNullOrEmpty($activeIdentity) -or -not $manager.Registered.ContainsKey($nativeId)){return $null}
 $id=$manager.Registered[$nativeId]
 for($i=0;$i -lt @($entries).Count;$i++){if($entries[$i]['Id'] -eq $id){if($entries[$i]['Identity'] -eq $activeIdentity){return $null};return @{Id=$id;Number=$i+1}}}
 return $null
}
