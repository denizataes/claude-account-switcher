$ErrorActionPreference='Stop'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ClaudeHotkeysTest-'+[guid]::NewGuid().ToString('N'));$oldLocal=$env:LOCALAPPDATA;$oldUser=$env:USERPROFILE
try{
 $env:LOCALAPPDATA=Join-Path $temp 'local';$env:USERPROFILE=Join-Path $temp 'user'
 . (Join-Path $PSScriptRoot 'AccountCore.ps1');Initialize-AccountCore
 . (Join-Path $PSScriptRoot 'PreferenceCore.ps1');. (Join-Path $PSScriptRoot 'HotkeyCore.ps1')
 Add-Type -TypeDefinition @'
using System.Collections.Generic;
public class FakeHotkeyRegistrar {
 public readonly Dictionary<int,string> Active=new Dictionary<int,string>(); public int BlockKey;
 public bool Register(int id,int mod,int key){string value=mod+":"+key;if(key==BlockKey||Active.ContainsValue(value)||Active.ContainsKey(id))return false;Active[id]=value;return true;}
 public bool Unregister(int id){Active.Remove(id);return true;}
}
'@
 $fake=[FakeHotkeyRegistrar]::new();$manager=New-HotkeyManager $fake
 $entries=@(@{Id='a';Identity='a';Name='One'},@{Id='b';Identity='b';Name='Two'},@{Id='c';Identity='c';Name='Three'})
 Write-Json $indexPath @{Accounts=$entries}
 $prefs=Read-Preferences;$prefs['Favorites']=[string[]]@('c');$prefs['AlertsEnabled']=$false;$prefs['Future']='keep';Write-Json (Get-PreferencePath) $prefs
 Save-AccountHotkey $manager 'a' @{Modifiers=3;Key=49} $entries
 $oldId=@($manager.Registered.Keys)[0];$oldHash=(Get-FileHash (Get-PreferencePath)).Hash
 try{Save-AccountHotkey $manager 'b' @{Modifiers=3;Key=49} $entries;throw 'Duplicate accepted'}catch{if($_.Exception.Message -eq 'Duplicate accepted'){throw}}
 if((Get-FileHash (Get-PreferencePath)).Hash -ne $oldHash -or $fake.Active.Count -ne 1){throw 'Duplicate conflict did not restore previous bindings/prefs'}
 if(Resolve-AccountHotkey $manager $oldId $entries 'b' $false){throw 'Old queued native ID was reused'}
 $currentId=@($manager.Registered.Keys)[0]
 if((Resolve-AccountHotkey $manager $currentId @($entries[2],$entries[1],$entries[0]) 'b' $false).Number -ne 3){throw 'Reorder lost immutable account mapping'}
 foreach($state in @(@{Identity='a';Busy=$false},@{Identity='';Busy=$false},@{Identity='b';Busy=$true})){if(Resolve-AccountHotkey $manager $currentId $entries $state.Identity $state.Busy){throw 'Active/unknown/busy dispatch not suppressed'}}
 if(Resolve-AccountHotkey $manager $currentId @($entries[1]) 'b' $false){throw 'Removed account dispatched'}
 $fake.BlockKey=50;try{Save-AccountHotkey $manager 'b' @{Modifiers=3;Key=50} $entries;throw 'OS conflict accepted'}catch{if($_.Exception.Message -eq 'OS conflict accepted'){throw}}
 if((Get-FileHash (Get-PreferencePath)).Hash -ne $oldHash -or $fake.Active.Count -ne 1){throw 'OS conflict lost bindings/prefs'};$fake.BlockKey=0
 $writer=${function:Write-Json};$script:failWrite=$true
 function Write-Json($path,$value){if($script:failWrite -and $path -eq (Get-PreferencePath)){$script:failWrite=$false;throw 'Injected preference persistence failure'};& $writer $path $value}
 try{Save-AccountHotkey $manager 'b' @{Modifiers=3;Key=50} $entries;throw 'Write failure accepted'}catch{if($_.Exception.Message -eq 'Write failure accepted'){throw}}
 Set-Item Function:\Write-Json $writer
 if((Get-FileHash (Get-PreferencePath)).Hash -ne $oldHash -or $fake.Active.Count -ne 1){throw 'Write failure lost previous state'}
 foreach($binding in @(@{Modifiers=0;Key=65},@{Modifiers=4;Key=112},@{Modifiers=8;Key=65},@{Modifiers=11;Key=49},@{Modifiers=2;Key=67},@{Modifiers=3;Key=123},@{Modifiers=1;Key=115})){try{Assert-HotkeyBinding $binding;throw 'Invalid/reserved combo accepted'}catch{if($_.Exception.Message -eq 'Invalid/reserved combo accepted'){throw}}}
 Assert-HotkeyBinding @{Modifiers=2;Key=119};Assert-HotkeyBinding @{Modifiers=3;Key=65}
 Stop-AccountHotkeys $manager;$manager.Suspended=$true
 Save-AccountHotkey $manager 'b' @{Modifiers=3;Key=50} $entries
 if($fake.Active.Count -ne 0){throw 'Settings capture retained registrations'}
 $manager.Suspended=$false;Register-AccountHotkeys $manager (Read-Preferences)['Hotkeys'] $entries
 if($fake.Active.Count -ne 2 -or (Read-Preferences).Future -ne 'keep' -or (Read-Preferences).AlertsEnabled -or (Read-Preferences).Favorites[0] -ne 'c'){throw 'Restart/preferences preservation failed'}
 Stop-AccountHotkeys $manager;$fake.BlockKey=49;Register-AccountHotkeys $manager (Read-Preferences)['Hotkeys'] $entries
 if($manager.Errors.Count -ne 1 -or $fake.Active.Count -ne 1){throw 'Startup conflict did not retain usable registrations'}
 $fake.BlockKey=0;Save-AccountHotkey $manager '' $null $entries $true
 if($fake.Active.Count -or (Read-Preferences).Hotkeys.Count){throw 'Clear all failed'}
 Write-Host 'PASS: shortcut persistence/restart, duplicate/OS/write rollback, capture suspension, monotonic IDs, fresh original indices, busy/active/unknown/removed guards, startup conflict and exact unregister; fake registrar/profiles only.'
}finally{$env:LOCALAPPDATA=$oldLocal;$env:USERPROFILE=$oldUser;if([IO.Path]::GetFullPath($temp).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()))){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}}
$global:LASTEXITCODE=0
