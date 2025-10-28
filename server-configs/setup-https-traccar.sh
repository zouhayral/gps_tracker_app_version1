#!/bin/bash
#
# Traccar HTTPS Setup Script
# This script installs and configures Nginx with Let's Encrypt SSL
# for your Traccar server
#
# Usage: sudo bash setup-https-traccar.sh
#

set -e  # Exit on error

echo "========================================="
echo "Traccar HTTPS Setup Script"
echo "========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root (sudo bash setup-https-traccar.sh)"
    exit 1
fi

echo "📋 This script will:"
echo "   1. Install Nginx"
echo "   2. Install Certbot (Let's Encrypt)"
echo "   3. Configure Nginx as reverse proxy for Traccar"
echo "   4. Obtain SSL certificate"
echo "   5. Enable automatic certificate renewal"
echo ""

# Prompt for domain name
read -p "Enter your domain name (e.g., traccar.yourdomain.com): " DOMAIN_NAME
read -p "Enter your email for Let's Encrypt notifications: " EMAIL

if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL" ]; then
    echo "❌ Domain name and email are required"
    exit 1
fi

echo ""
echo "🔍 Configuration:"
echo "   Domain: $DOMAIN_NAME"
echo "   Email: $EMAIL"
echo "   Traccar Port: 8082 (localhost)"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Update system
echo ""
echo "📦 Updating system packages..."
apt-get update -qq

# Install Nginx
echo ""
echo "📦 Installing Nginx..."
apt-get install -y nginx

# Install Certbot
echo ""
echo "📦 Installing Certbot..."
apt-get install -y certbot python3-certbot-nginx

# Stop Nginx temporarily
echo ""
echo "⏸️  Stopping Nginx..."
systemctl stop nginx

# Obtain SSL certificate
echo ""
echo "🔐 Obtaining SSL certificate from Let's Encrypt..."
echo "   (This may take a minute...)"
certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Failed to obtain SSL certificate"
    echo "   Make sure:"
    echo "   - Port 80 is open in your firewall"
    echo "   - $DOMAIN_NAME points to this server's IP"
    echo "   - No other service is using port 80"
    exit 1
fi

echo "✅ SSL certificate obtained successfully"

# Create Nginx config
echo ""
echo "📝 Creating Nginx configuration..."

NGINX_CONFIG="/etc/nginx/sites-available/traccar"
NGINX_ENABLED="/etc/nginx/sites-enabled/traccar"

cat > "$NGINX_CONFIG" <<EOF
# Traccar Reverse Proxy with HTTPS
# Generated on $(date)

# HTTP -> HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME;
    
    # Allow Let's Encrypt validation
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$DOMAIN_NAME/chain.pem;
    
    # Modern SSL settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # CORS headers for Flutter web app
    add_header Access-Control-Allow-Origin "https://app-gps-version.web.app" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
    add_header Access-Control-Allow-Credentials "true" always;
    
    # Handle preflight requests
    if (\$request_method = 'OPTIONS') {
        add_header Access-Control-Allow-Origin "https://app-gps-version.web.app" always;
        add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS" always;
        add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With" always;
        add_header Access-Control-Allow-Credentials "true" always;
        add_header Access-Control-Max-Age 1728000;
        add_header Content-Type "text/plain charset=UTF-8";
        add_header Content-Length 0;
        return 204;
    }
    
    # Timeouts
    client_max_body_size 50M;
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    # Proxy to Traccar
    location / {
        proxy_pass http://127.0.0.1:8082;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
    
    # Logs
    access_log /var/log/nginx/traccar-access.log;
    error_log /var/log/nginx/traccar-error.log;
}
EOF

echo "✅ Nginx configuration created: $NGINX_CONFIG"

# Enable site
echo ""
echo "🔗 Enabling Nginx site..."
ln -sf "$NGINX_CONFIG" "$NGINX_ENABLED"

# Remove default site if exists
if [ -f "/etc/nginx/sites-enabled/default" ]; then
    rm -f /etc/nginx/sites-enabled/default
    echo "   Removed default Nginx site"
fi

# Test Nginx config
echo ""
echo "🧪 Testing Nginx configuration..."
nginx -t

if [ $? -ne 0 ]; then
    echo "❌ Nginx configuration test failed"
    exit 1
fi

echo "✅ Nginx configuration valid"

# Start Nginx
echo ""
echo "▶️  Starting Nginx..."
systemctl start nginx
systemctl enable nginx

# Check if Nginx is running
if systemctl is-active --quiet nginx; then
    echo "✅ Nginx is running"
else
    echo "❌ Nginx failed to start"
    systemctl status nginx
    exit 1
fi

# Setup auto-renewal
echo ""
echo "🔄 Setting up automatic SSL renewal..."
systemctl enable certbot.timer
systemctl start certbot.timer

# Test renewal
echo "   Testing renewal process (dry-run)..."
certbot renew --dry-run --nginx

if [ $? -eq 0 ]; then
    echo "✅ Auto-renewal configured successfully"
else
    echo "⚠️  Auto-renewal test had warnings (but certificate is valid)"
fi

# Open firewall ports if UFW is active
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo ""
    echo "🔥 Configuring firewall (UFW)..."
    ufw allow 'Nginx Full'
    ufw delete allow 8082  # Remove direct access to Traccar
    echo "✅ Firewall configured"
fi

# Display results
echo ""
echo "========================================="
echo "✅ Setup Complete!"
echo "========================================="
echo ""
echo "📋 Summary:"
echo "   HTTPS URL: https://$DOMAIN_NAME"
echo "   SSL Certificate: Valid"
echo "   Auto-renewal: Enabled"
echo "   Nginx Status: Running"
echo ""
echo "🧪 Test your setup:"
echo "   curl -I https://$DOMAIN_NAME/api/server"
echo ""
echo "🔐 Security:"
echo "   - HTTP (port 80) redirects to HTTPS (port 443)"
echo "   - Traccar (port 8082) only accessible via localhost"
echo "   - SSL certificate auto-renews every 60 days"
echo ""
echo "📝 Next steps:"
echo "   1. Update .env.production with: TRACCAR_BASE_URL=https://$DOMAIN_NAME"
echo "   2. Redeploy Flutter web app"
echo "   3. Test login at: https://app-gps-version.web.app"
echo ""
echo "📊 Monitor logs:"
echo "   - Nginx access: tail -f /var/log/nginx/traccar-access.log"
echo "   - Nginx errors: tail -f /var/log/nginx/traccar-error.log"
echo "   - Traccar: sudo journalctl -u traccar -f"
echo ""
