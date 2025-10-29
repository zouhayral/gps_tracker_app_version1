# Alternative Image Conversion Guide
# Use this if ImageMagick is not available

Write-Host "=== Alternative Image Conversion Options ===" -ForegroundColor Cyan
Write-Host ""

# Check for icon.png as alternative
$iconPath = "..\assets\icon.png"
$logoPng = "..\assets\logo.png"

if (Test-Path $iconPath) {
    Write-Host "✓ Found icon.png - can use as temporary logo" -ForegroundColor Green
    if (-not (Test-Path $logoPng)) {
        Copy-Item $iconPath $logoPng
        Write-Host "✓ Copied icon.png to logo.png" -ForegroundColor Green
    }
} else {
    Write-Host "✗ No existing image assets found" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Online Conversion (Easiest Method) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Visit: https://cloudconvert.com/png-to-webp" -ForegroundColor White
Write-Host "   OR: https://convertio.co/png-webp/" -ForegroundColor White
Write-Host "   OR: https://www.freeconvert.com/png-to-webp" -ForegroundColor White
Write-Host ""
Write-Host "2. Upload your logo image (PNG/JPG)" -ForegroundColor White
Write-Host ""
Write-Host "3. For MAIN LOGO (logo.webp):" -ForegroundColor Yellow
Write-Host "   - Set dimensions: 200x200 pixels" -ForegroundColor White
Write-Host "   - Set quality: 85" -ForegroundColor White
Write-Host "   - Download and save to: assets\logo.webp" -ForegroundColor White
Write-Host ""
Write-Host "4. For PLACEHOLDER (logo_placeholder.webp):" -ForegroundColor Yellow
Write-Host "   - Set dimensions: 50x50 pixels" -ForegroundColor White
Write-Host "   - Set quality: 60" -ForegroundColor White
Write-Host "   - Download and save to: assets\logo_placeholder.webp" -ForegroundColor White
Write-Host ""
Write-Host "=== Using Paint.NET (Windows) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Download Paint.NET: https://www.getpaint.net/" -ForegroundColor White
Write-Host "2. Install WebP plugin: https://github.com/0xC0000054/pdn-webp" -ForegroundColor White
Write-Host "3. Open your logo in Paint.NET" -ForegroundColor White
Write-Host "4. Resize to 200x200 (Image > Canvas Size)" -ForegroundColor White
Write-Host "5. Save As > WebP format (Quality: 85)" -ForegroundColor White
Write-Host "6. Repeat for 50x50 placeholder (Quality: 60)" -ForegroundColor White
Write-Host ""
Write-Host "=== Using GIMP (Free) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Download GIMP: https://www.gimp.org/downloads/" -ForegroundColor White
Write-Host "2. Open your logo" -ForegroundColor White
Write-Host "3. Scale Image (Image > Scale Image): 200x200" -ForegroundColor White
Write-Host "4. Export As > logo.webp (Quality: 85)" -ForegroundColor White
Write-Host "5. Repeat for 50x50 placeholder" -ForegroundColor White
Write-Host ""
Write-Host "=== Using Photoshop ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Open logo in Photoshop" -ForegroundColor White
Write-Host "2. Image > Image Size: 200x200" -ForegroundColor White
Write-Host "3. File > Export > Save for Web" -ForegroundColor White
Write-Host "4. Choose WebP, Quality: 85" -ForegroundColor White
Write-Host "5. Save to assets\logo.webp" -ForegroundColor White
Write-Host "6. Repeat for 50x50 placeholder" -ForegroundColor White
Write-Host ""
Write-Host "=== Temporary Fallback (Testing Only) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "If you just want to test the code without WebP:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Keep using PNG temporarily:" -ForegroundColor White
Write-Host "   - Change code: 'assets/logo.webp' → 'assets/logo.png'" -ForegroundColor White
Write-Host "   - Change code: 'assets/logo_placeholder.webp' → 'assets/icon.png'" -ForegroundColor White
Write-Host ""
Write-Host "2. This will work but won't get the full performance benefits" -ForegroundColor Yellow
Write-Host ""
Write-Host "=== Quick Check ===" -ForegroundColor Cyan
Write-Host ""

$assetsPath = "..\assets"
$files = @{
    "logo.webp" = "Main logo (200x200, 85% quality)"
    "logo_placeholder.webp" = "Placeholder (50x50, 60% quality)"
    "logo.png" = "Original PNG (can be used temporarily)"
    "icon.png" = "Icon (can be used as placeholder)"
}

foreach ($file in $files.Keys) {
    $path = Join-Path $assetsPath $file
    if (Test-Path $path) {
        $size = [math]::Round(((Get-Item $path).Length / 1KB), 2)
        Write-Host "✓ $file exists (${size} KB)" -ForegroundColor Green
    } else {
        Write-Host "✗ $file missing" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Recommended: Use Online Converter ===" -ForegroundColor Green
Write-Host "It's the fastest and easiest method!" -ForegroundColor Green
Write-Host ""
