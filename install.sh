#!/bin/bash

# =====================================================
#  System Check Installer / Uninstaller
# =====================================================
#  Features:
#   - Install System Check (Node.js + PM2 + Nginx + SSL)
#   - Uninstall System Check (remove files, nginx config, certs)
# =====================================================

if [ "$EUID" -ne 0 ]; then
  echo -e "\e[31mPlease run as root or with sudo.\e[0m"
  exit 1
fi

echo "====================================="
echo "   Welcome to System Check Installer "
echo "====================================="
echo "1) Install System Check"
echo "2) Uninstall System Check"
read -p "Choose an option [1-2]: " OPTION

# ------------------- UNINSTALL -------------------
if [ "$OPTION" == "2" ]; then
  read -p "Enter your domain name to uninstall (example.com): " DOMAIN
  WEB_DIR="/var/www/$DOMAIN"
  NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

  echo "Stopping and cleaning up for $DOMAIN..."

  # Stop PM2 process
  pm2 delete system-check >/dev/null 2>&1

  # Remove directory
  if [ -d "$WEB_DIR" ]; then
    rm -rf "$WEB_DIR"
    echo "Removed $WEB_DIR"
  fi

  # Remove Nginx config
  if [ -f "$NGINX_CONF" ]; then
    rm -f "$NGINX_CONF"
    rm -f "/etc/nginx/sites-enabled/$DOMAIN"
    echo "Removed Nginx config for $DOMAIN"
  fi

  # Reload Nginx
  systemctl reload nginx

  # Delete SSL cert
  certbot delete --cert-name "$DOMAIN" -n 2>/dev/null

  echo "✅ System Check uninstalled for $DOMAIN."
  exit 0
fi

# ------------------- INSTALL -------------------
read -p "Enter your domain name (example.com): " DOMAIN
read -p "Enter your email for SSL certificate: " EMAIL

# Update system
apt update && apt upgrade -y

# Install dependencies
apt install -y curl git nginx certbot python3-certbot-nginx

# Install Node.js (LTS)
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs build-essential

# Install PM2
npm install -g pm2

# Setup app directory
WEB_DIR="/var/www/$DOMAIN"
if [ -d "$WEB_DIR" ]; then
  echo "📂 Directory exists, pulling latest..."
  cd "$WEB_DIR" && git pull
else
  git clone https://github.com/Tozter-dev/System-Check/main "$WEB_DIR"
fi

cd "$WEB_DIR"
npm install

# Start with PM2
pm2 start server.js --name system-check
pm2 save
pm2 startup systemd -u $USER --hp $HOME

# Nginx config
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"
if [ ! -f "$NGINX_CONF" ]; then
cat > "$NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOL
    ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/
fi

# Test and reload nginx
nginx -t && systemctl restart nginx

# SSL
if ! certbot certificates | grep -q "$DOMAIN"; then
  certbot --nginx -d "$DOMAIN" -d "www.$DOMAIN" --non-interactive --agree-tos -m "$EMAIL"
fi

# Enable certbot auto-renew
systemctl enable certbot.timer

echo "----------------------------------------"
echo "✅ System Check deployed successfully!"
echo "🌍 Access at: https://$DOMAIN"
echo "📂 App files: $WEB_DIR"
echo "----------------------------------------"
