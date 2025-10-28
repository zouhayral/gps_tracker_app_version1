#!/bin/bash
#
# Traccar Direct HTTPS Configuration (Alternative to Nginx)
# This configures Traccar to handle SSL directly via Java
#
# Usage: sudo bash setup-traccar-direct-ssl.sh
#

set -e

echo "========================================="
echo "Traccar Direct HTTPS Setup"
echo "========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root"
    exit 1
fi

# Prompt for domain
read -p "Enter your domain name: " DOMAIN_NAME
read -p "Enter your email for Let's Encrypt: " EMAIL

if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL" ]; then
    echo "❌ Domain and email required"
    exit 1
fi

# Install certbot
echo ""
echo "📦 Installing Certbot..."
apt-get update -qq
apt-get install -y certbot

# Stop Traccar temporarily
echo ""
echo "⏸️  Stopping Traccar..."
systemctl stop traccar

# Obtain certificate (standalone mode)
echo ""
echo "🔐 Obtaining SSL certificate..."
certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN_NAME" \
    --http-01-port 80

if [ $? -ne 0 ]; then
    echo "❌ Failed to obtain certificate"
    systemctl start traccar
    exit 1
fi

# Convert PEM to PKCS12 (Java keystore format)
echo ""
echo "🔄 Converting certificate to Java keystore format..."

CERT_DIR="/etc/letsencrypt/live/$DOMAIN_NAME"
KEYSTORE_DIR="/opt/traccar/ssl"
KEYSTORE_FILE="$KEYSTORE_DIR/traccar.pkcs12"
KEYSTORE_PASS="changeit"  # Change this!

mkdir -p "$KEYSTORE_DIR"

openssl pkcs12 -export \
    -in "$CERT_DIR/fullchain.pem" \
    -inkey "$CERT_DIR/privkey.pem" \
    -out "$KEYSTORE_FILE" \
    -name traccar \
    -password "pass:$KEYSTORE_PASS"

chmod 640 "$KEYSTORE_FILE"
chown traccar:traccar "$KEYSTORE_FILE"

echo "✅ Keystore created: $KEYSTORE_FILE"

# Update Traccar configuration
echo ""
echo "📝 Updating Traccar configuration..."

TRACCAR_CONFIG="/opt/traccar/conf/traccar.xml"

# Backup original config
cp "$TRACCAR_CONFIG" "${TRACCAR_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

# Add/update SSL configuration
cat >> "$TRACCAR_CONFIG" <<EOF

<!-- HTTPS Configuration (added by setup script) -->
<entry key='web.port'>8443</entry>
<entry key='web.ssl.enable'>true</entry>
<entry key='web.ssl.keystore'>$KEYSTORE_FILE</entry>
<entry key='web.ssl.keystorePassword'>$KEYSTORE_PASS</entry>
<entry key='web.ssl.keystoreType'>PKCS12</entry>

<!-- CORS Configuration -->
<entry key='web.origin'>https://app-gps-version.web.app</entry>
EOF

echo "✅ Traccar configuration updated"

# Open firewall
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo ""
    echo "🔥 Configuring firewall..."
    ufw allow 8443/tcp
    ufw delete allow 8082/tcp  # Remove old HTTP port
    echo "✅ Firewall configured"
fi

# Setup auto-renewal script
echo ""
echo "🔄 Setting up SSL renewal automation..."

cat > /opt/traccar/renew-ssl.sh <<'SCRIPT'
#!/bin/bash
# Automatic SSL certificate renewal for Traccar

DOMAIN="DOMAIN_PLACEHOLDER"
KEYSTORE_FILE="/opt/traccar/ssl/traccar.pkcs12"
KEYSTORE_PASS="changeit"

# Renew certificate
certbot renew --quiet

# Convert to PKCS12
openssl pkcs12 -export \
    -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
    -inkey "/etc/letsencrypt/live/$DOMAIN/privkey.pem" \
    -out "$KEYSTORE_FILE" \
    -name traccar \
    -password "pass:$KEYSTORE_PASS"

# Restart Traccar
systemctl restart traccar

echo "SSL certificate renewed and Traccar restarted"
SCRIPT

sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN_NAME/g" /opt/traccar/renew-ssl.sh
chmod +x /opt/traccar/renew-ssl.sh

# Add to crontab (run monthly)
(crontab -l 2>/dev/null; echo "0 3 1 * * /opt/traccar/renew-ssl.sh >> /var/log/traccar-ssl-renewal.log 2>&1") | crontab -

echo "✅ Auto-renewal configured (monthly at 3 AM)"

# Start Traccar
echo ""
echo "▶️  Starting Traccar with HTTPS..."
systemctl start traccar

sleep 5

# Check if running
if systemctl is-active --quiet traccar; then
    echo "✅ Traccar is running"
else
    echo "❌ Traccar failed to start"
    echo "   Check logs: sudo journalctl -u traccar -n 50"
    exit 1
fi

# Display results
echo ""
echo "========================================="
echo "✅ Direct HTTPS Setup Complete!"
echo "========================================="
echo ""
echo "📋 Configuration:"
echo "   HTTPS URL: https://$DOMAIN_NAME:8443"
echo "   Keystore: $KEYSTORE_FILE"
echo "   Password: $KEYSTORE_PASS (change in traccar.xml!)"
echo ""
echo "🧪 Test:"
echo "   curl -I https://$DOMAIN_NAME:8443/api/server"
echo ""
echo "📝 Next steps:"
echo "   1. Change keystore password in /opt/traccar/conf/traccar.xml"
echo "   2. Update .env.production: TRACCAR_BASE_URL=https://$DOMAIN_NAME:8443"
echo "   3. Redeploy Flutter app"
echo ""
echo "⚠️  Important:"
echo "   - Don't forget to update the keystore password!"
echo "   - Certificate auto-renews on the 1st of each month"
echo ""
