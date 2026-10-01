Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
if(-not ('WarmRoundedButton' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'VisualControls.dll')}
$script:uiFonts=@{}
$script:uiIcon=New-Object Drawing.Icon((Join-Path $PSScriptRoot 'Claude-Switch.ico'))
function Get-UIFont($family,$size,$bold=$false) {
 $key="$family|$size|$bold"
 if(-not $script:uiFonts.ContainsKey($key)){$style=if($bold){[Drawing.FontStyle]::Bold}else{[Drawing.FontStyle]::Regular};$script:uiFonts[$key]=New-Object Drawing.Font($family,[single]$size,$style)}
 return $script:uiFonts[$key]
}
function Dispose-UIResources {foreach($font in $script:uiFonts.Values){$font.Dispose()};$script:uiFonts.Clear();if($script:uiIcon){$script:uiIcon.Dispose();$script:uiIcon=$null}}
$script:Palette=@{ Ink=[Drawing.ColorTranslator]::FromHtml('#3D3A36');Muted=[Drawing.ColorTranslator]::FromHtml('#81776E');Accent=[Drawing.ColorTranslator]::FromHtml('#D97757');Soft=[Drawing.ColorTranslator]::FromHtml('#F3E6DD');Paper=[Drawing.ColorTranslator]::FromHtml('#FAF9F5');Orange=[Drawing.ColorTranslator]::FromHtml('#C15F3C');Border=[Drawing.ColorTranslator]::FromHtml('#E8E0D8') }
function New-UIText($text,$x,$y,$w,$h,$size=10,$bold=$false) {
 $label=New-Object Windows.Forms.Label;$label.Text=$text;$label.Location=New-Object Drawing.Point($x,$y);$label.Size=New-Object Drawing.Size($w,$h)
 $label.Font=if($size -ge 18){Get-UIFont 'Georgia' $size}else{Get-UIFont 'Segoe UI' $size $bold};$label.ForeColor=$Palette.Ink;$label.BackColor=[Drawing.Color]::Transparent
 return $label
}
function New-UIButton($text,$x,$y,$w,$h,$primary=$false) {
 $button=New-Object WarmRoundedButton;$button.Text=$text;$button.Location=New-Object Drawing.Point($x,$y);$button.Size=New-Object Drawing.Size($w,$h)
 $button.Font=Get-UIFont 'Segoe UI' 10 $true;$button.FlatStyle='Flat';$button.FlatAppearance.BorderSize=0;$button.Cursor='Hand'
 $button.BackColor=if($primary){$Palette.Accent}else{$Palette.Soft};$button.ForeColor=if($primary){[Drawing.Color]::White}else{$Palette.Ink}
 $button.FlatAppearance.MouseOverBackColor=if($primary){[Drawing.ColorTranslator]::FromHtml('#C15F3C')}else{[Drawing.ColorTranslator]::FromHtml('#EEDFCE')}
 $button.FlatAppearance.MouseDownBackColor=if($primary){[Drawing.ColorTranslator]::FromHtml('#B45A3C')}else{[Drawing.ColorTranslator]::FromHtml('#E8D3C2')}
 return $button
}
function Format-UsageReset($window) {
 if(-not $window -or -not $window['ResetsAt']){return 'Yenilenme saati bildirilmedi'}
 $date=[DateTimeOffset]::MinValue
 if(-not [DateTimeOffset]::TryParse([string]$window['ResetsAt'],[ref]$date)){return 'Yenilenme saati bildirilmedi'}
 $local=$date.ToLocalTime();$left=$date-[DateTimeOffset]::UtcNow
 $remaining=if($left.TotalMinutes -le 0){'yenilenme zamanı geldi'}elseif($left.TotalDays -ge 1){"$([int][Math]::Floor($left.TotalDays))g $($left.Hours)sa"}else{"$([int][Math]::Floor($left.TotalHours))sa $($left.Minutes)dk"}
 return ('Yenilenme: '+$local.ToString('dd MMM HH:mm',[Globalization.CultureInfo]::GetCultureInfo('tr-TR'))+' · '+$remaining)
}
function New-UsageMeter($period,$key,$x,$y) {
 $panel=New-Object Windows.Forms.Panel;$panel.Location=New-Object Drawing.Point($x,$y);$panel.Size=New-Object Drawing.Size(306,44);$panel.BackColor=[Drawing.Color]::Transparent;$panel.Tag=@{Kind='UsageMeter';Key=$key;Period=$period}
 $title=New-UIText ($period+' · —') 0 0 306 18 8 $true;$title.Tag='MeterTitle'
 $track=New-Object WarmRoundedPanel;$track.Location=New-Object Drawing.Point(0,20);$track.Size=New-Object Drawing.Size(306,5);$track.BackColor=$Palette.Border;$track.Tag='MeterTrack'
 $fill=New-Object WarmRoundedPanel;$fill.Location=New-Object Drawing.Point(0,0);$fill.Height=5;$fill.Width=0;$fill.BackColor=$Palette.Accent;$fill.Tag='MeterFill';$track.Controls.Add($fill)

 $reset=New-UIText 'Veri bekleniyor' 0 28 306 16 7.5;$reset.ForeColor=$Palette.Muted;$reset.Tag='MeterReset'
 $panel.Controls.AddRange(@($title,$track,$reset));return $panel
}
function Update-PopupUsage($form,$usage,$collecting=$false) {
 $list=@($form.Controls | Where-Object {$_.Tag -is [string] -and $_.Tag -eq 'AccountList'})[0]
 if(-not $list){return}
 foreach($card in $list.Controls){
  if(-not ($card -is [WarmRoundedButton])){continue}
  $record=$null;if($usage -and $usage.ContainsKey($card.Tag.UsageId)){$record=$usage[$card.Tag.UsageId]}
  $status=if($collecting -and -not $record){'Limitler kontrol ediliyor'}elseif(-not $record){'Henüz okunmadı'}else{switch($record['Status']){'ok'{'Güncel'};'expired'{'Giriş yenilenmeli'};'auth'{'Giriş yenilenmeli'};'forbidden'{'Kullanım bilgisine erişilemiyor'};'rate_limited'{'Servis beklememizi istedi'};'unsupported'{'Bu hesap limit bildirmedi'};default{'Veri şu an alınamıyor'}}}
  $last=''
  if($record -and $record['Status'] -eq 'ok' -and (($record['FiveHour'] -and $record['FiveHour']['Stale']) -or ($record['SevenDay'] -and $record['SevenDay']['Stale']))){$status='Kısmi veri · eski dönem'}
  if($record -and $record['UpdatedAt']){
   $date=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$record['UpdatedAt']);$last=' · '+$date.ToLocalTime().ToString('HH:mm')
   if($record['Status'] -ne 'ok' -or ([DateTimeOffset]::UtcNow-$date).TotalMinutes -gt 5){$status='Eski veri · '+$(if($record['Status'] -eq 'ok'){'son okuma'}else{$status})}
  }
  foreach($control in $card.Controls){
   if($control.Tag -is [string] -and $control.Tag -eq 'AccountStatus'){$control.Text=$(if($card.Tag.Active){'AKTİF · '}else{''})+$status+$last}
   if($control.Tag -is [Collections.IDictionary] -and $control.Tag['Kind'] -eq 'UsageMeter'){
    $window=if($record){$record[$control.Tag['Key']]}else{$null}
    $known=$window -and $null -ne $window['UsedPercentage']
    $resetPassed=$false
    if($known -and $window['ResetsAt']){$resetDate=[DateTimeOffset]::MinValue;if([DateTimeOffset]::TryParse([string]$window['ResetsAt'],[ref]$resetDate)){$resetPassed=$resetDate -le [DateTimeOffset]::UtcNow}}
    $track=@($control.Controls|Where-Object {$_.Tag -eq 'MeterTrack'})[0]
    foreach($child in $control.Controls){
     if($child.Tag -eq 'MeterTitle'){$child.Text=$control.Tag['Period']+' · '+$(if($known){'%'+([double]$window['UsedPercentage']).ToString('0.#',[Globalization.CultureInfo]::GetCultureInfo('tr-TR'))+' '+$(if($resetPassed -or $window['Stale'] -or $status.StartsWith('Eski veri')){'son okuma'}else{'kullanıldı'})}else{'—'})}
     if($child.Tag -eq 'MeterReset'){$child.Text=if($known){Format-UsageReset $window}else{if($record -and $record['Status'] -eq 'ok'){'Bu dönem için veri bildirilmedi'}else{$status}}}
    }
    $track.Visible=[bool]$known
    if($known){$fill=$track.Controls[0];$fill.Width=[int]([Math]::Min(100,[Math]::Max(0,[double]$window['UsedPercentage']))*$track.Width/100);$fill.BackColor=if([double]$window['UsedPercentage'] -ge 85){$Palette.Orange}else{$Palette.Accent}}
   }
  }
 }
}
function New-AccountPopup($entries,$activeId,$onSelect,$onImport,$onAdd,$onStartup,$startupChecked,$onExit,$usage=$null,$collecting=$false,$onRefresh=$null) {
 $form=New-Object Windows.Forms.Form;$form.SuspendLayout();$form.FormBorderStyle='None';$form.ShowInTaskbar=$false;$form.TopMost=$true;$form.StartPosition='Manual';$form.BackColor=$Palette.Paper
 $form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96);$form.AutoScaleMode='Dpi';$form.Font=Get-UIFont 'Segoe UI' 10
 [WarmRegions]::Apply($form,18)
 $form.KeyPreview=$true;$form.Add_KeyDown({param($sender,$eventArgs) if($eventArgs.KeyCode -eq 'Escape'){$sender.Hide()}})
 $form.Add_Paint({param($sender,$eventArgs) $pen=New-Object Drawing.Pen($Palette.Border);$eventArgs.Graphics.DrawRectangle($pen,0,0,$sender.ClientSize.Width-1,$sender.ClientSize.Height-1);$pen.Dispose()})
 $form.Controls.Add((New-UIText 'CLAUDE · HESAP SEÇİCİ' 24 22 315 22 9 $true))
 $heading=New-UIText 'Direksiyon sende.' 24 52 340 40 23;$heading.Font=Get-UIFont 'Georgia' 23;$form.Controls.Add($heading)
 $subtitle=New-UIText 'Hesap genelinde limitler · 5 saat + hafta' 24 98 340 25 9;$subtitle.ForeColor=$Palette.Muted;$form.Controls.Add($subtitle)
 $close=New-UIButton '×' 351 14 28 28;$close.Font=Get-UIFont 'Segoe UI' 15;$close.Add_Click({param($sender,$eventArgs)$sender.FindForm().Hide()});$form.Controls.Add($close)
 $list=New-Object Windows.Forms.Panel;$list.Tag='AccountList';$list.Location=New-Object Drawing.Point(20,136);$list.Width=360;$list.AutoScroll=$true;$list.BackColor=$Palette.Paper
 $list.Add_Scroll({param($sender,$eventArgs)$sender.Invalidate($true)})
 $count=@($entries).Count;$listDesignHeight=[Math]::Min(360,[Math]::Max(82,$count*178));$list.Height=$listDesignHeight
 for($i=0;$i -lt $count;$i++) {
  $entry=$entries[$i];$active=$entry['Identity'] -eq $activeId
  $button=New-UIButton '' 2 ($i*178) 334 170;$button.BackColor=if($active){$Palette.Soft}else{[Drawing.Color]::White};$button.FlatAppearance.BorderSize=1;$button.FlatAppearance.BorderColor=$Palette.Border
  $button.TextAlign='MiddleLeft';$button.Tag=@{Number=$i+1;Callback=$onSelect;Active=$active;UsageId=$(if($entry['Id']){$entry['Id']}else{$entry['Identity']})};$button.AccessibleName=$entry['Name']
  $name=[string]$entry['Name'];$initial=if($name.Length){$name.Substring(0,1).ToUpperInvariant()}else{'C'}
  $avatar=New-Object WarmAvatar;$avatar.Text=$initial;$avatar.Location=New-Object Drawing.Point(14,14);$avatar.Size=New-Object Drawing.Size(40,40);$avatar.Font=Get-UIFont 'Segoe UI' 17 $true;$avatar.TextAlign='MiddleCenter';$avatar.BackColor=$Palette.Accent;$avatar.ForeColor=[Drawing.Color]::White

  $title=New-UIText $name 68 13 205 24 11 $true;$title.AutoEllipsis=$true
  $hint=New-UIText '' 68 39 242 20 7.5;$hint.Tag='AccountStatus';$hint.AutoEllipsis=$true;$hint.ForeColor=if($active){$Palette.Accent}else{$Palette.Muted}
  $five=New-UsageMeter '5 saat' 'FiveHour' 14 62;$week=New-UsageMeter 'Haftalık' 'SevenDay' 14 114
  $button.Controls.AddRange(@($avatar,$title,$hint,$five,$week))
  $click={param($sender,$eventArgs) $parent=$sender;while($parent -and -not ($parent -is [WarmRoundedButton])){$parent=$parent.Parent};if($parent){$parent.FindForm().Hide();& $parent.Tag.Callback ([int]$parent.Tag.Number)}}
  $button.Add_Click($click);$children=@($avatar,$title,$hint,$five,$week)+@($five.Controls)+@($week.Controls)+@($five.Controls|Where-Object {$_.Tag -eq 'MeterTrack'}|ForEach-Object {$_.Controls})+@($week.Controls|Where-Object {$_.Tag -eq 'MeterTrack'}|ForEach-Object {$_.Controls});foreach($child in $children){$child.Cursor='Hand';$child.Add_Click($click)}
  $list.Controls.Add($button)
 }
 if(-not $count){$empty=New-UIText 'İlk hesabını ekle, ekipman hazır.' 12 24 330 45 11;$empty.ForeColor=$Palette.Muted;$list.Controls.Add($empty)}
 $form.Controls.Add($list)
 $footerY=146+$listDesignHeight
 $import=New-UIButton 'Mevcut hesabı kaydet' 24 $footerY 170 42;$import.Tag=$onImport;$import.Add_Click({param($sender,$eventArgs)$sender.FindForm().Hide();& $sender.Tag});$form.Controls.Add($import)
 $add=New-UIButton '+ Yeni hesap' 206 $footerY 170 42 $true;$add.Tag=$onAdd;$add.Add_Click({param($sender,$eventArgs)$sender.FindForm().Hide();& $sender.Tag});$form.Controls.Add($add)
 $startup=New-Object Windows.Forms.CheckBox;$startup.Text='Windows açılınca hazır olsun';$startup.Checked=$startupChecked;$startup.Location=New-Object Drawing.Point(24,($footerY+60));$startup.Size=New-Object Drawing.Size(275,26);$startup.ForeColor=$Palette.Muted;$startup.Tag=$onStartup
 $startup.Add_CheckedChanged({param($sender,$eventArgs)& $sender.Tag $sender.Checked});$form.Controls.Add($startup)
 if($onRefresh){$refresh=New-UIButton '↻ Limitler' 24 ($footerY+89) 116 28;$refresh.Font=Get-UIFont 'Segoe UI' 8;$refresh.Tag=$onRefresh;$refresh.Add_Click({param($sender,$eventArgs)& $sender.Tag});$form.Controls.Add($refresh)}
 $exit=New-UIButton 'Çıkış' 308 ($footerY+57) 68 30;$exit.Font=Get-UIFont 'Segoe UI' 9;$exit.Tag=$onExit;$exit.Add_Click({param($sender,$eventArgs)& $sender.Tag});$form.Controls.Add($exit)
 $form.ClientSize=New-Object Drawing.Size(400,($footerY+$(if($onRefresh){132}else{103})))
 Update-PopupUsage $form $usage $collecting
 $form.ResumeLayout($true);return $form
}
function Fit-AccountPopup($form,[Drawing.Rectangle]$area) {
 $list=@($form.Controls | Where-Object {$_.Tag -is [string] -and $_.Tag -eq 'AccountList'})[0]
 $excess=$form.Height-($area.Height-16)
 if($excess -gt 0 -and $list){
  $oldBottom=$list.Bottom;$reduction=[Math]::Min($excess,[Math]::Max(0,$list.Height-70))
  foreach($control in $form.Controls){if($control.Top -ge $oldBottom){$control.Top-=$reduction}}
  $list.Height-=$reduction;$form.Height-=$reduction
 }
}
function Show-NameDialog([string]$title) {
 $form=New-Object Windows.Forms.Form;$form.SuspendLayout();$form.Text=$title;$form.Icon=$script:uiIcon;$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false;$form.BackColor=$Palette.Paper;$form.ClientSize=New-Object Drawing.Size(400,205);$form.AutoScaleMode='Dpi';$form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
 $form.Controls.Add((New-UIText $title 24 20 350 35 18 $true));$form.Controls.Add((New-UIText 'Kısa bir ad ver. Gerisi bizde.' 24 61 350 25 10))
 $input=New-Object Windows.Forms.TextBox;$input.Location=New-Object Drawing.Point(24,100);$input.Width=352;$input.Font=Get-UIFont 'Segoe UI' 12;$form.Controls.Add($input)
 $ok=New-UIButton 'Kaydet' 224 151 152 36 $true;$ok.DialogResult='OK';$form.Controls.Add($ok)
 $cancel=New-UIButton 'Vazgeç' 24 151 112 36;$cancel.DialogResult='Cancel';$form.Controls.Add($cancel);$form.AcceptButton=$ok;$form.CancelButton=$cancel
  $form.ResumeLayout($true);try {if($form.ShowDialog() -eq 'OK' -and -not [string]::IsNullOrWhiteSpace($input.Text)){return $input.Text.Trim()};return $null}finally{$form.Dispose()}
}
function Show-CloseConfirmation([int]$count,[string]$PreviewPath) {
 $form=New-Object Windows.Forms.Form;$form.SuspendLayout();$form.Text='Claude oturumlarını kapat';$form.Icon=$script:uiIcon;$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false;$form.BackColor=$Palette.Paper;$form.ClientSize=New-Object Drawing.Size(440,250);$form.AutoScaleMode='Dpi';$form.AutoScaleDimensions=New-Object Drawing.SizeF(96,96)
 $form.Controls.Add((New-UIText "$count Claude oturumu açık" 24 22 392 40 18 $true))
 $form.Controls.Add((New-UIText 'Hesap işlemi için bu oturumlar kapatılacak. Kaydedilmemiş çalışma kesilebilir. Terminal pencereleri kapatılmaz.' 24 77 392 83 11))
 $yes=New-UIButton 'Evet, kapat ve devam et' 174 190 242 40 $true;$yes.DialogResult='Yes';$form.Controls.Add($yes)
 $no=New-UIButton 'Vazgeç' 24 190 126 40;$no.DialogResult='No';$form.Controls.Add($no);$form.AcceptButton=$no;$form.CancelButton=$no
 try{
  if($PreviewPath){$form.StartPosition='Manual';$form.Location=New-Object Drawing.Point(-32000,-32000);$form.Show();[Windows.Forms.Application]::DoEvents();$bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height);$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save($PreviewPath,[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose();return $false}
   $form.ResumeLayout($true);return $form.ShowDialog() -eq 'Yes'
 }finally{$form.Dispose()}
}














