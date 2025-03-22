#!/bin/bash
# scripts/nginx-setup.sh
# Konfigurationsscript för Reverse Proxy (Nginx)

# Sätt APP_SERVER_IP till IP-adressen för App Server
# Detta är bara ett exempel, i verkligheten måste detta skriptet modifieras
# för att hämta denna IP-adress från Azure-metadata eller via parameter
APP_SERVER_IP="10.0.3.4"  # Denna IP-adress kommer från App Server

# Uppdatera systemet
apt-get update
apt-get upgrade -y

# Installera Nginx
apt-get install -y nginx

# Konfigurera Nginx som reverse proxy
cat > /etc/nginx/sites-available/default << EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html index.htm;

    server_name _;

    location / {
        proxy_pass http://${APP_SERVER_IP}:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# Testa Nginx-konfigurationen
nginx -t

# Starta om Nginx för att ladda konfigurationen
systemctl restart nginx

# Säkerställ att Nginx startar automatiskt vid omstart
systemctl enable nginx

# Loggmeddelande
echo "Reverse Proxy (Nginx) konfiguration slutförd $(date)" >> /var/log/nginx-setup.log

####################################