# Deploy to Vercel (Staging or Production)
# Usage: .\deploy-vercel.ps1 [staging|production]

param(
    [Parameter(Position=0)]
    [ValidateSet("staging", "production", "")]
    [string]$Environment = "staging"
)

# Stop on error
$ErrorActionPreference = "Stop"

# Display help if no argument provided
if ($Environment -eq "") {
    Write-Host ""
    Write-Host "Vercel Deployment Script" -ForegroundColor Cyan
    Write-Host "========================"
    Write-Host ""
    Write-Host "Usage: .\deploy-vercel.ps1 [staging|production]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\deploy-vercel.ps1 staging     # Deploy to staging (preview)"
    Write-Host "  .\deploy-vercel.ps1 production  # Deploy to production"
    Write-Host ""
    exit 0
}

# Set environment-specific variables
if ($Environment -eq "production") {
    $TraccarUrl = "https://your-production-traccar-server.com"
    $AllowInsecure = "false"
    $ProductionFlag = "--prod"
    $Target = "production"
} else {
    $TraccarUrl = "http://37.60.238.215:8082"
    $AllowInsecure = "true"
    $ProductionFlag = ""
    $Target = "staging (preview)"
}

Write-Host ""
Write-Host "Deploying to Vercel ($Environment)..." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor DarkGray
Write-Host ""

# Step 1: Build Flutter Web App
Write-Host "Building Flutter Web App for Vercel..." -ForegroundColor Yellow
Write-Host "   Environment: $Environment" -ForegroundColor Gray
Write-Host "   Traccar URL: $TraccarUrl" -ForegroundColor Gray
Write-Host ""

# Try WASM build first (optimized), fallback to JS if it fails
$WasmSuccess = $false
Write-Host "Attempting WASM build (optimized)..." -ForegroundColor Cyan

try {
    flutter build web --release --wasm `
        --dart-define=TRACCAR_BASE_URL=$TraccarUrl `
        --dart-define=ALLOW_INSECURE=$AllowInsecure `
        --dart-define=ENVIRONMENT=$Environment
    
    if ($LASTEXITCODE -eq 0) {
        $WasmSuccess = $true
        Write-Host ""
        Write-Host "WASM build successful!" -ForegroundColor Green
    }
} catch {
    Write-Host "WASM build failed, trying JS fallback..." -ForegroundColor Yellow
}

# Fallback to JS build if WASM failed
if (-not $WasmSuccess) {
    Write-Host ""
    Write-Host "Building with JavaScript (fallback)..." -ForegroundColor Yellow
    
    try {
        flutter build web --release `
            --dart-define=TRACCAR_BASE_URL=$TraccarUrl `
            --dart-define=ALLOW_INSECURE=$AllowInsecure `
            --dart-define=ENVIRONMENT=$Environment
        
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter build failed with exit code $LASTEXITCODE"
        }
        
        Write-Host ""
        Write-Host "JavaScript build complete!" -ForegroundColor Green
    } catch {
        Write-Host ""
        Write-Host "Build failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Step 2: Pre-deployment checks
Write-Host ""
Write-Host "Running pre-deployment checks..." -ForegroundColor Yellow

if (-not (Test-Path "build\web")) {
    Write-Host "Build directory not found!" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path "build\web\index.html")) {
    Write-Host "index.html not found in build!" -ForegroundColor Red
    exit 1
}

Write-Host "Pre-deployment checks passed!" -ForegroundColor Green

# Step 3: Deploy to Vercel
Write-Host ""
Write-Host "Deploying to Vercel ($Target)..." -ForegroundColor Yellow
Write-Host ""

try {
    if ($Environment -eq "production") {
        # Deploy to production
        vercel deploy build\web --prod --yes
    } else {
        # Deploy to preview (staging)
        vercel deploy build\web --yes
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Vercel deployment failed"
    }
} catch {
    Write-Host ""
    Write-Host "Deployment failed: $_" -ForegroundColor Red
    Write-Host "Make sure you have run vercel login and linked your project" -ForegroundColor Yellow
    exit 1
}

# Success message
Write-Host ""
Write-Host "================================================" -ForegroundColor DarkGray
Write-Host "Vercel deployment complete!" -ForegroundColor Green
Write-Host ""

# Display information
if ($Environment -eq "production") {
    Write-Host "Your app is live on production!" -ForegroundColor Cyan
    Write-Host "   Check your Vercel dashboard for the production URL" -ForegroundColor Gray
} else {
    Write-Host "Your preview deployment is live!" -ForegroundColor Cyan
    Write-Host "   Check the terminal output above for the preview URL" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "   1. Run smoke tests: npm run smoke-test" -ForegroundColor Gray
Write-Host "   2. Check service worker: Open DevTools -> Application -> Service Workers" -ForegroundColor Gray
Write-Host "   3. Test deep links: Visit /dashboard, /map directly" -ForegroundColor Gray
Write-Host "   4. Check logs: vercel logs" -ForegroundColor Gray
Write-Host ""
