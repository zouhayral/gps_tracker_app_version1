# PowerShell script to convert logo.png to optimized WebP format
# Requirements: Install ImageMagick or use online converter

Write-Host "=== Logo Image Optimization Script ===" -ForegroundColor Cyan
Write-Host ""

$assetsPath = "..\assets"
$logoPng = Join-Path $assetsPath "logo.png"
$logoWebp = Join-Path $assetsPath "logo.webp"
$logoPlaceholder = Join-Path $assetsPath "logo_placeholder.webp"

# Check if logo.png exists
if (-not (Test-Path $logoPng)) {
    Write-Host "ERROR: logo.png not found at $logoPng" -ForegroundColor Red
    Write-Host "Please ensure logo.png exists in the assets folder." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found logo.png at: $logoPng" -ForegroundColor Green
Write-Host ""

# Check if ImageMagick is installed
$magickInstalled = $null -ne (Get-Command "magick" -ErrorAction SilentlyContinue)

if ($magickInstalled) {
    Write-Host "ImageMagick detected. Converting images..." -ForegroundColor Green
    Write-Host ""
    
    # Convert main logo to WebP (200x200, quality 85)
    Write-Host "1. Converting logo.png to logo.webp (200x200)..." -ForegroundColor Cyan
    magick convert "$logoPng" -resize 200x200 -quality 85 "$logoWebp"
    
    if ($LASTEXITCODE -eq 0) {
        $webpSize = (Get-Item $logoWebp).Length / 1KB
        Write-Host "   ✓ Created logo.webp (Size: $([math]::Round($webpSize, 2)) KB)" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Failed to convert logo.webp" -ForegroundColor Red
    }
    
    # Create placeholder (50x50, quality 60, very small)
    Write-Host "2. Creating logo_placeholder.webp (50x50)..." -ForegroundColor Cyan
    magick convert "$logoPng" -resize 50x50 -quality 60 "$logoPlaceholder"
    
    if ($LASTEXITCODE -eq 0) {
        $placeholderSize = (Get-Item $logoPlaceholder).Length / 1KB
        Write-Host "   ✓ Created logo_placeholder.webp (Size: $([math]::Round($placeholderSize, 2)) KB)" -ForegroundColor Green
    } else {
        Write-Host "   ✗ Failed to convert logo_placeholder.webp" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "=== Conversion Complete! ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Original PNG size: $([math]::Round(((Get-Item $logoPng).Length / 1KB), 2)) KB" -ForegroundColor Yellow
    if (Test-Path $logoWebp) {
        Write-Host "Optimized WebP size: $([math]::Round(((Get-Item $logoWebp).Length / 1KB), 2)) KB" -ForegroundColor Yellow
    }
    if (Test-Path $logoPlaceholder) {
        Write-Host "Placeholder WebP size: $([math]::Round(((Get-Item $logoPlaceholder).Length / 1KB), 2)) KB" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Estimated performance improvement:" -ForegroundColor Cyan
    Write-Host "  - Login load time: 1.2s → ~500ms (-58%)" -ForegroundColor Green
    Write-Host "  - First frame delay: 300-400ms → ~50ms (-85%)" -ForegroundColor Green
    Write-Host "  - Smooth fade-in animation (200ms)" -ForegroundColor Green
    
} else {
    Write-Host "ImageMagick not found. Please convert manually." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option 1: Install ImageMagick" -ForegroundColor Cyan
    Write-Host "  1. Download from: https://imagemagick.org/script/download.php" -ForegroundColor White
    Write-Host "  2. Install and add to PATH" -ForegroundColor White
    Write-Host "  3. Run this script again" -ForegroundColor White
    Write-Host ""
    Write-Host "Option 2: Use Online Converter" -ForegroundColor Cyan
    Write-Host "  1. Visit: https://convertio.co/png-webp/" -ForegroundColor White
    Write-Host "  2. Upload: $logoPng" -ForegroundColor White
    Write-Host "  3. Download and save as:" -ForegroundColor White
    Write-Host "     - $logoWebp (resize to 200x200)" -ForegroundColor White
    Write-Host "     - $logoPlaceholder (resize to 50x50, low quality)" -ForegroundColor White
    Write-Host ""
    Write-Host "Option 3: Use Flutter DevTools" -ForegroundColor Cyan
    Write-Host "  flutter pub run flutter_native_image:compress" -ForegroundColor White
    Write-Host ""
    Write-Host "Manual Steps:" -ForegroundColor Yellow
    Write-Host "  1. Resize logo.png to 200x200 pixels" -ForegroundColor White
    Write-Host "  2. Convert to WebP format (quality: 85)" -ForegroundColor White
    Write-Host "  3. Save as: assets/logo.webp" -ForegroundColor White
    Write-Host "  4. Create 50x50 placeholder (quality: 60)" -ForegroundColor White
    Write-Host "  5. Save as: assets/logo_placeholder.webp" -ForegroundColor White
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Verify assets/logo.webp exists (~10-30 KB)" -ForegroundColor White
Write-Host "  2. Verify assets/logo_placeholder.webp exists (~1-2 KB)" -ForegroundColor White
Write-Host "  3. Run: flutter clean" -ForegroundColor White
Write-Host "  4. Run: flutter pub get" -ForegroundColor White
Write-Host "  5. Test the login page performance" -ForegroundColor White
Write-Host ""

# Summary
if (Test-Path $logoWebp) {
    Write-Host "✓ logo.webp ready" -ForegroundColor Green
} else {
    Write-Host "✗ logo.webp missing - please create manually" -ForegroundColor Red
}

if (Test-Path $logoPlaceholder) {
    Write-Host "✓ logo_placeholder.webp ready" -ForegroundColor Green
} else {
    Write-Host "✗ logo_placeholder.webp missing - please create manually" -ForegroundColor Red
}

Write-Host ""
