function Show-TokenDialog([string]$PreviewPath) {
 $form=[Windows.Forms.Form]::new();$form.SuspendLayout();$form.Text='Token ile hesap ekle';$form.Icon=$script:uiIcon;$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false;$form.MinimizeBox=$false;$form.BackColor=$Palette.Paper;$form.ClientSize=[Drawing.Size]::new(470,535);$form.AutoScaleDimensions=[Drawing.SizeF]::new(96,96);$form.AutoScaleMode='Dpi'
 $form.Controls.Add((New-UIText 'Anahtar sende.' 24 20 420 40 23))
 $form.Controls.Add((New-UIText 'Kendi tokenini ekle. Etkinleştirmek için sonra listeden seç.' 24 67 420 35 9))
 $form.Controls.Add((New-UIText 'Hesap adı' 24 107 422 18 9 $true));
 $form.Controls.Add((New-UIText 'Bağlantı türü' 24 166 422 18 9 $true));
 $form.Controls.Add((New-UIText 'Token / API key' 24 224 422 18 9 $true));
 $name=[Windows.Forms.TextBox]::new();$name.Location=[Drawing.Point]::new(24,129);$name.Width=422;$name.Font=Get-UIFont 'Segoe UI' 11;$name.AccessibleName='Hesap adı';$form.Controls.Add($name)
 $kind=[Windows.Forms.ComboBox]::new();$kind.DropDownStyle='DropDownList';$kind.Location=[Drawing.Point]::new(24,188);$kind.Width=422;$kind.Font=Get-UIFont 'Segoe UI' 10;[void]$kind.Items.AddRange(@('setup-token · Claude aboneliği','OAuth access token · Claude aboneliği','API key · API kullanımı'));$kind.SelectedIndex=0;$kind.AccessibleName='Token türü';$form.Controls.Add($kind)
 $input=[Windows.Forms.TextBox]::new();$input.Location=[Drawing.Point]::new(24,246);$input.Width=422;$input.UseSystemPasswordChar=$true;$input.MaxLength=16384;$input.Font=Get-UIFont 'Segoe UI' 11;$input.AccessibleName='Gizli token';$form.Controls.Add($input)
 $check=[Windows.Forms.CheckBox]::new();$check.Text='Sunucuda kontrol et (model isteği göndermez)';$check.Location=[Drawing.Point]::new(24,289);$check.Size=[Drawing.Size]::new(422,28);$check.Font=Get-UIFont 'Segoe UI' 9;$form.Controls.Add($check)
 $info=New-UIText '' 24 325 422 110 9;$info.ForeColor=$Palette.Muted;$info.AutoEllipsis=$false;$form.Controls.Add($info)
 $status=New-UIText '' 24 440 422 32 9;$form.Controls.Add($status)
 $ok=New-UIButton 'Kaydet' 290 480 156 36 $true;$cancel=New-UIButton 'Vazgeç' 24 480 112 36;$cancel.DialogResult='Cancel';$form.Controls.AddRange(@($ok,$cancel));$form.CancelButton=$cancel
 $ctx=@{PowerShell=$null;Pending=$null;Result=$null;Kinds=@('SetupToken','OAuthAccess','ApiKey');Form=$form;Name=$name;Input=$input;Kind=$kind;Check=$check;Info=$info;Status=$status;OK=$ok;Root=$PSScriptRoot;Cancellation=[hashtable]::Synchronized(@{Cancelled=$false;Request=$null})}
 $kind.Tag=$ctx;$kind.Add_SelectedIndexChanged({param($sender,$args)$c=$sender.Tag;$setup=$sender.SelectedIndex -eq 0;$c.Check.Enabled=-not $setup;$c.Check.Checked=-not $setup;$c.Info.Text=if($setup){'setup-token yalnızca model isteklerini destekler. Sunucuda kimlik kontrolü ve limitler yok; geçerlilik / süre bilinmiyor.'}elseif($sender.SelectedIndex -eq 1){'Access token otomatik yenilenmez. Profil yetkisi yoksa kontrol başarısız olur; süre bilinmiyor.'}else{'API key abonelik limitlerini kullanmaz; kullanım API anahtarı sahibine faturalanır.'};$c.Info.Text+=' Seçilen token native Claude için kullanıcı settings.json içinde açık metin olur; kayıtlar DPAPI ile korunur.'})
 $kind.SelectedIndex=1;$kind.SelectedIndex=0
 $timer=[Windows.Forms.Timer]::new();$timer.Interval=150;$timer.Tag=$ctx
 $ok.Tag=$ctx;$ok.Add_Click({param($sender,$args)$c=$sender.Tag
  try{
   if([string]::IsNullOrWhiteSpace($c.Name.Text)){throw 'Hesap adı girin.'}
   $state=@{AuthKind=$c.Kinds[$c.Kind.SelectedIndex];Token=$c.Input.Text;Identity='token-fixture'};Assert-TokenSnapshot $state
   if(-not $c.Check.Checked){$c.Result=@{Kind=$state.AuthKind;Token=$state.Token;Name=$c.Name.Text.Trim();Validation=@{Status='unverified'}};$c.Form.DialogResult='OK';return}
   $c.OK.Enabled=$false;$c.Kind.Enabled=$false;$c.Input.Enabled=$false;$c.Name.Enabled=$false;$c.Check.Enabled=$false;$c.Status.Text='Yalnızca okuma kontrolü yapılıyor...'
   $c.PowerShell=[Management.Automation.PowerShell]::Create()
   [void]$c.PowerShell.AddScript('param($root,$kind,$token,$cancel); . (Join-Path $root "AccountCore.ps1"); Initialize-AccountCore; Invoke-TokenReadCheck $kind $token $cancel').AddArgument($c.Root).AddArgument($state.AuthKind).AddArgument($state.Token).AddArgument($c.Cancellation)
   $c.Pending=$c.PowerShell.BeginInvoke()
  }catch{$c.Status.Text=$_.Exception.Message}
 })
 $timer.Add_Tick({param($sender,$args)$c=$sender.Tag
  if($c.Pending -and $c.Pending.IsCompleted){
   try{
    $result=$c.PowerShell.EndInvoke($c.Pending)
    if($c.PowerShell.HadErrors -or -not $result.Count){throw 'Kontrol tamamlanamadı. Token kaydedilmedi; türü/yetkileri kontrol edin.'}
    $c.Result=@{Kind=$c.Kinds[$c.Kind.SelectedIndex];Token=$c.Input.Text;Name=$c.Name.Text.Trim();Validation=$result[0]};$c.Form.DialogResult='OK'
   }catch{$c.Status.Text=$_.Exception.Message;$c.OK.Enabled=$true;$c.Kind.Enabled=$true;$c.Input.Enabled=$true;$c.Name.Enabled=$true;$c.Check.Enabled=$c.Kind.SelectedIndex -ne 0}
   finally{$c.PowerShell.Dispose();$c.PowerShell=$null;$c.Pending=$null}
  }
 })
 $form.ResumeLayout($true)
 try{
  if($PreviewPath){$name.Text='Demo account';$input.Text='demo-masked-token';$form.Location=[Drawing.Point]::new(-32000,-32000);$form.StartPosition='Manual';$form.Show();[Windows.Forms.Application]::DoEvents();$bitmap=[Drawing.Bitmap]::new($form.Width,$form.Height);try{$form.DrawToBitmap($bitmap,[Drawing.Rectangle]::new(0,0,$form.Width,$form.Height));$bitmap.Save($PreviewPath)}finally{$bitmap.Dispose()};return $null}
  $timer.Start();if($form.ShowDialog() -eq 'OK'){return $ctx.Result};return $null
 }finally{$timer.Stop();$timer.Dispose();$input.Clear();$name.Clear();if($ctx.PowerShell){$ctx.Cancellation.Cancelled=$true;if($ctx.Cancellation.Request){$ctx.Cancellation.Request.Abort()};$stop=$ctx.PowerShell.BeginStop($null,$null);$script:tokenCleanups=@($script:tokenCleanups)+@(@{PowerShell=$ctx.PowerShell;Stop=$stop})};$ctx.Pending=$null;$ctx.Result=$null;$form.Dispose()}
}
function Complete-TokenCleanup {
 if(-not $script:tokenCleanups){return}
 $remaining=@()
 foreach($item in $script:tokenCleanups){if($item.Stop.IsCompleted){try{$item.PowerShell.EndStop($item.Stop)}catch{};$item.PowerShell.Dispose()}else{$remaining+=,$item}}
 $script:tokenCleanups=$remaining
}
