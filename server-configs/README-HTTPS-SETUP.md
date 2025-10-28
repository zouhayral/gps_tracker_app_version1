# ===========================================
# Traccar HTTPS Setup - Complete Guide
# ===========================================

## Problem
Your Flutter web app (HTTPS) cannot connect to Traccar backend (HTTP) due to mixed content security policy.

**Current Setup:**
- Frontend: https://app-gps-version.web.app (HTTPS) ✅
- Backend: http://37.60.238.215:8082 (HTTP) ❌

**Error:** Browsers block HTTP requests from HTTPS pages for security.

---

## Solution Options

### Option 1: Nginx Reverse Proxy (Recommended) ⭐

**Pros:**
- Best performance
- Easy to manage
- Automatic SSL renewal
- Can serve multiple services

**Setup Steps:**

1. **Prepare DNS**
   ```bash
   # Point your domain to server IP
   # Example: traccar.yourdomain.com → 37.60.238.215
   ```

2. **Upload setup script to server**
   ```bash
   # On your local machine
   scp server-configs/setup-https-traccar.sh root@37.60.238.215:/root/
   ```

3. **Run setup script on server**
   ```bash
   # SSH to server
   ssh root@37.60.238.215
   
   # Run setup
   chmod +x setup-https-traccar.sh
   sudo bash setup-https-traccar.sh
   
   # Follow prompts:
   # - Domain: traccar.yourdomain.com
   # - Email: your-email@example.com
   ```

4. **Verify setup**
   ```bash
   # Test HTTPS endpoint
   curl -I https://traccar.yourdomain.com/api/server
   
   # Check Nginx status
   systemctl status nginx
   
   # View logs
   tail -f /var/log/nginx/traccar-access.log
   ```

5. **Update Flutter app**
   ```bash
   # Edit .env.production
   TRACCAR_BASE_URL=https://traccar.yourdomain.com
   ALLOW_INSECURE=false
   
   # Edit deploy-firebase.ps1 (line 34)
   $TraccarUrl = "https://traccar.yourdomain.com"
   $AllowInsecure = "false"
   
   # Redeploy
   .\deploy-firebase.ps1 production
   ```

---

### Option 2: Direct Java SSL (No Nginx)

**Pros:**
- Simpler architecture
- One less service to manage

**Cons:**
- Harder to manage certificates
- Less flexible

**Setup:**

```bash
# Upload script
scp server-configs/setup-traccar-direct-ssl.sh root@37.60.238.215:/root/

# SSH and run
ssh root@37.60.238.215
chmod +x setup-traccar-direct-ssl.sh
sudo bash setup-traccar-direct-ssl.sh

# Update app to use port 8443
TRACCAR_BASE_URL=https://traccar.yourdomain.com:8443
```

---

### Option 3: Docker with Nginx (Modern)

**Pros:**
- Containerized (easy backup/migration)
- Isolated environment
- Easy scaling

**Setup:**

```bash
# 1. Install Docker on server
ssh root@37.60.238.215
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# 2. Upload configs
scp -r server-configs root@37.60.238.215:/opt/traccar-docker/

# 3. Start services
cd /opt/traccar-docker
docker-compose up -d

# 4. Obtain SSL certificate
docker-compose run --rm certbot certonly \
  --webroot -w /var/www/certbot \
  -d traccar.yourdomain.com \
  --email your-email@example.com \
  --agree-tos

# 5. Restart Nginx
docker-compose restart nginx
```

---

## Quick Start (Option 1 - Recommended)

**If you have a domain:**

```bash
# 1. SSH to server
ssh root@37.60.238.215

# 2. Download and run setup script
wget https://raw.githubusercontent.com/YOUR_REPO/main/server-configs/setup-https-traccar.sh
chmod +x setup-https-traccar.sh
sudo bash setup-https-traccar.sh
```

**If you DON'T have a domain:**

You have two choices:

### A. Get a free domain
- Use: DuckDNS, No-IP, or Cloudflare (free tier)
- Point subdomain to: 37.60.238.215
- Example: `traccar-gps.duckdns.org`

### B. Use self-signed certificate (testing only)
```bash
# Generate self-signed cert
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/traccar-selfsigned.key \
  -out /etc/ssl/certs/traccar-selfsigned.crt

# Update nginx config to use it
# (Users will get security warnings in browser)
```

---

## Troubleshooting

### Certificate Error
```bash
# Check certificate validity
openssl x509 -in /etc/letsencrypt/live/DOMAIN/fullchain.pem -text -noout

# Renew manually
certbot renew --nginx
```

### Nginx Won't Start
```bash
# Check config syntax
nginx -t

# Check logs
tail -f /var/log/nginx/error.log

# Check port conflicts
netstat -tulpn | grep :443
```

### Traccar Not Accessible
```bash
# Check if Traccar is running
systemctl status traccar

# Check if listening on 8082
netstat -tulpn | grep 8082

# Test local connection
curl http://127.0.0.1:8082/api/server
```

### CORS Errors
```bash
# Check Nginx config has CORS headers
grep -A 5 "Access-Control-Allow-Origin" /etc/nginx/sites-available/traccar

# Test CORS
curl -I -X OPTIONS https://traccar.yourdomain.com/api/server \
  -H "Origin: https://app-gps-version.web.app"
```

### Mixed Content Warning Still Appears
- Make sure Flutter app uses HTTPS URL
- Clear browser cache
- Check browser DevTools → Network tab → Request URL
- Verify no hardcoded HTTP URLs in code

---

## Post-Setup Checklist

- [ ] SSL certificate obtained and valid
- [ ] Nginx running and accessible on port 443
- [ ] Traccar accessible via HTTPS (https://your-domain.com/api/server)
- [ ] CORS headers present in responses
- [ ] `.env.production` updated with HTTPS URL
- [ ] `deploy-firebase.ps1` updated with HTTPS URL
- [ ] Flutter app redeployed to Firebase
- [ ] Login succeeds at https://app-gps-version.web.app
- [ ] No console errors in browser DevTools
- [ ] Auto-renewal configured (check: `certbot renew --dry-run`)

---

## Monitoring

### Check SSL expiration
```bash
# Days until expiration
echo | openssl s_client -servername traccar.yourdomain.com \
  -connect traccar.yourdomain.com:443 2>/dev/null | \
  openssl x509 -noout -dates
```

### Monitor logs
```bash
# Access logs (who's connecting)
tail -f /var/log/nginx/traccar-access.log

# Error logs (problems)
tail -f /var/log/nginx/traccar-error.log

# Traccar logs
tail -f /opt/traccar/logs/tracker-server.log
```

### Test renewal
```bash
# Dry run (doesn't actually renew)
certbot renew --dry-run

# Manual renewal
certbot renew --force-renewal
```

---

## Security Best Practices

1. **Firewall Configuration**
   ```bash
   # Allow only necessary ports
   ufw allow 22/tcp    # SSH
   ufw allow 80/tcp    # HTTP (for Let's Encrypt)
   ufw allow 443/tcp   # HTTPS
   ufw allow 5055/tcp  # GPS devices
   ufw deny 8082/tcp   # Block direct Traccar access
   ufw enable
   ```

2. **Strong SSL Configuration**
   - TLS 1.2 and 1.3 only (already in config)
   - HSTS enabled (already in config)
   - Regular security updates: `apt update && apt upgrade`

3. **Regular Backups**
   ```bash
   # Backup Traccar data
   tar -czf traccar-backup-$(date +%Y%m%d).tar.gz /opt/traccar/data/

   # Backup Nginx config
   tar -czf nginx-backup-$(date +%Y%m%d).tar.gz /etc/nginx/
   ```

4. **Monitor Certificate Expiration**
   - Let's Encrypt certs expire after 90 days
   - Auto-renewal should handle this
   - Set up email alerts if renewal fails

---

## Quick Reference

**Service Commands:**
```bash
# Nginx
systemctl status nginx
systemctl restart nginx
systemctl reload nginx  # Reload config without downtime

# Traccar
systemctl status traccar
systemctl restart traccar

# Check logs
journalctl -u nginx -f
journalctl -u traccar -f
```

**File Locations:**
```bash
/etc/nginx/sites-available/traccar     # Nginx config
/etc/letsencrypt/live/DOMAIN/          # SSL certificates
/opt/traccar/conf/traccar.xml          # Traccar config
/var/log/nginx/                        # Nginx logs
/opt/traccar/logs/                     # Traccar logs
```

**Test Endpoints:**
```bash
# Server info
curl https://traccar.yourdomain.com/api/server

# Health check (returns 200)
curl https://traccar.yourdomain.com/health
```

---

## Support

If issues persist:

1. Check server logs
2. Verify DNS is correct: `nslookup traccar.yourdomain.com`
3. Test from server: `curl -I http://127.0.0.1:8082/api/server`
4. Check firewall: `ufw status`
5. Verify port binding: `netstat -tulpn | grep -E ':(80|443|8082)'`

Need help? Include:
- Output of: `nginx -t`
- Last 50 lines: `journalctl -u nginx -n 50`
- Certificate info: `certbot certificates`
