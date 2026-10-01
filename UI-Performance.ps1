$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TrayUI.ps1')
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class UiResourceMeasure { [DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr process,uint kind); }'
$entries=1..12|ForEach-Object {@{Name="Fixture $_";Identity="id-$_";Id="id-$_"}}
function New-FixtureForm {return New-AccountPopup $entries 'id-1' {} {} {} {} $true {} @{} $false {}}
$form=New-FixtureForm
try{
 $form.TopMost=$false;$form.Location=New-Object Drawing.Point(-32000,-32000);$form.Show();[Windows.Forms.Application]::DoEvents();$form.Hide()
 $p=Get-Process -Id $PID;$beforeGdi=[UiResourceMeasure]::GetGuiResources($p.Handle,0);$beforeHandles=$p.HandleCount
 $watch=[Diagnostics.Stopwatch]::StartNew()
 for($i=0;$i -lt 50;$i++){$form.Show();[Windows.Forms.Application]::DoEvents();$form.Hide()}
 $watch.Stop();$p.Refresh();$reuseGdi=[UiResourceMeasure]::GetGuiResources($p.Handle,0);$reuseHandles=$p.HandleCount
 $form.Dispose();$form=$null
 for($i=0;$i -lt 20;$i++){$temporary=New-FixtureForm;$temporary.CreateControl();$temporary.Dispose()}
 [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();$p.Refresh();$afterGdi=[UiResourceMeasure]::GetGuiResources($p.Handle,0)
 $result=@{OpenCloseCycles=50;AverageCycleMs=[Math]::Round($watch.Elapsed.TotalMilliseconds/50,2);ReuseGdiDelta=[int]$reuseGdi-[int]$beforeGdi;ReuseHandleDelta=$reuseHandles-$beforeHandles;StressRebuilds=20;FinalGdi=$afterGdi;BaselineGdi=$beforeGdi;SharedFontCount=$script:uiFonts.Count}
 if($result.ReuseGdiDelta -gt 5 -or $result.ReuseHandleDelta -gt 10){throw 'Resource growth during reused popup cycles'}
 $result|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'performance-ui.json')
 $result|ConvertTo-Json
}finally{if($form){$form.Dispose()};Dispose-UIResources}
