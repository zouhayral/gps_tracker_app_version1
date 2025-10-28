# Deploy to Firebase Hosting (Staging or Production)
# Usage: .\deploy-firebase.ps1 [staging|production]

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
    Write-Host "Firebase Deployment Script" -ForegroundColor Cyan
    Write-Host "=========================="
    Write-Host ""
    Write-Host "Usage: .\deploy-firebase.ps1 [staging|production]" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\deploy-firebase.ps1 staging     # Deploy to staging environment"
    Write-Host "  .\deploy-firebase.ps1 production  # Deploy to production environment"
    Write-Host ""
    exit 0
}

# Configuration
$StagingProject = "app-gps-version"
$ProductionProject = "app-gps-version"

# Set environment-specific variables
if ($Environment -eq "production") {
    # Using same Traccar server for now (update when you have a production HTTPS server)
    $TraccarUrl = "http://37.60.238.215:8082"
    $AllowInsecure = "true"
    $FirebaseProject = $ProductionProject
    $Target = "production"
} else {
    $TraccarUrl = "http://37.60.238.215:8082"
    $AllowInsecure = "true"
    $FirebaseProject = $StagingProject
    $Target = "staging"
}

Write-Host ""
Write-Host "Deploying to Firebase Hosting ($Environment)..." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor DarkGray
Write-Host ""

# Step 0: Validate Firebase login and project
Write-Host "Checking Firebase authentication..." -ForegroundColor Yellow

try {
    $loginCheck = firebase login:list 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "Firebase not logged in. Logging in now..." -ForegroundColor Yellow
        firebase login
        
        if ($LASTEXITCODE -ne 0) {
            throw "Firebase login failed"
        }
    } else {
        Write-Host "Firebase authentication verified!" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Host "Firebase authentication failed: $_" -ForegroundColor Red
    Write-Host "Please run 'firebase login' manually and try again." -ForegroundColor Yellow
    exit 1
}

# Verify correct Firebase project is selected
Write-Host ""
Write-Host "Verifying Firebase project configuration..." -ForegroundColor Yellow

try {
    $currentProject = firebase use 2>&1 | Out-String
    
    if ($currentProject -notmatch "app-gps-version") {
        Write-Host "Switching to Firebase project: $FirebaseProject..." -ForegroundColor Cyan
        firebase use $FirebaseProject
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to switch to project: $FirebaseProject"
        }
        
        Write-Host "Switched to project: $FirebaseProject" -ForegroundColor Green
    } else {
        Write-Host "Project verified: $FirebaseProject" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Host "Failed to configure Firebase project: $_" -ForegroundColor Red
    Write-Host "Available projects:" -ForegroundColor Yellow
    firebase projects:list
    Write-Host ""
    Write-Host "Please ensure you have access to the '$FirebaseProject' project." -ForegroundColor Yellow
    exit 1
}

Write-Host ""

# Step 1: Build Flutter Web App
Write-Host "Building Flutter Web App..." -ForegroundColor Yellow
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

# Step 3: Deploy to Firebase
Write-Host ""
Write-Host "Deploying to Firebase Hosting..." -ForegroundColor Yellow

try {
    # Deploy to hosting (single site configuration)
    firebase deploy --only hosting
    
    if ($LASTEXITCODE -ne 0) {
        throw "Firebase deployment failed"
    }
    
    Write-Host ""
    Write-Host "Deployment to Firebase completed successfully!" -ForegroundColor Green
} catch {
    Write-Host ""
    Write-Host "Firebase deployment failed: $_" -ForegroundColor Red
    Write-Host "Please verify your project access and Firebase configuration." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Cyan
    Write-Host "   1. Check Firebase login: firebase login:list" -ForegroundColor Gray
    Write-Host "   2. List projects: firebase projects:list" -ForegroundColor Gray
    Write-Host "   3. View firebase.json: cat firebase.json" -ForegroundColor Gray
    exit 1
}

# Success message
Write-Host ""
Write-Host "================================================" -ForegroundColor DarkGray
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor DarkGray
Write-Host ""

# Display URLs
Write-Host "Your app is now live at:" -ForegroundColor Cyan
if ($Environment -eq "production") {
    Write-Host "   https://app-gps-version.web.app" -ForegroundColor White -BackgroundColor DarkGreen
    Write-Host "   https://app-gps-version.firebaseapp.com" -ForegroundColor Gray
} else {
    Write-Host "   https://app-gps-version.web.app" -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "   https://app-gps-version.firebaseapp.com" -ForegroundColor Gray
}
Write-Host ""

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "   1. Run smoke tests: npm run smoke-test" -ForegroundColor Gray
Write-Host "   2. Check service worker: Open DevTools -> Application -> Service Workers" -ForegroundColor Gray
Write-Host "   3. Test deep links: Visit /dashboard, /map directly" -ForegroundColor Gray
Write-Host "   4. Monitor logs: firebase functions:log" -ForegroundColor Gray
Write-Host ""
