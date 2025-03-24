#!/bin/bash
# connect-to-cloud.sh
# Skript för att ansluta till din molninfrastruktur

# Färgkoder för utskrifter
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfigurationsvariabler - hämta alla IP-adresser från Azure deployment
BASTION_IP=$(az deployment group show --resource-group myapp-rg --name myapp-deployment --query 'properties.outputs.bastionPublicIp.value' -o tsv)
REVERSEPROXY_IP=$(az deployment group show --resource-group myapp-rg --name myapp-deployment --query 'properties.outputs.reverseProxyPrivateIp.value' -o tsv)
APPSERVER_IP=$(az deployment group show --resource-group myapp-rg --name myapp-deployment --query 'properties.outputs.appServerPrivateIp.value' -o tsv)
BASTION_USER="azureuser" # Användarnamn för att ansluta till Bastion
SSH_KEY_PATH="~/.ssh/id_rsa" # Lokala SSH-nyckeln för autentisering

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
    # Kontrollera om timestamp-filen finns
    if [ -f "$TIMESTAMP_FILE" ]; then
    # Hämta resultatet från grep och klipp bort prefixet
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
    
    # Tar bort eventuellt befintliga nycklar servrar
    ssh-keygen -R $BASTION_IP 2>/dev/null
    ssh-keygen -R myapp-bastion 2>/dev/null
    ssh-keygen -R $REVERSEPROXY_IP 2>/dev/null
    ssh-keygen -R myapp-reverseproxy 2>/dev/null
    ssh-keygen -R $APPSERVER_IP 2>/dev/null
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
        sed -i.bak "s/HostName .* # myapp-reverseproxy/HostName ${REVERSEPROXY_IP} # myapp-reverseproxy/g" ~/.ssh/config
        sed -i.bak "s/HostName .* # myapp-appserver/HostName ${APPSERVER_IP} # myapp-appserver/g" ~/.ssh/config
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
    HostName ${REVERSEPROXY_IP} # myapp-reverseproxy
    User ${BASTION_USER}
    IdentityFile ${SSH_KEY_PATH}
    ProxyJump myapp-bastion
    ForwardAgent yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host myapp-appserver
    HostName ${APPSERVER_IP} # myapp-appserver
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
# Logga en filöverföring till historikfilen
log_file_transfer() {
    local source=$1
    local destination=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local transfer_log="$HOME/.myapp-transfers.log"
    
    # Skapa logfilen om den inte finns
    touch "$transfer_log"
    
    # Begränsa filnamnet om det är för långt
    local short_source
    if [[ ${#source} -gt 40 ]]; then
        short_source="...${source: -40}"
    else
        short_source="$source"
    fi
    
    # Lägg till överföringen i loggen (i början av filen)
    echo "$timestamp | $short_source | $destination" | cat - "$transfer_log" > /tmp/templog && mv /tmp/templog "$transfer_log"
    
    # Behåll bara de 100 senaste överföringarna
    tail -n 100 "$transfer_log" > /tmp/templog && mv /tmp/templog "$transfer_log"
}

# Visa senaste filöverföringar
show_recent_transfers() {
    local transfer_log="$HOME/.myapp-transfers.log"
    local count=${1:-5} # Antal överföringar att visa, standard är 5
    
    echo -e "${BLUE}=== Senaste $count filöverföringar ===${NC}"
    
    if [ -f "$transfer_log" ]; then
        head -n $count "$transfer_log" | while IFS='|' read -r timestamp source destination; do
            echo -e "${YELLOW}$timestamp${NC} | ${GREEN}$source${NC} | ${BLUE}$destination${NC}"
        done
    else
        echo -e "${YELLOW}Ingen överföringshistorik finns ännu.${NC}"
    fi
    echo
}
# Logga en filöverföring till historikfilen
log_file_transfer() {
    local source=$1
    local destination=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local transfer_log="$HOME/.myapp-transfers.log"
    
    # Skapa logfilen om den inte finns
    touch "$transfer_log"
    
    # Begränsa filnamnet om det är för långt
    local short_source
    if [[ ${#source} -gt 40 ]]; then
        short_source="...${source: -40}"
    else
        short_source="$source"
    fi
    
    # Lägg till överföringen i loggen (i början av filen)
    echo "$timestamp | $short_source | $destination" | cat - "$transfer_log" > /tmp/templog && mv /tmp/templog "$transfer_log"
    
    # Behåll bara de 100 senaste överföringarna
    tail -n 100 "$transfer_log" > /tmp/templog && mv /tmp/templog "$transfer_log"
}

# Visa senaste filöverföringar
show_recent_transfers() {
    local transfer_log="$HOME/.myapp-transfers.log"
    local count=${1:-5} # Antal överföringar att visa, standard är 5
    
    echo -e "${BLUE}=== Senaste $count filöverföringar ===${NC}"
    
    if [ -f "$transfer_log" ]; then
        head -n $count "$transfer_log" | while IFS='|' read -r timestamp source destination; do
            echo -e "${YELLOW}$timestamp${NC} | ${GREEN}$source${NC} | ${BLUE}$destination${NC}"
        done
    else
        echo -e "${YELLOW}Ingen överföringshistorik finns ännu.${NC}"
    fi
    echo
}

# Funktion för att överföra filer till App Server
transfer_files() {
    echo -e "${YELLOW}Överför filer till App Server...${NC}"
    
    # Standardkatalog för överföring
    DEFAULT_REMOTE_PATH="/home/azureuser/app"
    
    # Visa senaste överföringar först
    show_recent_transfers
    
    # Fråga användaren om sökväg till lokal fil/katalog
    read -p "Ange sökväg till lokal fil eller katalog som ska överföras: " LOCAL_PATH
    
    # Hantera ~ i sökvägen (expandera till hemkatalogen)
    LOCAL_PATH="${LOCAL_PATH/#\~/$HOME}"
    
    # Kontrollera om filen/katalogen existerar
    if [ ! -e "$LOCAL_PATH" ]; then
        echo -e "${RED}Filen eller katalogen existerar inte. Försök igen.${NC}"
        return 1
    fi
    
    # Fråga användaren om målkatalog på App Server
    read -p "Ange målkatalog på App Server [$DEFAULT_REMOTE_PATH]: " REMOTE_PATH
    
    # Sätt standardvärde om inget anges
    REMOTE_PATH=${REMOTE_PATH:-$DEFAULT_REMOTE_PATH}
    
    # Visa sammanfattning innan överföring
    echo -e "${BLUE}=== Överföringsinformation ===${NC}"
    echo -e "Från: ${GREEN}$LOCAL_PATH${NC}"
    echo -e "Till: ${GREEN}myapp-appserver:$REMOTE_PATH${NC}"
    
    # Be om bekräftelse
    read -p "Fortsätt med överföringen? (j/n): " CONFIRM
    if [[ ! $CONFIRM =~ ^[Jj]$ ]]; then
        echo -e "${YELLOW}Överföring avbruten.${NC}"
        return 0
    fi
    
    # Skapa målkatalogen om den inte finns
    echo -e "${YELLOW}Kontrollerar om målkatalogen finns på servern...${NC}"
    ssh myapp-appserver "mkdir -p $REMOTE_PATH"
    
    # Visa progress under överföringen
    echo -e "${GREEN}Överför till App Server...${NC}"
    
    # Använd SCP för överföring med rekursiv flagga för kataloger
    scp -r "$LOCAL_PATH" "myapp-appserver:$REMOTE_PATH"
    
    # Kontrollera om överföringen lyckades
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Filöverföring slutförd!${NC}"
        update_timestamp "transfer_files"
        
        # Logga den lyckade överföringen
        log_file_transfer "$LOCAL_PATH" "myapp-appserver:$REMOTE_PATH"
    else
        echo -e "${RED}Filöverföring misslyckades.${NC}"
        echo -e "${YELLOW}Tips: Kontrollera att du har rätt behörigheter på servern.${NC}"
    fi
}

# Funktion för att visa meny och hantera val
show_menu() {
    # Hämta timestamps
    local config_time=$(get_timestamp "update_ssh_config")
    local clean_time=$(get_timestamp "clean_host_keys")
    local setup_time=$(get_timestamp "setup_bastion_access")
    local transfer_time=$(get_timestamp "transfer_files")
    
    echo -e "${BLUE}===== MyApp Cloud Infrastructure =====${NC}"
    echo -e "${YELLOW}Bastion IP:${NC} ${BASTION_IP}"
    echo -e "${YELLOW}Reverse Proxy IP:${NC} ${REVERSEPROXY_IP}"
    echo -e "${YELLOW}App Server IP:${NC} ${APPSERVER_IP}"
    echo
    echo "Välj en server att ansluta till:"
    echo "1) Bastion"
    echo "2) Reverse Proxy Server"
    echo "3) App Server (.NET)"
    echo -e "4) Uppdatera ~/.ssh/config auto ${YELLOW}(Senast ändrad: $config_time)${NC}"
    echo -e "5) Rensa ALLA SSH-nycklar ${YELLOW}(Senast ändrad: $clean_time)${NC}"
    echo -e "6) Sätt upp SSH-åtkomst på Bastion mellan servrarna ${YELLOW}(Senast konfigurerad: $setup_time)${NC}"
    echo -e "7) Överför filer med SCP lokalt till App Server ${YELLOW}(Senast: $transfer_time)${NC}"
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
            transfer_files
            ;;
        q|Q)
            echo -e "${YELLOW}Avslutar${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Ogiltigt val, försök igen.${NC}"
            ;;
    esac
}

echo -e "${YELLOW}Hämtar information om din molninfrastruktur...${NC}"

# Kontrollera om IP-adresser kunde hämtas
if [ -z "$BASTION_IP" ]; then
    echo -e "${RED}Kunde inte hämta Bastion IP-adress. Kontrollera att deploymentet finns.${NC}"
    echo "Du kan ange IP-adressen manuellt genom att redigera variabeln BASTION_IP i skriptet."
    exit 1
fi

if [ -z "$REVERSEPROXY_IP" ]; then
    echo -e "${YELLOW}Varning: Kunde inte hämta Reverse Proxy IP-adress. Använder standardvärde 10.0.2.4${NC}"
    REVERSEPROXY_IP="10.0.2.4"
fi

if [ -z "$APPSERVER_IP" ]; then
    echo -e "${YELLOW}Varning: Kunde inte hämta App Server IP-adress. Använder standardvärde 10.0.3.4${NC}"
    APPSERVER_IP="10.0.3.4"
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