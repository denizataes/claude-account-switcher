function Show-HotkeySettings($manager,$entries,[string]$PreviewPath='') {
 $form=[Windows.Forms.Form]::new();$form.SuspendLayout();$form.Text='Ayarlar · Hesap kısayolları';$form.Icon=$script:uiIcon;$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false;$form.BackColor=$Palette.Paper;$form.ClientSize=[Drawing.Size]::new(490,540);$form.AutoScaleDimensions=[Drawing.SizeF]::new(96,96);$form.AutoScaleMode='Dpi'
 $form.Controls.Add((New-UIText 'Bir tuş, bir hesap.' 24 20 440 40 23))
 $form.Controls.Add((New-UIText 'Kısayol yeni varsayılan hesabı seçer. Açık Claude oturumları için kapatma onayı yine sorulur.' 24 70 440 48 9))
 $form.Controls.Add((New-UIText 'Kaydedilmiş hesap' 24 132 440 20 9 $true))
 $accounts=[Windows.Forms.ListBox]::new();$accounts.Height=82;$accounts.Location=[Drawing.Point]::new(24,158);$accounts.Width=442;$accounts.Font=Get-UIFont 'Segoe UI' 11;$accounts.AccessibleName='Kısayol atanacak hesap';$form.Controls.Add($accounts)
 $form.Controls.Add((New-UIText 'Kısayol · alana tıkla ve tuşlara bas' 24 254 440 20 9 $true))
 $capture=[Windows.Forms.TextBox]::new();$capture.ReadOnly=$true;$capture.Location=[Drawing.Point]::new(24,280);$capture.Width=442;$capture.Font=Get-UIFont 'Segoe UI' 12;$capture.AccessibleName='Kısayol kaydetme alanı';$form.Controls.Add($capture)
 $info=New-UIText 'Örnek: Ctrl+Alt+1 veya Ctrl+F8. Harf/rakam için iki değiştirici; F12 ve Windows tuşu desteklenmez. Bu pencere açıkken kendi kısayolların durdurulur.' 24 323 440 70 9;$info.ForeColor=$Palette.Muted;$form.Controls.Add($info)
 $status=New-UIText '' 24 400 440 48 9;$status.ForeColor=$Palette.Orange;$form.Controls.Add($status)
 $clear=New-UIButton 'Temizle' 24 486 100 34;$all=New-UIButton 'Tümünü temizle' 132 486 130 34;$all.Font=Get-UIFont 'Segoe UI' 8;$save=New-UIButton 'Kaydet' 274 486 92 34 $true;$close=New-UIButton 'Kapat' 376 486 90 34;$close.DialogResult='Cancel';$form.Controls.AddRange(@($clear,$all,$save,$close));$form.CancelButton=$close
 $ctx=@{Form=$form;Manager=$manager;Entries=$entries;Accounts=$accounts;Capture=$capture;Status=$status;Binding=$null}
 $preferences=Read-Preferences
 foreach($entry in @($entries)){$binding=$preferences['Hotkeys'][$entry['Id']];$suffix=if($manager.Errors.ContainsKey([string]$entry['Id'])){' · etkin değil'}else{''};[void]$accounts.Items.Add(([string]$entry['Name']+' · '+(Format-AccountHotkey $binding)+$suffix))}
 $accounts.Tag=$ctx;$accounts.Add_SelectedIndexChanged({param($sender,$eventArgs)$c=$sender.Tag;$entry=$c.Entries[$sender.SelectedIndex];$c.Binding=(Read-Preferences)['Hotkeys'][$entry['Id']];$c.Capture.Text=Format-AccountHotkey $c.Binding;$c.Status.Text=''})
 $capture.Tag=$ctx;$capture.Add_KeyDown({param($sender,$eventArgs)$eventArgs.SuppressKeyPress=$true;$eventArgs.Handled=$true;$mod=0;if($eventArgs.Alt){$mod=$mod-bor 1};if($eventArgs.Control){$mod=$mod-bor 2};if($eventArgs.Shift){$mod=$mod-bor 4};if([AccountHotkeyHost]::WindowsKeyDown()){$mod=$mod-bor 8};$binding=@{Modifiers=$mod;Key=[int]$eventArgs.KeyCode};try{Assert-HotkeyBinding $binding;$sender.Tag.Binding=$binding;$sender.Text=Format-AccountHotkey $binding;$sender.Tag.Status.Text=''}catch{$sender.Tag.Status.Text='Geçerli bir kombinasyon kullan. Örnek: Ctrl+Alt+1 / Ctrl+F8.'}})
 $clear.Tag=$ctx;$clear.Add_Click({param($sender,$eventArgs)$sender.Tag.Binding=$null;$sender.Tag.Capture.Text='—';$sender.Tag.Status.Text='Silmek için Kaydet.'})
 $save.Tag=$ctx;$save.Add_Click({param($sender,$eventArgs)$c=$sender.Tag;try{$entry=$c.Entries[$c.Accounts.SelectedIndex];$fresh=@((Read-Json $indexPath)['Accounts']);Save-AccountHotkey $c.Manager $entry['Id'] $c.Binding $fresh;$c.Status.Text='Kaydedildi. Pencere kapanınca kısayol etkinleşir.';$c.Accounts.Items[$c.Accounts.SelectedIndex]=[string]$entry['Name']+' · '+(Format-AccountHotkey $c.Binding)}catch{$c.Status.Text=$_.Exception.Message}})
 $all.Tag=$ctx;$all.Add_Click({param($sender,$eventArgs)$c=$sender.Tag;try{Save-AccountHotkey $c.Manager '' $null @((Read-Json $indexPath)['Accounts']) $true;$c.Binding=$null;$c.Capture.Text='—';$c.Status.Text='Tüm kısayollar temizlendi.';for($i=0;$i -lt $c.Entries.Count;$i++){$c.Accounts.Items[$i]=[string]$c.Entries[$i]['Name']+' · —'}}catch{$c.Status.Text=$_.Exception.Message}})
 if($accounts.Items.Count){$accounts.SelectedIndex=0}else{$save.Enabled=$false;$capture.Enabled=$false;$status.Text='Önce bir hesap kaydet.'}
 $form.ResumeLayout($true)
 try{
  if($PreviewPath){$capture.Text='Ctrl+Alt+1';$form.StartPosition='Manual';$form.Location=[Drawing.Point]::new(-32000,-32000);$form.Show();[Windows.Forms.Application]::DoEvents();$bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$bitmap.Save($PreviewPath)}finally{$bitmap.Dispose()};return}
  [void]$form.ShowDialog()
 }finally{$form.Dispose()}
}
