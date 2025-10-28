# Deploy Server Configuration Files to Traccar Server
# Usage: .\prepare-server-configs.ps1

param(
    [Parameter(Mandatory=$false)]
    [string]$ServerIP = "37.60.238.215",
    
    [Parameter(Mandatory=$false)]
    [string]$Username = "root",
    
    [Parameter(Mandatory=$false)]
    [string]$DomainName = ""
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Traccar HTTPS Setup - File Preparation"
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# Check if server-configs directory exists
if (-not (Test-Path "server-configs")) {
    Write-Host "Error: server-configs directory not found!" -ForegroundColor Red
    Write-Host "Run this script from the project root directory." -ForegroundColor Yellow
    exit 1
}

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "   Server IP: $ServerIP"
Write-Host "   Username: $Username"
Write-Host "   Files: server-configs\"
Write-Host ""

# Check for SCP (Windows 10 version 1809+ includes OpenSSH)
$scpAvailable = $null -ne (Get-Command scp -ErrorAction SilentlyContinue)

if (-not $scpAvailable) {
    Write-Host "Warning: SCP not found. You'll need to manually copy files." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "   1. Install OpenSSH Client:"
    Write-Host "      Settings -> Apps -> Optional Features -> Add -> OpenSSH Client"
    Write-Host ""
    Write-Host "   2. Use WinSCP (GUI tool): https://winscp.net/"
    Write-Host ""
    Write-Host "   3. Manually copy files using your preferred method"
    Write-Host ""
} else {
    Write-Host "SCP found: Files can be uploaded automatically" -ForegroundColor Green
    Write-Host ""
}

# Display domain setup instructions
if ($DomainName -eq "") {
    Write-Host "=================================================" -ForegroundColor Yellow
    Write-Host "IMPORTANT: Domain Setup Required"
    Write-Host "=================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Before running the setup script on the server, you need a domain name." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Option 1: Use your own domain" -ForegroundColor White
    Write-Host "   - Buy a domain (e.g., from Namecheap, GoDaddy, Cloudflare)"
    Write-Host "   - Create DNS A record: traccar.yourdomain.com -> $ServerIP"
    Write-Host "   - Wait for DNS propagation (5-30 minutes)"
    Write-Host ""
    Write-Host "Option 2: Free subdomain services" -ForegroundColor White
    Write-Host "   - DuckDNS: https://www.duckdns.org (e.g., traccar-gps.duckdns.org)"
    Write-Host "   - No-IP: https://www.noip.com"
    Write-Host "   - Cloudflare: Free tier with custom domain"
    Write-Host ""
    Write-Host "Option 3: Test with IP (not recommended for production)" -ForegroundColor White
    Write-Host "   - Some Let's Encrypt clients work with IP addresses"
    Write-Host "   - Users will see certificate warnings"
    Write-Host ""
}

# List files to be uploaded
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Files Ready for Upload"
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

$files = @(
    "server-configs/setup-https-traccar.sh",
    "server-configs/setup-traccar-direct-ssl.sh",
    "server-configs/nginx-traccar.conf",
    "server-configs/docker-compose.yml",
    "server-configs/README-HTTPS-SETUP.md"
)

foreach ($file in $files) {
    if (Test-Path $file) {
        $size = (Get-Item $file).Length
        Write-Host "   $file" -NoNewline
        Write-Host " ($([math]::Round($size/1KB, 1)) KB)" -ForegroundColor Gray
    } else {
        Write-Host "   $file [MISSING]" -ForegroundColor Red
    }
}

Write-Host ""

# Upload option
if ($scpAvailable) {
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "Upload Files"
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $upload = Read-Host "Upload files now? (y/n)"
    
    if ($upload -eq "y" -or $upload -eq "Y") {
        Write-Host ""
        Write-Host "Uploading files to ${Username}@${ServerIP}:/root/..." -ForegroundColor Yellow
        
        try {
            # Create remote directory
            ssh "${Username}@${ServerIP}" "mkdir -p /root/traccar-https-setup"
            
            # Upload files
            foreach ($file in $files) {
                if (Test-Path $file) {
                    Write-Host "   Uploading $(Split-Path $file -Leaf)..." -NoNewline
                    scp $file "${Username}@${ServerIP}:/root/traccar-https-setup/"
                    Write-Host " Done" -ForegroundColor Green
                }
            }
            
            Write-Host ""
            Write-Host "Files uploaded successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Next Steps:" -ForegroundColor Cyan
            Write-Host "   1. SSH to server: ssh ${Username}@${ServerIP}"
            Write-Host "   2. Go to directory: cd /root/traccar-https-setup"
            Write-Host "   3. Make executable: chmod +x *.sh"
            Write-Host "   4. Run setup: sudo bash setup-https-traccar.sh"
            Write-Host ""
            
        } catch {
            Write-Host " Failed" -ForegroundColor Red
            Write-Host ""
            Write-Host "Error: $_" -ForegroundColor Red
            Write-Host ""
            Write-Host "Troubleshooting:" -ForegroundColor Yellow
            Write-Host "   1. Check SSH access: ssh ${Username}@${ServerIP}"
            Write-Host "   2. Verify server IP is correct"
            Write-Host "   3. Ensure SSH key is set up or password is ready"
            Write-Host ""
        }
    }
}

# Display manual instructions
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "Manual Upload Instructions (if needed)"
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Using WinSCP:" -ForegroundColor White
Write-Host "   1. Open WinSCP"
Write-Host "   2. Connect to: ${ServerIP} as ${Username}"
Write-Host "   3. Upload server-configs\ folder to: /root/traccar-https-setup/"
Write-Host ""
Write-Host "Using Command Line:" -ForegroundColor White
Write-Host "   scp -r server-configs ${Username}@${ServerIP}:/root/traccar-https-setup/"
Write-Host ""

# Next steps
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "After Upload: Server Setup"
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. SSH to your server:" -ForegroundColor Yellow
Write-Host "   ssh ${Username}@${ServerIP}"
Write-Host ""
Write-Host "2. Navigate to setup directory:" -ForegroundColor Yellow
Write-Host "   cd /root/traccar-https-setup"
Write-Host ""
Write-Host "3. Make scripts executable:" -ForegroundColor Yellow
Write-Host "   chmod +x *.sh"
Write-Host ""
Write-Host "4. Run the setup script:" -ForegroundColor Yellow
Write-Host "   sudo bash setup-https-traccar.sh"
Write-Host ""
Write-Host "5. Follow the prompts:" -ForegroundColor Yellow
Write-Host "   - Enter your domain name (e.g., traccar.yourdomain.com)"
Write-Host "   - Enter your email for SSL certificate notifications"
Write-Host ""
Write-Host "6. After successful setup, update Flutter app:" -ForegroundColor Yellow
Write-Host "   - Edit .env.production with: TRACCAR_BASE_URL=https://your-domain.com"
Write-Host "   - Edit deploy-firebase.ps1 with same URL"
Write-Host "   - Redeploy: .\deploy-firebase.ps1 production"
Write-Host ""

Write-Host "=================================================" -ForegroundColor Green
Write-Host "Preparation Complete!"
Write-Host "=================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Read server-configs/README-HTTPS-SETUP.md for detailed guide." -ForegroundColor Cyan
Write-Host ""
