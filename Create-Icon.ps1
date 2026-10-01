Add-Type -AssemblyName System.Drawing
$images=@()
foreach ($size in @(16,32,48)) {
 $bitmap=New-Object Drawing.Bitmap($size,$size)
 $g=[Drawing.Graphics]::FromImage($bitmap)
 $g.SmoothingMode='AntiAlias'
 $g.ScaleTransform(($size/48.0),($size/48.0))
 $bg=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(217,119,87))
 $white=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(250,249,245))
 $orange=New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(250,229,215))
 $rays=New-Object 'Collections.Generic.List[Drawing.PointF]'
 for($j=0;$j -lt 32;$j++){$angle=$j*[Math]::PI/16;$radius=if($j%2){18}else{23};$rays.Add([Drawing.PointF]::new([single](24+[Math]::Cos($angle)*$radius),[single](24+[Math]::Sin($angle)*$radius)))}
 $g.FillPolygon($bg,$rays.ToArray())
 $top=[Drawing.PointF[]]@([Drawing.PointF]::new(10,15),[Drawing.PointF]::new(29,15),[Drawing.PointF]::new(29,10),[Drawing.PointF]::new(39,19),[Drawing.PointF]::new(29,28),[Drawing.PointF]::new(29,23),[Drawing.PointF]::new(10,23))
 $bottom=[Drawing.PointF[]]@([Drawing.PointF]::new(38,26),[Drawing.PointF]::new(19,26),[Drawing.PointF]::new(19,21),[Drawing.PointF]::new(9,30),[Drawing.PointF]::new(19,39),[Drawing.PointF]::new(19,34),[Drawing.PointF]::new(38,34))
 $g.FillPolygon($white,$top);$g.FillPolygon($orange,$bottom)
 $stream=New-Object IO.MemoryStream
 $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
 $images+=,@{Size=$size;Data=$stream.ToArray()}
 if ($size -eq 48) {$bitmap.Save((Join-Path $PSScriptRoot 'Icon-Preview.png'),[Drawing.Imaging.ImageFormat]::Png)}
 $stream.Dispose();$g.Dispose();$bitmap.Dispose();$bg.Dispose();$white.Dispose();$orange.Dispose()
}
$file=[IO.File]::Create((Join-Path $PSScriptRoot 'Claude-Switch.ico'))
$writer=New-Object IO.BinaryWriter($file)
try {
 $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
 $offset=6+16*$images.Count
 foreach ($image in $images) {
  $writer.Write([byte]$image.Size);$writer.Write([byte]$image.Size);$writer.Write([byte]0);$writer.Write([byte]0)
  $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$image.Data.Length);$writer.Write([uint32]$offset)
  $offset+=$image.Data.Length
 }
 foreach ($image in $images) {$writer.Write([byte[]]$image.Data)}
} finally {$writer.Dispose();$file.Dispose()}
