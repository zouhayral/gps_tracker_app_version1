#!/bin/bash
#
# HTTPS Traccar Verification Script
# Run this on your Traccar server to verify HTTPS setup
#
# Usage: bash verify-traccar-https.sh YOUR_DOMAIN

set -e

DOMAIN=${1:-"traccar-gps.duckdns.org"}

echo "========================================="
echo "Traccar HTTPS Verification"
echo "========================================="
echo ""
echo "Domain: $DOMAIN"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  Not running as root. Some checks may fail."
    echo "   Run with: sudo bash verify-traccar-https.sh"
    echo ""
fi

# 1. Check Nginx Status
echo "1. Checking Nginx Status..."
echo "   --------------------------------"
if systemctl is-active --quiet nginx; then
    echo "   ✅ Nginx is running"
    systemctl status nginx --no-pager | head -n 3
else
    echo "   ❌ Nginx is NOT running"
    echo "   Start with: sudo systemctl start nginx"
    exit 1
fi
echo ""

# 2. Check SSL Certificates
echo "2. Checking SSL Certificates..."
echo "   --------------------------------"
if command -v certbot &> /dev/null; then
    if certbot certificates 2>&1 | grep -q "No certificates found"; then
        echo "   ❌ No SSL certificates found"
        echo "   Run setup script first!"
        exit 1
    else
        echo "   ✅ SSL Certificates found:"
        certbot certificates 2>&1 | grep -E "(Certificate Name|Domains|Expiry Date)" | sed 's/^/   /'
    fi
else
    echo "   ⚠️  Certbot not installed"
fi
echo ""

# 3. Check Certificate Expiration
echo "3. Checking Certificate Expiration..."
echo "   --------------------------------"
CERT_FILE="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
if [ -f "$CERT_FILE" ]; then
    EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -lt 30 ]; then
        echo "   ⚠️  Certificate expires in $DAYS_LEFT days!"
        echo "   Renew with: sudo certbot renew"
    else
        echo "   ✅ Certificate valid for $DAYS_LEFT more days"
    fi
    echo "   Expires: $EXPIRY"
else
    echo "   ❌ Certificate file not found: $CERT_FILE"
fi
echo ""

# 4. Check Nginx Configuration
echo "4. Checking Nginx Configuration..."
echo "   --------------------------------"
if nginx -t 2>&1 | grep -q "syntax is ok"; then
    echo "   ✅ Nginx configuration is valid"
else
    echo "   ❌ Nginx configuration has errors:"
    nginx -t 2>&1 | sed 's/^/   /'
    exit 1
fi
echo ""

# 5. Check Port Bindings
echo "5. Checking Port Bindings..."
echo "   --------------------------------"
if netstat -tulpn 2>/dev/null | grep -q ":443.*nginx"; then
    echo "   ✅ Nginx listening on port 443 (HTTPS)"
else
    echo "   ❌ Nginx NOT listening on port 443"
fi

if netstat -tulpn 2>/dev/null | grep -q ":80.*nginx"; then
    echo "   ✅ Nginx listening on port 80 (HTTP redirect)"
else
    echo "   ⚠️  Nginx NOT listening on port 80"
fi

if netstat -tulpn 2>/dev/null | grep -q ":8082"; then
    LISTENING=$(netstat -tulpn 2>/dev/null | grep ":8082" | awk '{print $4}')
    if [[ $LISTENING == "127.0.0.1:8082" ]]; then
        echo "   ✅ Traccar listening on localhost:8082 (secure)"
    else
        echo "   ⚠️  Traccar listening on $LISTENING (should be localhost only)"
    fi
else
    echo "   ❌ Traccar NOT listening on port 8082"
fi
echo ""

# 6. Check Traccar Status
echo "6. Checking Traccar Status..."
echo "   --------------------------------"
if systemctl is-active --quiet traccar; then
    echo "   ✅ Traccar is running"
    systemctl status traccar --no-pager | head -n 3
else
    echo "   ❌ Traccar is NOT running"
    echo "   Start with: sudo systemctl start traccar"
fi
echo ""

# 7. Test HTTPS Endpoint (Internal)
echo "7. Testing HTTPS Endpoint (from server)..."
echo "   --------------------------------"
if command -v curl &> /dev/null; then
    echo "   Testing: https://$DOMAIN/api/server"
    
    RESPONSE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$DOMAIN/api/server" 2>&1)
    
    if [ "$RESPONSE" == "200" ]; then
        echo "   ✅ HTTPS endpoint accessible (200 OK)"
    elif [ "$RESPONSE" == "401" ]; then
        echo "   ✅ HTTPS endpoint accessible (401 Unauthorized - expected for /api/server)"
    else
        echo "   ⚠️  HTTPS endpoint returned: $RESPONSE"
        echo "   Full test:"
        curl -I -k "https://$DOMAIN/api/server" 2>&1 | sed 's/^/   /'
    fi
else
    echo "   ⚠️  curl not installed"
fi
echo ""

# 8. Test HTTP to HTTPS Redirect
echo "8. Testing HTTP → HTTPS Redirect..."
echo "   --------------------------------"
if command -v curl &> /dev/null; then
    REDIRECT=$(curl -s -o /dev/null -w "%{http_code}:%{redirect_url}" "http://$DOMAIN/api/server")
    HTTP_CODE=$(echo $REDIRECT | cut -d: -f1)
    REDIRECT_URL=$(echo $REDIRECT | cut -d: -f2-)
    
    if [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ]; then
        if [[ $REDIRECT_URL == https://* ]]; then
            echo "   ✅ HTTP redirects to HTTPS ($HTTP_CODE)"
            echo "   Redirects to: $REDIRECT_URL"
        else
            echo "   ⚠️  HTTP redirects but not to HTTPS: $REDIRECT_URL"
        fi
    else
        echo "   ⚠️  No redirect found (HTTP $HTTP_CODE)"
    fi
else
    echo "   ⚠️  curl not installed"
fi
echo ""

# 9. Check CORS Headers
echo "9. Checking CORS Headers..."
echo "   --------------------------------"
if command -v curl &> /dev/null; then
    CORS=$(curl -k -s -I "https://$DOMAIN/api/server" | grep -i "access-control")
    if [ -n "$CORS" ]; then
        echo "   ✅ CORS headers found:"
        echo "$CORS" | sed 's/^/   /'
    else
        echo "   ⚠️  No CORS headers found"
        echo "   This may cause issues with web app authentication"
    fi
else
    echo "   ⚠️  curl not installed"
fi
echo ""

# 10. Check Firewall Rules
echo "10. Checking Firewall..."
echo "   --------------------------------"
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        echo "   ✅ UFW is active"
        if ufw status | grep -q "443"; then
            echo "   ✅ Port 443 (HTTPS) is allowed"
        else
            echo "   ❌ Port 443 (HTTPS) is NOT allowed"
            echo "   Allow with: sudo ufw allow 443/tcp"
        fi
        if ufw status | grep -q "80"; then
            echo "   ✅ Port 80 (HTTP) is allowed"
        else
            echo "   ⚠️  Port 80 (HTTP) is NOT allowed (needed for cert renewal)"
        fi
    else
        echo "   ⚠️  UFW is not active"
    fi
else
    echo "   ⚠️  UFW not installed"
fi
echo ""

# Summary
echo "========================================="
echo "Verification Summary"
echo "========================================="
echo ""

# Count checks
PASSED=0
FAILED=0

# Nginx running
if systemctl is-active --quiet nginx; then ((PASSED++)); else ((FAILED++)); fi

# Traccar running
if systemctl is-active --quiet traccar; then ((PASSED++)); else ((FAILED++)); fi

# Certificate exists
if [ -f "$CERT_FILE" ]; then ((PASSED++)); else ((FAILED++)); fi

# Nginx config valid
if nginx -t 2>&1 | grep -q "syntax is ok"; then ((PASSED++)); else ((FAILED++)); fi

echo "✅ Passed: $PASSED checks"
echo "❌ Failed: $FAILED checks"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "🎉 All checks passed! Your Traccar HTTPS setup is ready!"
    echo ""
    echo "📝 Next Steps:"
    echo "   1. Update .env.production: TRACCAR_BASE_URL=https://$DOMAIN"
    echo "   2. Update deploy-firebase.ps1 with same URL"
    echo "   3. Redeploy Flutter app: .\deploy-firebase.ps1 production"
    echo "   4. Test login at: https://app-gps-version.web.app"
    echo ""
else
    echo "⚠️  Some checks failed. Review the output above and fix issues."
    echo ""
    echo "📚 Common fixes:"
    echo "   - Nginx not running: sudo systemctl start nginx"
    echo "   - No certificate: sudo certbot certonly --nginx -d $DOMAIN"
    echo "   - Traccar not running: sudo systemctl start traccar"
    echo "   - Firewall: sudo ufw allow 443/tcp"
    echo ""
fi

echo "========================================="
echo ""

# Log file
LOG_FILE="/var/log/traccar-https-verification.log"
if [ -w /var/log ]; then
    echo "Verification run on $(date)" >> "$LOG_FILE"
    echo "Domain: $DOMAIN" >> "$LOG_FILE"
    echo "Passed: $PASSED | Failed: $FAILED" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
fi
