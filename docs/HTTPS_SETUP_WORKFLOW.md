# 🔐 HTTPS Setup - Complete Workflow

This guide walks you through the complete process of enabling HTTPS for your Traccar backend and updating your Flutter web app.

---

## 🎯 Goal

Enable secure HTTPS communication between:
- **Frontend**: https://app-gps-version.web.app (Flutter Web - HTTPS ✅)
- **Backend**: https://your-domain.com (Traccar - HTTP ❌ → HTTPS ✅)

---

## 📋 Prerequisites

- [ ] Traccar server running at `37.60.238.215:8082`
- [ ] SSH access to the server
- [ ] Domain name (or use free service like DuckDNS)
- [ ] Flutter web app deployed to Firebase

---

## 🚀 Step-by-Step Guide

### Step 1: Get a Domain Name

#### Option A: Free Subdomain (DuckDNS - Recommended for Testing)

1. Go to https://www.duckdns.org
2. Sign in with your account
3. Create a subdomain (e.g., `traccar-gps`)
4. Point it to your server IP: `37.60.238.215`
5. Your domain: `traccar-gps.duckdns.org`

#### Option B: Own Domain

1. Buy domain from registrar (Namecheap, GoDaddy, Cloudflare, etc.)
2. Add DNS A record:
   ```
   traccar.yourdomain.com → 37.60.238.215
   ```
3. Wait 5-30 minutes for DNS propagation

**Verify DNS:**
```bash
nslookup traccar-gps.duckdns.org
# Should return: 37.60.238.215
```

---

### Step 2: Upload Setup Scripts to Server

On your **Windows machine**:

```powershell
# Navigate to project directory
cd "C:\Users\Acer\Desktop\notification step\my_app_gps_version2"

# Run preparation script
.\prepare-server-configs.ps1

# When prompted, allow upload (if you have SSH/SCP configured)
# OR manually upload via WinSCP
```

**Manual upload with WinSCP:**
1. Open WinSCP
2. Connect to: `37.60.238.215` as `root`
3. Upload `server-configs/` folder to `/root/traccar-https-setup/`

---

### Step 3: Run HTTPS Setup on Server

SSH to your server:

```bash
ssh root@37.60.238.215
```

Navigate to setup directory:

```bash
cd /root/traccar-https-setup
chmod +x *.sh
```

**Run the setup script:**

```bash
sudo bash setup-https-traccar.sh
```

**Follow the prompts:**
```
Enter your domain name: traccar-gps.duckdns.org
Enter your email: your-email@example.com
Continue? (y/n) y
```

The script will:
- ✅ Install Nginx
- ✅ Install Certbot
- ✅ Obtain SSL certificate from Let's Encrypt
- ✅ Configure Nginx as reverse proxy
- ✅ Add CORS headers
- ✅ Setup auto-renewal
- ✅ Start services

**Expected output:**
```
✅ Setup Complete!
================================================
HTTPS URL: https://traccar-gps.duckdns.org
SSL Certificate: Valid
Auto-renewal: Enabled
Nginx Status: Running
```

---

### Step 4: Verify HTTPS Setup on Server

Run verification script:

```bash
bash verify-traccar-https.sh traccar-gps.duckdns.org
```

**Expected output:**
```
✅ Nginx is running
✅ SSL Certificates found
✅ Certificate valid for 89 days
✅ Nginx configuration is valid
✅ Nginx listening on port 443 (HTTPS)
✅ Traccar listening on localhost:8082 (secure)
✅ Traccar is running
✅ HTTPS endpoint accessible (200 OK or 401 Unauthorized)
✅ HTTP redirects to HTTPS
...
🎉 All checks passed! Your Traccar HTTPS setup is ready!
```

**Test HTTPS endpoint:**
```bash
curl -I https://traccar-gps.duckdns.org/api/server
```

Should return:
```
HTTP/2 200
# or
HTTP/2 401 (Unauthorized - also OK)
```

---

### Step 5: Update Flutter App Configuration (Local Machine)

On your **Windows machine**, run the finalization script:

```powershell
# Navigate to project directory
cd "C:\Users\Acer\Desktop\notification step\my_app_gps_version2"

# Run finalization script with your domain
.\finalize-https-setup.ps1 -TraccarDomain "traccar-gps.duckdns.org"
```

**The script will:**
1. ✅ Verify HTTPS endpoint is accessible from your machine
2. ✅ Check SSL certificate validity
3. ✅ Backup existing configuration files
4. ✅ Update `.env.production` with HTTPS URL
5. ✅ Update `deploy-firebase.ps1` with HTTPS URL
6. ✅ Prompt to deploy to Firebase

**When prompted:**
```
Deploy Flutter app to Firebase now? (y/n) y
```

---

### Step 6: Verify Deployment

1. **Open your app**: https://app-gps-version.web.app

2. **Open Browser DevTools** (F12)

3. **Check Network Tab:**
   - Requests should go to `https://traccar-gps.duckdns.org`
   - SSL lock icon should be visible 🔒
   - No mixed content warnings

4. **Try to Login:**
   - Enter Traccar credentials
   - Login should succeed
   - No `connectionError` or CORS issues

5. **Check Console Tab:**
   - No errors related to mixed content
   - No SSL warnings
   - No CORS errors

---

## ✅ Verification Checklist

### Server Side:
- [ ] Nginx installed and running
- [ ] SSL certificate obtained and valid
- [ ] Port 443 open in firewall
- [ ] HTTP (port 80) redirects to HTTPS (port 443)
- [ ] Traccar accessible only on localhost:8082
- [ ] HTTPS endpoint returns 200 or 401: `curl -I https://traccar-gps.duckdns.org/api/server`
- [ ] Auto-renewal configured: `sudo certbot renew --dry-run`

### Client Side (Flutter App):
- [ ] `.env.production` has HTTPS URL
- [ ] `deploy-firebase.ps1` uses HTTPS URL
- [ ] App deployed successfully
- [ ] No build errors
- [ ] Firebase hosting updated

### Browser Testing:
- [ ] App loads at https://app-gps-version.web.app
- [ ] DevTools shows HTTPS requests
- [ ] SSL lock icon visible
- [ ] No mixed content warnings
- [ ] Login succeeds
- [ ] Real-time updates work (WebSocket over WSS)

---

## 🐛 Troubleshooting

### Issue: "SSL certificate not found"

**Solution:**
```bash
# Obtain certificate manually
sudo certbot certonly --nginx -d traccar-gps.duckdns.org

# Restart Nginx
sudo systemctl restart nginx
```

### Issue: "Connection refused" or "ERR_CONNECTION_REFUSED"

**Check:**
1. Nginx is running: `sudo systemctl status nginx`
2. Port 443 is open: `sudo ufw allow 443/tcp`
3. DNS resolves: `nslookup traccar-gps.duckdns.org`

### Issue: "Mixed content blocked"

**This means:**
- Your Flutter app still uses HTTP URL

**Solution:**
```powershell
# Verify .env.production
Get-Content .env.production
# Should show: TRACCAR_BASE_URL=https://...

# Redeploy
.\deploy-firebase.ps1 production
```

### Issue: "CORS error"

**Solution on server:**
```bash
# Check Nginx config has CORS headers
grep -A 5 "Access-Control-Allow-Origin" /etc/nginx/sites-available/traccar

# If missing, add to Nginx config:
add_header Access-Control-Allow-Origin "https://app-gps-version.web.app" always;

# Reload Nginx
sudo systemctl reload nginx
```

### Issue: "Certificate expires soon"

**Solution:**
```bash
# Renew certificate
sudo certbot renew

# Restart Nginx
sudo systemctl restart nginx

# Test auto-renewal
sudo certbot renew --dry-run
```

---

## 📊 Monitoring

### Check Certificate Expiration:
```bash
# Days until expiration
openssl x509 -in /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem -noout -dates
```

### View Logs:
```bash
# Nginx access log
sudo tail -f /var/log/nginx/traccar-access.log

# Nginx error log
sudo tail -f /var/log/nginx/traccar-error.log

# Traccar log
sudo tail -f /opt/traccar/logs/tracker-server.log

# Certbot renewal log
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

### Test Renewal:
```bash
# Dry run (doesn't actually renew)
sudo certbot renew --dry-run
```

---

## 🔄 Maintenance

### Monthly Tasks:
- [ ] Check certificate expiration (should auto-renew)
- [ ] Review Nginx logs for errors
- [ ] Verify HTTPS endpoint is accessible
- [ ] Check Traccar logs for issues

### When Certificate Renews (Auto):
- Certbot runs twice daily to check renewal
- Renews certificates within 30 days of expiration
- Automatically reloads Nginx after renewal

### Manual Renewal (if needed):
```bash
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

---

## 📁 Important Files

### Server:
- Nginx config: `/etc/nginx/sites-available/traccar`
- SSL certificates: `/etc/letsencrypt/live/YOUR_DOMAIN/`
- Traccar config: `/opt/traccar/conf/traccar.xml`
- Renewal script: `/etc/cron.d/certbot`

### Local:
- Environment: `.env.production`
- Deploy script: `deploy-firebase.ps1`
- Verification: `finalize-https-setup.ps1`
- Backups: `.env.production.backup-*`, `deploy-firebase.ps1.backup-*`

---

## 🎯 Quick Reference

### Restart Services:
```bash
sudo systemctl restart nginx
sudo systemctl restart traccar
```

### Test Endpoints:
```bash
# HTTPS
curl -I https://traccar-gps.duckdns.org/api/server

# HTTP redirect
curl -I http://traccar-gps.duckdns.org/api/server

# Local Traccar
curl -I http://127.0.0.1:8082/api/server
```

### Redeploy Flutter App:
```powershell
.\deploy-firebase.ps1 production
```

---

## 📞 Support

If issues persist after following this guide:

1. Run verification script: `bash verify-traccar-https.sh YOUR_DOMAIN`
2. Check all logs (Nginx, Traccar, Certbot)
3. Verify DNS: `nslookup YOUR_DOMAIN`
4. Test from different network
5. Check browser console for specific errors

Include output from verification script when asking for help!

---

**Last Updated**: $(Get-Date -Format "yyyy-MM-dd")
**Status**: Ready for deployment
