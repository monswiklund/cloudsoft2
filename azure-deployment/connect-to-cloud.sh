#!/bin/bash
# connect-to-cloud.sh
# Skript för att ansluta till din molninfrastruktur

# Färgkoder för utskrifter
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfiguration - ersätt med dina faktiska värden från deploymentet
BASTION_IP=$(az deployment group show --resource-group myapp-rg --name myapp-deployment --query 'properties.outputs.bastionPublicIp.value' -o tsv)
BASTION_USER="azureuser"
SSH_KEY_PATH="~/.ssh/id_rsa" # Din lokala SSH-nyckel som används för att ansluta till Bastion

# Timestamp-fil för att lagra information om senaste åtgärder
TIMESTAMP_FILE="$HOME/.myapp-timestamps"

# Funktion för att uppdatera timestamp
update_timestamp() {
    local action=$1
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Skapa fil om den inte finns
    touch "$TIMESTAMP_FILE"
    
    # Uppdatera timestamp för den specifika åtgärden
    if grep -q "^$action:" "$TIMESTAMP_FILE"; then
        sed -i.bak "s/^$action:.*/$action: $timestamp/" "$TIMESTAMP_FILE"
    else
        echo "$action: $timestamp" >> "$TIMESTAMP_FILE"
    fi
}

# Funktion för att hämta timestamp
get_timestamp() {
    local action=$1
    local default="Aldrig"
    
    if [ -f "$TIMESTAMP_FILE" ]; then
        local result=$(grep "^$action:" "$TIMESTAMP_FILE" | cut -d':' -f2- | xargs)
        if [ -n "$result" ]; then
            echo "$result"
        else
            echo "$default"
        fi
    else
        echo "$default"
    fi
}

# Rensar gamla host keys för att förhindra verifieringsproblem
clean_host_keys() {
    echo -e "${YELLOW}Rensar gamla SSH host keys...${NC}"
    
    # Tar bort eventuellt befintliga nycklar för våra servrar
    ssh-keygen -R $BASTION_IP 2>/dev/null
    ssh-keygen -R myapp-bastion 2>/dev/null
    ssh-keygen -R 10.0.2.4 2>/dev/null
    ssh-keygen -R myapp-reverseproxy 2>/dev/null
    ssh-keygen -R 10.0.3.4 2>/dev/null
    ssh-keygen -R myapp-appserver 2>/dev/null
    
    echo -e "${GREEN}SSH host keys har rensats!${NC}"
    
    # Uppdatera timestamp
    update_timestamp "clean_host_keys"
}

# Skapa eller uppdatera SSH-konfigurationen
update_ssh_config() {
    echo -e "${YELLOW}Uppdaterar SSH-konfigurationen...${NC}"
    
    # Skapa SSH config-filen om den inte finns
    mkdir -p ~/.ssh
    touch ~/.ssh/config
    
    # Kontrollera om konfigurationen redan finns
    if grep -q "Host myapp-bastion" ~/.ssh/config; then
        # Uppdatera befintlig konfiguration
        sed -i.bak "s/HostName .* # myapp-bastion/HostName ${BASTION_IP} # myapp-bastion/g" ~/.ssh/config
    else
        # Lägg till ny konfiguration
        cat >> ~/.ssh/config << EOL

# MyApp Cloud Infrastructure
Host myapp-bastion
    HostName ${BASTION_IP} # myapp-bastion
    User ${BASTION_USER}
    IdentityFile ${SSH_KEY_PATH}
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host myapp-reverseproxy
    HostName 10.0.2.4
    User ${BASTION_USER}
    IdentityFile ${SSH_KEY_PATH}
    ProxyJump myapp-bastion
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host myapp-appserver
    HostName 10.0.3.4
    User ${BASTION_USER}
    IdentityFile ${SSH_KEY_PATH}
    ProxyJump myapp-bastion
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOL
    fi
    
    # Sätt rätt behörigheter
    chmod 600 ~/.ssh/config
    
    echo -e "${GREEN}SSH-konfigurationen har uppdaterats!${NC}"
    
    # Uppdatera timestamp
    update_timestamp "update_ssh_config"
}

# Kör setup_ssh_access på bastion om det behövs
setup_bastion_access() {
    echo -e "${YELLOW}Konfigurerar SSH-åtkomst på Bastion...${NC}"
    
    # Kontrollera om setup_ssh_access.sh-skriptet finns och kör det
    ssh -q myapp-bastion "if [ -f ~/setup_ssh_access.sh ]; then bash ~/setup_ssh_access.sh; else echo 'setup_ssh_access.sh not found'; fi"
    
    echo -e "${GREEN}SSH-åtkomst på Bastion har konfigurerats!${NC}"
    
    # Uppdatera timestamp
    update_timestamp "setup_bastion_access"
}

# Skapa en SSH-tunnel till appservern på port 5000
create_app_tunnel() {
    echo -e "${YELLOW}Skapar SSH-tunnel till appservern port 5000...${NC}"
    
    # Avsluta eventuell befintlig tunnel på port 5000
    lsof -ti:5000 | xargs kill -9 2>/dev/null
    
    # Skapa SSH-tunnel genom bastion till appserver
    ssh -L 5000:10.0.3.4:5000 -N -f myapp-bastion
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSH-tunnel skapad! Besök http://localhost:5000 i din webbläsare.${NC}"
        echo -e "${YELLOW}Tunneln körs i bakgrunden. Kör 'lsof -ti:5000 | xargs kill -9' för att stänga den.${NC}"
        update_timestamp "create_app_tunnel"
    else
        echo -e "${RED}Misslyckades med att skapa SSH-tunnel.${NC}"
    fi
}

# Skapa en SSH-tunnel för filöverföring
create_file_tunnel() {
    echo -e "${YELLOW}Skapar SSH-tunnel för filöverföring (port 2222)...${NC}"
    
    # Avsluta eventuell befintlig tunnel på port 2222
    lsof -ti:2222 | xargs kill -9 2>/dev/null
    
    # Skapa SSH-tunnel genom bastion till appserver för SSH-trafik
    ssh -L 2222:10.0.3.4:22 -N -f myapp-bastion
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSH-tunnel för filöverföring skapad på port 2222!${NC}"
        echo -e "${YELLOW}Tunneln körs i bakgrunden. Kör 'lsof -ti:2222 | xargs kill -9' för att stänga den.${NC}"
        update_timestamp "create_file_tunnel"
    else
        echo -e "${RED}Misslyckades med att skapa SSH-tunnel för filöverföring.${NC}"
    fi
}

# Funktion för att överföra filer till appservern
transfer_files() {
    echo -e "${YELLOW}Överför filer till App Server...${NC}"
    
    # Fråga efter källsökväg om den inte anges
    local source_path
    read -p "Ange sökväg till filer att överföra: " source_path
    
    if [ -z "$source_path" ]; then
        echo -e "${RED}Ingen källsökväg angiven.${NC}"
        return 1
    fi
    
    if [ ! -e "$source_path" ]; then
        echo -e "${RED}Källsökvägen existerar inte: $source_path${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Välj överföringsmetod:${NC}"
    echo "1) Via SSH-tunnel (port 2222)"
    echo "2) Direkt via ProxyJump"
    read -p "Ditt val: " transfer_method
    
    case $transfer_method in
        1)
            # Först skapa tunneln
            create_file_tunnel
            
            # Sedan överföra filerna via tunneln
            echo -e "${YELLOW}Överför filer via SSH-tunnel...${NC}"
            scp -r -P 2222 "$source_path" "azureuser@localhost:~/"
            ;;
        2)
            # Överför direkt med ProxyJump
            echo -e "${YELLOW}Överför filer direkt via ProxyJump...${NC}"
            scp -r -o "ProxyJump=myapp-bastion" "$source_path" "azureuser@myapp-appserver:~/"
            ;;
        *)
            echo -e "${RED}Ogiltigt val, avbryter.${NC}"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Filöverföring slutförd!${NC}"
        update_timestamp "transfer_files"
    else
        echo -e "${RED}Filöverföring misslyckades.${NC}"
    fi
}

# Funktion för att installera .NET SDK på appservern
install_dotnet_sdk() {
    echo -e "${YELLOW}Installerar/uppdaterar .NET SDK på App Server...${NC}"
    
    # Fråga efter .NET-version
    local dotnet_version
    read -p "Ange .NET-version att installera (t.ex. 8.0): " dotnet_version
    
    if [ -z "$dotnet_version" ]; then
        echo -e "${YELLOW}Ingen version angiven, använder standardversion 8.0${NC}"
        dotnet_version="8.0"
    fi
    
    # Kör kommandot för att installera .NET SDK på appservern
    ssh myapp-appserver << EOF
    echo "Kontrollerar om .NET är installerat..."
    
    if command -v dotnet &> /dev/null; then
        echo "Nuvarande installerade .NET-versioner:"
        dotnet --list-sdks
        dotnet --list-runtimes
    fi
    
    echo "Installerar .NET SDK $dotnet_version..."
    
    # Installera nödvändiga paket
    sudo apt-get update
    sudo apt-get install -y wget apt-transport-https
    
    # Lägg till Microsofts paketrepo
    wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
    sudo dpkg -i packages-microsoft-prod.deb
    rm packages-microsoft-prod.deb
    
    # Uppdatera paketlistor och installera .NET SDK
    sudo apt-get update
    sudo apt-get install -y dotnet-sdk-$dotnet_version
    
    echo "Installation slutförd. Installerade .NET-versioner:"
    dotnet --list-sdks
    dotnet --list-runtimes
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}.NET SDK installation/uppdatering slutförd!${NC}"
        update_timestamp "install_dotnet_sdk"
    else
        echo -e "${RED}.NET SDK installation/uppdatering misslyckades.${NC}"
    fi
}

# Funktion för att visa meny och hantera val
show_menu() {
    # Hämta timestamps
    local config_time=$(get_timestamp "update_ssh_config")
    local clean_time=$(get_timestamp "clean_host_keys")
    local setup_time=$(get_timestamp "setup_bastion_access")
    local tunnel_time=$(get_timestamp "create_app_tunnel")
    local transfer_time=$(get_timestamp "transfer_files")
    local dotnet_time=$(get_timestamp "install_dotnet_sdk")
    
    echo -e "${BLUE}===== MyApp Cloud Infrastructure =====${NC}"
    echo -e "${YELLOW}Bastion IP:${NC} ${BASTION_IP}"
    echo
    echo "Välj en server att ansluta till:"
    echo "1) Bastion (Jump Server)"
    echo "2) Reverse Proxy Server"
    echo "3) App Server (.NET)"
    echo -e "4) Uppdatera SSH-konfiguration ${YELLOW}(Senast ändrad: $config_time)${NC}"
    echo -e "5) Rensa SSH host keys ${YELLOW}(Senast ändrad: $clean_time)${NC}"
    echo -e "6) Konfigurera SSH-åtkomst på Bastion ${YELLOW}(Senast konfigurerad: $setup_time)${NC}"
    echo -e "7) Skapa SSH-tunnel till App Server (port 5000) ${YELLOW}(Senast skapad: $tunnel_time)${NC}"
    echo -e "8) Överför filer till App Server ${YELLOW}(Senast: $transfer_time)${NC}"
    echo -e "9) Installera/uppdatera .NET SDK på App Server ${YELLOW}(Senast: $dotnet_time)${NC}"
    echo "q) Avsluta"
    echo
    read -p "Ditt val: " choice
    
    case $choice in
        1)
            echo -e "${GREEN}Ansluter till Bastion server...${NC}"
            ssh myapp-bastion
            ;;
        2)
            echo -e "${GREEN}Ansluter till Reverse Proxy server via Bastion...${NC}"
            ssh myapp-reverseproxy
            ;;
        3)
            echo -e "${GREEN}Ansluter till App server via Bastion...${NC}"
            ssh myapp-appserver
            ;;
        4)
            update_ssh_config
            ;;
        5)
            clean_host_keys
            ;;
        6)
            setup_bastion_access
            ;;
        7)
            create_app_tunnel
            ;;
        8)
            transfer_files
            ;;
        9)
            install_dotnet_sdk
            ;;
        q|Q)
            echo -e "${YELLOW}Avslutar. Ha en trevlig dag!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Ogiltigt val, försök igen.${NC}"
            ;;
    esac
}

# Huvudprogrammet
echo -e "${YELLOW}Hämtar information om din molninfrastruktur...${NC}"

# Kontrollera om BASTION_IP kunde hämtas
if [ -z "$BASTION_IP" ]; then
    echo -e "${RED}Kunde inte hämta Bastion IP-adress. Kontrollera att deploymentet finns.${NC}"
    echo "Du kan ange IP-adressen manuellt genom att redigera variabeln BASTION_IP i skriptet."
    exit 1
fi

# Rensa gamla host keys
clean_host_keys

# Uppdatera SSH-konfigurationen
update_ssh_config

# Visa menyn
while true; do
    show_menu
    echo
done