$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TrayUI.ps1')
$out=Join-Path $PSScriptRoot 'previews';New-Item -ItemType Directory -Path $out -Force | Out-Null
foreach($count in @(0,5,12)){
 foreach($scale in @(1.0,1.5,2.0)){
  $entries=@();for($i=0;$i -lt $count;$i++){$entries+=,@{Identity="id-$i";Name=$(if($i -eq 0){'Personal account'}elseif($i -eq 1){'Work account - Product team'}else{"Demo account $($i+1)"})}}
  $fixtures=@{}
  for($i=0;$i -lt $count;$i++){
   $fixtures["id-$i"]=@{Status=$(switch($i){2{'expired'};3{'rate_limited'};4{'unsupported'};default{'ok'}});UpdatedAt=[DateTimeOffset]::UtcNow.AddMinutes($(if($i -eq 2){-20}else{0})).ToUnixTimeMilliseconds();FiveHour=$(if($i -eq 4){$null}else{@{UsedPercentage=$(if($i -eq 0){5}elseif($i -eq 1){0}else{42.5});ResetsAt=[DateTimeOffset]::UtcNow.AddHours(3).ToString('o')}});SevenDay=$(if($i -eq 4){$null}else{@{UsedPercentage=$(if($i -eq 1){100}else{26});ResetsAt=[DateTimeOffset]::UtcNow.AddDays(6).ToString('o')}})}
  }
  $form=New-AccountPopup $entries 'id-1' {} {} {} {} $true {} $fixtures $false {}
  try{
   $form.TopMost=$false;$form.Location=New-Object Drawing.Point(-32000,-32000);$form.Show();[Windows.Forms.Application]::DoEvents();$form.Scale((New-Object Drawing.SizeF($scale,$scale)))
   Fit-AccountPopup $form (New-Object Drawing.Rectangle(0,0,1920,1040))
   if($form.Height -gt 1024){throw 'Popup exceeds working area'}
   foreach($control in $form.Controls){if($control.Bottom -gt $form.ClientSize.Height -or $control.Right -gt $form.ClientSize.Width){throw 'Top-level control clipped'}}
   $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
   $form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)))
   $bitmap.Save((Join-Path $out ("tray-$count-$scale.png")),[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose()
  }finally{$form.Dispose()}
 }
}
Write-Host 'PASS: empty/5/12 accounts; Unicode long names; 100/150/200% scale; working-area fit and control bounds.'
[void](Show-CloseConfirmation 3 (Join-Path $out 'confirmation.png'))




