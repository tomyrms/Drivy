# Icône provisoire du laboratoire : géométrie vectorielle, couleurs de la référence Drivy.
Add-Type -AssemblyName System.Drawing
$drivyIconDirectory = Join-Path $PSScriptRoot '../apps/ios/Drivy/Resources/Assets.xcassets/AppIcon.appiconset'
[IO.Directory]::CreateDirectory($drivyIconDirectory) | Out-Null
$drivyBitmap = [Drawing.Bitmap]::new(1024, 1024)
$drivyGraphics = [Drawing.Graphics]::FromImage($drivyBitmap)
$drivyGraphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$drivyGraphics.Clear([Drawing.ColorTranslator]::FromHtml('#EAF0FE'))
$drivyRoad = [Drawing.Pen]::new([Drawing.Color]::White, 100)
$drivyRoad.StartCap = [Drawing.Drawing2D.LineCap]::Round
$drivyRoad.EndCap = [Drawing.Drawing2D.LineCap]::Round
$drivyGraphics.DrawLine($drivyRoad, -50, 320, 1100, 760)
$drivyGraphics.DrawLine($drivyRoad, 650, -30, 350, 1100)
$drivyRoute = [Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#245BD6'), 72)
$drivyRoute.StartCap = [Drawing.Drawing2D.LineCap]::Round
$drivyRoute.EndCap = [Drawing.Drawing2D.LineCap]::Round
$drivyRoute.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
$drivyPath = [Drawing.Drawing2D.GraphicsPath]::new()
$drivyPath.AddBezier(296, 758, 290, 550, 732, 688, 728, 458)
$drivyPath.AddBezier(728, 458, 726, 314, 548, 346, 510, 236)
$drivyGraphics.DrawPath($drivyRoute, $drivyPath)
$drivyBlue = [Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#245BD6'))
$drivyWhite = [Drawing.SolidBrush]::new([Drawing.Color]::White)
$drivyGraphics.FillEllipse($drivyWhite, 212, 674, 168, 168)
$drivyGraphics.FillEllipse($drivyBlue, 247, 709, 98, 98)
$drivyArrow = [Drawing.PointF[]]@([Drawing.PointF]::new(510,158),[Drawing.PointF]::new(407,303),[Drawing.PointF]::new(510,274),[Drawing.PointF]::new(613,303))
$drivyGraphics.FillPolygon($drivyBlue, $drivyArrow)
$drivyBitmap.Save((Join-Path $drivyIconDirectory 'AppIcon.png'), [Drawing.Imaging.ImageFormat]::Png)
$drivyPath.Dispose()
$drivyRoad.Dispose()
$drivyRoute.Dispose()
$drivyBlue.Dispose()
$drivyWhite.Dispose()
$drivyGraphics.Dispose()
$drivyBitmap.Dispose()
