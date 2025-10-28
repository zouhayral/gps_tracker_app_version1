# HTTPS Traccar Final Setup - Local Verification and Deployment
# Run this script on your Windows machine after HTTPS is set up on the server

param(
    [Parameter(Mandatory=$true)]
    [string]$TraccarDomain,  # e.g., traccar-gps.duckdns.org
    
    [Parameter(Mandatory=$false)]
    [string]$ServerIP = "37.60.238.215",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipVerification
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Traccar HTTPS Final Setup"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$TraccarUrl = "https://$TraccarDomain"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "   Traccar Domain: $TraccarDomain"
Write-Host "   Traccar URL: $TraccarUrl"
Write-Host "   Server IP: $ServerIP"
Write-Host ""

# Step 1: Verify HTTPS Endpoint Accessibility (from local machine)
if (-not $SkipVerification) {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Step 1: Verify HTTPS Endpoint"
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Testing HTTPS endpoint from your machine..." -ForegroundColor Yellow
    Write-Host "   URL: $TraccarUrl/api/server" -ForegroundColor Gray
    Write-Host ""
    
    try {
        $response = Invoke-WebRequest -Uri "$TraccarUrl/api/server" -Method GET -UseBasicParsing -ErrorAction Stop
        Write-Host "   ✅ HTTPS endpoint accessible!" -ForegroundColor Green
        Write-Host "   Status: $($response.StatusCode) $($response.StatusDescription)" -ForegroundColor Gray
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 401) {
            Write-Host "   ✅ HTTPS endpoint accessible!" -ForegroundColor Green
            Write-Host "   Status: 401 Unauthorized (expected for /api/server without auth)" -ForegroundColor Gray
        } else {
            Write-Host "   ❌ HTTPS endpoint test failed!" -ForegroundColor Red
            Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "   Troubleshooting:" -ForegroundColor Yellow
            Write-Host "   1. Verify DNS: nslookup $TraccarDomain" -ForegroundColor Gray
            Write-Host "   2. Check server HTTPS: ssh root@$ServerIP 'sudo systemctl status nginx'" -ForegroundColor Gray
            Write-Host "   3. Test from server: ssh root@$ServerIP 'curl -I https://$TraccarDomain/api/server'" -ForegroundColor Gray
            Write-Host ""
            
            $continue = Read-Host "Continue anyway? (y/n)"
            if ($continue -ne "y") {
                exit 1
            }
        }
    }
    
    Write-Host ""
    
    # Check SSL Certificate
    Write-Host "Checking SSL certificate..." -ForegroundColor Yellow
    try {
        $request = [System.Net.WebRequest]::Create("$TraccarUrl/api/server")
        $response = $request.GetResponse()
        $cert = $request.ServicePoint.Certificate
        $cert2 = [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert
        
        Write-Host "   ✅ SSL Certificate valid!" -ForegroundColor Green
        Write-Host "   Issued to: $($cert2.Subject)" -ForegroundColor Gray
        Write-Host "   Issued by: $($cert2.Issuer)" -ForegroundColor Gray
        Write-Host "   Valid from: $($cert2.NotBefore)" -ForegroundColor Gray
        Write-Host "   Valid until: $($cert2.NotAfter)" -ForegroundColor Gray
        
        $daysLeft = ($cert2.NotAfter - (Get-Date)).Days
        if ($daysLeft -lt 30) {
            Write-Host "   ⚠️  Certificate expires in $daysLeft days!" -ForegroundColor Yellow
        } else {
            Write-Host "   ✅ Certificate valid for $daysLeft more days" -ForegroundColor Green
        }
        
        $response.Close()
    } catch {
        Write-Host "   ⚠️  Could not verify SSL certificate" -ForegroundColor Yellow
        Write-Host "   Error: $($_.Exception.Message)" -ForegroundColor Gray
    }
    
    Write-Host ""
}

# Step 2: Update Local Configuration Files
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Step 2: Update Local Configuration"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Backup existing files
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
if (Test-Path ".env.production") {
    Copy-Item ".env.production" ".env.production.backup-$timestamp"
    Write-Host "   ✅ Backed up .env.production" -ForegroundColor Green
}
if (Test-Path "deploy-firebase.ps1") {
    Copy-Item "deploy-firebase.ps1" "deploy-firebase.ps1.backup-$timestamp"
    Write-Host "   ✅ Backed up deploy-firebase.ps1" -ForegroundColor Green
}
Write-Host ""

# Update .env.production
Write-Host "Updating .env.production..." -ForegroundColor Yellow
$envContent = @"
# Production Environment Configuration
# Updated for HTTPS Traccar backend on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
TRACCAR_BASE_URL=$TraccarUrl
ALLOW_INSECURE=false
"@

Set-Content -Path ".env.production" -Value $envContent -Encoding UTF8
Write-Host "   ✅ Updated .env.production" -ForegroundColor Green
Write-Host "   TRACCAR_BASE_URL=$TraccarUrl" -ForegroundColor Gray
Write-Host "   ALLOW_INSECURE=false" -ForegroundColor Gray
Write-Host ""

# Update deploy-firebase.ps1
Write-Host "Updating deploy-firebase.ps1..." -ForegroundColor Yellow

$deployScript = Get-Content "deploy-firebase.ps1" -Raw

# Update production TraccarUrl
$deployScript = $deployScript -replace 'if \(\$Environment -eq "production"\) \{[^}]*\$TraccarUrl\s*=\s*"[^"]*"', "if (`$Environment -eq `"production`") {`n    # HTTPS Traccar server (updated $(Get-Date -Format 'yyyy-MM-dd'))`n    `$TraccarUrl = `"$TraccarUrl`""

# Update AllowInsecure for production
$deployScript = $deployScript -replace '(\$TraccarUrl\s*=\s*"[^"]*"[^$]*)\$AllowInsecure\s*=\s*"true"', "`$1`$AllowInsecure = `"false`""

Set-Content -Path "deploy-firebase.ps1" -Value $deployScript -Encoding UTF8 -NoNewline
Write-Host "   ✅ Updated deploy-firebase.ps1" -ForegroundColor Green
Write-Host "   Production TraccarUrl: $TraccarUrl" -ForegroundColor Gray
Write-Host "   Production AllowInsecure: false" -ForegroundColor Gray
Write-Host ""

# Step 3: Display Summary
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Configuration Summary"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Updated Files:" -ForegroundColor Yellow
Write-Host "   ✅ .env.production" -ForegroundColor Green
Write-Host "      TRACCAR_BASE_URL=$TraccarUrl" -ForegroundColor Gray
Write-Host "      ALLOW_INSECURE=false" -ForegroundColor Gray
Write-Host ""
Write-Host "   ✅ deploy-firebase.ps1" -ForegroundColor Green
Write-Host "      Production uses: $TraccarUrl" -ForegroundColor Gray
Write-Host "      SSL verification: Enabled" -ForegroundColor Gray
Write-Host ""

Write-Host "Backup Files Created:" -ForegroundColor Yellow
Write-Host "   .env.production.backup-$timestamp" -ForegroundColor Gray
Write-Host "   deploy-firebase.ps1.backup-$timestamp" -ForegroundColor Gray
Write-Host ""

# Step 4: Prompt for Deployment
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Step 3: Deploy to Firebase"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$deploy = Read-Host "Deploy Flutter app to Firebase now? (y/n)"

if ($deploy -eq "y" -or $deploy -eq "Y") {
    Write-Host ""
    Write-Host "Starting deployment..." -ForegroundColor Yellow
    Write-Host ""
    
    & .\deploy-firebase.ps1 production
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "=========================================" -ForegroundColor Green
        Write-Host "Deployment Successful!"
        Write-Host "=========================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎉 Your Flutter Web app now uses HTTPS!" -ForegroundColor Green
        Write-Host ""
        Write-Host "✅ No more mixed content warnings" -ForegroundColor Green
        Write-Host "✅ Secure communication with Traccar" -ForegroundColor Green
        Write-Host "✅ Production-ready deployment" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Cyan
        Write-Host "   1. Test at: https://app-gps-version.web.app" -ForegroundColor White
        Write-Host "   2. Open DevTools → Network tab" -ForegroundColor White
        Write-Host "   3. Try to login" -ForegroundColor White
        Write-Host "   4. Verify requests go to: $TraccarUrl" -ForegroundColor White
        Write-Host "   5. Check for secure lock icon 🔒" -ForegroundColor White
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "❌ Deployment failed!" -ForegroundColor Red
        Write-Host "Check the output above for errors." -ForegroundColor Yellow
        Write-Host ""
    }
} else {
    Write-Host ""
    Write-Host "Deployment skipped." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To deploy later, run:" -ForegroundColor Cyan
    Write-Host "   .\deploy-firebase.ps1 production" -ForegroundColor White
    Write-Host ""
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
