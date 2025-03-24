#!/bin/bash
# ===================================================================
# APPSERVER-SETUP.SH (FÖRENKLAD VERSION)
# ===================================================================
# Förbereder App Server för att köra en .NET-applikation som kommer
# kopieras över via SCP senare
# 
# Skriptet gör följande:
# 1. Uppdaterar systemet
# 2. Installerar .NET SDK 9.0
# 3. Skapar applikationsmappen
# 4. Konfigurerar systemd-tjänsten
# 5. Sätter rätt rättigheter
#
# Senast uppdaterad: 2025-03-23
# ===================================================================

# --- Systemuppdatering ---
apt-get update 
apt-get upgrade -y

# --- Installation av .NET SDK ---
wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

apt-get update
apt-get install -y apt-transport-https
apt-get update

# Installerar .NET SDK 9.0
apt-get install -y dotnet-sdk-9.0

# --- Skapar applikationsmappen ---
mkdir -p /app

Kopiera din applikation till denna mapp (/app) och starta om tjänsten med:
sudo systemctl restart dotnet-app
EOL

# --- Konfigurerar systemd-tjänst ---
cat > /etc/systemd/system/dotnet-app.service << 'EOL'
[Unit]
Description=.NET Web Application
After=network.target

[Service]
WorkingDirectory=/app
ExecStart=/usr/bin/dotnet run --project /app --urls "http://0.0.0.0:5000"
Restart=always
RestartSec=10
SyslogIdentifier=dotnet-app
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOL

# --- Katalogåtkomst för www-data-användaren ---
mkdir -p /var/www/.dotnet
mkdir -p /var/www/.nuget

# --- Sätter rättigheter ---
chown -R www-data:www-data /app
chown -R www-data:www-data /var/www/.dotnet
chown -R www-data:www-data /var/www/.nuget
chmod -R 755 /app

# --- Aktiverar tjänsten (men startar den inte än) ---
systemctl enable dotnet-app

# --- Loggmeddelande ---
echo "App Server är förberedd för .NET-applikation $(date)" >> /var/log/appserver-setup.log
echo "Installera din app i /app-katalogen och starta sedan tjänsten" >> /var/log/appserver-setup.log