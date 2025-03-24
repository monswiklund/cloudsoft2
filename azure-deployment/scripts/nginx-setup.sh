#!/bin/bash
# ===================================================================
# NGINX-SETUP.SH
# ===================================================================
# Konfigurationsscript för min Reverse Proxy (Nginx)
# 
# Detta script installerar och konfigurerar Nginx som fungerar som
# en front-end för min applikation. All extern trafik kommer genom
# denna server som sedan vidarebefordrar den till App Server.
#
# Skriptet gör följande:
# 1. Installerar Nginx
# 2. Konfigurerar Nginx som en reverse proxy mot App Server
# 3. Startar och aktiverar Nginx-tjänsten
#
# Senast uppdaterad: 2024-03-23
# ===================================================================

# --- APP_SERVER_IP ---
# Fast IP-adress till min interna App Server
# OBS: I en mer robust lösning borde jag hämta denna IP dynamiskt
# från Azure Metadata Service eller via en parameter till skriptet
APP_SERVER_IP="10.0.3.4"  # Fast IP-adress i AppServerSubnet

# --- Systemuppdatering ---
# Uppdaterar systemet innan jag installerar ny programvara
apt-get update
apt-get upgrade -y

# --- Nginx-installation ---
# Installerar Nginx webbserver/reverse proxy
apt-get install -y nginx

# --- Nginx-konfiguration ---
# Konfigurerar Nginx att fungera som reverse proxy mot min .NET-app
# Använder heredoc (<<) för att skapa konfigurationsfilen
cat > /etc/nginx/sites-available/default << EOL
server {
    # Lyssnar på port 80 för alla IPv4 och IPv6-adresser
    listen 80 default_server;
    listen [::]:80 default_server;

    # Standard root-katalog och index-filer (används mest för statiskt innehåll)
    root /var/www/html;
    index index.html index.htm;

    # Serverns namn - _ matchar alla domännamn
    server_name _;

    # Huvudkonfiguration - vidarebefordra allt till App Server
    location / {
        # Skickar vidare alla förfrågningar till App Server på port 5000
        proxy_pass http://${APP_SERVER_IP}:5000;
        
        # HTTP 1.1 stöd
        proxy_http_version 1.1;
        
        # Nödvändiga headers för WebSocket och connection handling
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection keep-alive;
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        
        # Headers för att App Server ska veta klientens ursprungliga IP och protokoll
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# --- Nginx-konfigurationstest ---
# Verifierar att konfigurationen är korrekt innan jag tillämpar den

nginx -t
# Om testet misslyckas så skrivs ett felmeddelande till loggen
if [ $? -ne 0 ]; then
    echo "Nginx-konfigurationen är felaktig" >> /var/log/nginx-setup.log
fi

# --- Starta om Nginx ---
# Aktiverar den nya konfigurationen genom att starta om tjänsten
systemctl restart nginx

# --- Aktivera Nginx vid uppstart ---
# Ser till att Nginx startar automatiskt när servern startas om
systemctl enable nginx

# --- Loggmeddelande ---
# Skriver ett meddelande till loggen för att dokumentera installationen
echo "Reverse Proxy (Nginx) konfiguration slutförd $(date)" >> /var/log/nginx-setup.log