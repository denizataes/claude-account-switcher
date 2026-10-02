$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TrayUI.ps1')
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class HotkeyProbeMessage { [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd,int msg,IntPtr wp,IntPtr lp); }'
$first=[AccountHotkeyHost]::new();$second=[AccountHotkeyHost]::new();$script:fired=0;$script:firedId=0
try{
 $key=135;$registered=$false
 while($key -ge 124){if($first.Register(9000,7,$key)){$registered=$true;break};$key--}
 if(-not $registered){throw 'No unused Ctrl+Alt+Shift+F13-F24 probe available; no existing registration altered.'}
 if($second.Register(9001,7,$key)){throw 'Native OS duplicate registration unexpectedly accepted'}
 $first.Add_Fired({param($sender,$eventArgs)$script:fired++;$script:firedId=$eventArgs.Id})
 if(-not [HotkeyProbeMessage]::PostMessage($first.Handle,0x0312,[IntPtr]9000,[IntPtr](($key -shl 16) -bor 7))){throw 'Native message enqueue failed'}
 $watch=[Diagnostics.Stopwatch]::StartNew();while($script:fired -lt 1 -and $watch.ElapsedMilliseconds -lt 1000){[Windows.Forms.Application]::DoEvents();[Threading.Thread]::Sleep(10)}
 if($script:fired -ne 1 -or $script:firedId -ne 9000){throw 'Native message callback failed'}
 if(-not $first.Unregister(9000)){throw 'Native unregister failed'}
 [void][HotkeyProbeMessage]::PostMessage($first.Handle,0x0312,[IntPtr]9000,[IntPtr]0);[Windows.Forms.Application]::DoEvents()
 if($script:fired -ne 1){throw 'Unregistered queued event dispatched'}
 if(-not $second.Register(9002,7,$key)){throw 'Native registration not released'}
 Write-Host 'PASS: isolated RegisterHotKey OS conflict, WM_HOTKEY callback, queued-ID suppression and unregister/re-register. No keyboard synthesis or account action.'
}finally{$first.Dispose();$second.Dispose();Dispose-UIResources}
