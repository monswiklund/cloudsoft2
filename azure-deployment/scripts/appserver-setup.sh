#!/bin/bash
# scripts/appserver-setup.sh
# Konfigurationsscript för App Server (.NET)

# Uppdatera systemet
apt-get update
apt-get upgrade -y

# Installera .NET SDK 9.0 för Ubuntu 22.04
wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
rm packages-microsoft-prod.deb

apt-get update
apt-get install -y apt-transport-https
apt-get update
apt-get install -y dotnet-sdk-9.0

# Skapa en mapp för applikationen
mkdir -p /app

# Skapa en enkel Razor-applikation
cat > /app/Program.cs << 'EOL'
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddRazorPages();
builder.WebHost.ConfigureKestrel(options => {
    options.ListenAnyIP(5000);
});

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
}

app.UseStaticFiles();
app.UseRouting();
app.MapRazorPages();

app.MapGet("/", () => "Hej från .NET App Server på Ubuntu 22.04 LTS!");

app.Run();
EOL

# Skapa en csproj-fil
cat > /app/app.csproj << 'EOL'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>
</Project>
EOL

# Bygg applikationen
cd /app
dotnet build

# Skapa en systemd-tjänst för applikationen
cat > /etc/systemd/system/dotnet-app.service << 'EOL'
[Unit]
Description=.NET Web Application
After=network.target

[Service]
WorkingDirectory=/app
ExecStart=/usr/bin/dotnet run --project /app/app.csproj
Restart=always
RestartSec=10
SyslogIdentifier=dotnet-app
User=www-data
Environment=ASPNETCORE_ENVIRONMENT=Production

[Install]
WantedBy=multi-user.target
EOL

# Skapa nödvändiga kataloger för www-data användaren
mkdir -p /var/www/.dotnet
mkdir -p /var/www/.nuget

# Ge behörighet till www-data-användaren
chown -R www-data:www-data /app
chown -R www-data:www-data /var/www/.dotnet
chown -R www-data:www-data /var/www/.nuget

# Aktivera och starta tjänsten
systemctl enable dotnet-app
systemctl start dotnet-app

# Loggmeddelande
echo "App Server-konfiguration slutförd $(date) på Ubuntu 22.04 LTS" >> /var/log/appserver-setup.log