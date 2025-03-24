#!/bin/bash
# ===================================================================
# BASTION-SETUP.SH
# ===================================================================
# Konfigurationsscript för min Bastion-server (jump host)
# Denna server fungerar som den enda ingångspunkten till min infrastruktur
# via SSH, och måste därför vara extra säker.
#
# Skriptet gör följande:
# 1. Installerar fail2ban för att förhindra brute force-attacker
# 2. Konfigurerar säker SSH (ingen root, inga lösenord)
# 3. Genererar SSH-nycklar för åtkomst till interna servrar
# 4. Skapar SSH-konfigurationsfiler för enkel åtkomst
# 5. Skapar ett skript för att distribuera SSH-nycklar
#
# Senast uppdaterad: 2024-03-23
# ===================================================================

# --- Systemuppdatering ---
# Alltid bra att börja med en uppdaterad server för att täppa igen säkerhetshål
apt-get update
apt-get upgrade -y

# --- Säkerhetsverktyg ---
# Fail2ban övervakar misslyckade inloggningsförsök och blockerar IP-adresser
# netcat behövs för att testa SSH-anslutningar i setup-skriptet
apt-get install -y fail2ban
apt-get install -y netcat-openbsd

# --- Fail2ban-konfiguration ---
# Anpassad fail2ban-konfiguration som bannar IP-adresser efter 3 misslyckade försök i 1 timme
cat > /etc/fail2ban/jail.local << 'EOL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3       # Bannar efter 3 försök
bantime = 3600     # Bannar i 1 timme (3600 sekunder)
EOL

# Aktiverar nya fail2ban-konfigurationen
systemctl restart fail2ban

# --- SSH-säkerhetskonfiguration ---
# Skapar en ny SSH-konfiguration med stärkta säkerhetsinställningar
cat > /etc/ssh/sshd_config.d/security.conf << 'EOL'
# Säkrare SSH-konfiguration
PermitRootLogin no             # Förbjuder root-inloggning
PasswordAuthentication no      # Endast nyckelbaserad autentisering
AllowAgentForwarding yes       # Tillåter SSH agent-vidarebefordran för att slippa kopiera nycklar
X11Forwarding no               # Stänger av X11-vidarebefordran för säkerhet
EOL

# --- Generera interna SSH-nycklar ---
# Skapar en dedikerad SSH-nyckel för användaren som används för att ansluta till interna servrar
# -t rsa: Använder RSA-algoritm
# -b 4096: Använder 4096 bitar för extra säkerhet
# -N '': Ingen lösenfras (för automatisering)
su - azureuser -c "ssh-keygen -t rsa -b 4096 -f ~/.ssh/internal_id_rsa -N ''"

# --- Katalogstruktur för SSH ---
# Skapar nödvändiga kataloger om de inte redan finns
mkdir -p /etc/ssh/ssh_config.d/
mkdir -p /home/azureuser/.ssh/

# --- Global SSH-konfiguration ---
# Konfigurerar global SSH-agentvidarebefordran för alla användare
cat > /etc/ssh/ssh_config.d/agent_forwarding.conf << 'EOL'
# SSH-agentvidarebefordran
Host *
    ForwardAgent yes   # Tillåter att min SSH-agent skickas vidare till servrar jag ansluter till
EOL

# --- Användarspecifik SSH-konfiguration ---
# Skapar en användarvänlig SSH-config som gör det enkelt att ansluta till interna servrar
cat > /home/azureuser/.ssh/config << 'EOL'
# SSH-konfiguration för enkel åtkomst till interna servrar

# Allmänna inställningar för alla hosts
Host *
    StrictHostKeyChecking no     # Undviker hostkey-verifiering (bara i utvecklingsmiljö!)
    UserKnownHostsFile /dev/null # Ignorerar known_hosts-filen (bara i utvecklingsmiljö!)
    ServerAliveInterval 60       # Skickar keep-alive var 60:e sekund
    ServerAliveCountMax 10       # Tillåter 10 missade keep-alive innan nedkoppling
    ForwardAgent yes             # Tillåter SSH-agent-vidarebefordran

# ReverseProxy - direkt åtkomst från Bastion
Host reverseproxy
    HostName 10.0.2.4            # Fast IP för Reverse Proxy
    User azureuser
    IdentityFile ~/.ssh/internal_id_rsa

# AppServer - direkt åtkomst från Bastion
Host appserver
    HostName 10.0.3.4            # Fast IP för App Server
    User azureuser
    IdentityFile ~/.ssh/internal_id_rsa
EOL

# --- Sätt korrekta filrättigheter ---
# SSH är känsligt för fel filrättigheter och vägrar fungera om filerna är för öppna
chmod 644 /etc/ssh/sshd_config.d/security.conf
chmod 644 /etc/ssh/ssh_config.d/agent_forwarding.conf
chmod 700 /home/azureuser/.ssh                    # Endast användaren får åtkomst till .ssh-mappen
chmod 600 /home/azureuser/.ssh/config             # Konfigurationsfilen måste vara strikt privat
chmod 600 /home/azureuser/.ssh/internal_id_rsa    # Privata nyckeln måste vara strikt privat
chmod 644 /home/azureuser/.ssh/internal_id_rsa.pub # Publika nyckeln kan vara läsbar för alla
chown -R azureuser:azureuser /home/azureuser/.ssh # Användaren måste äga alla sina filer

# Startar om SSH-tjänsten för att aktivera nya inställningar
systemctl restart sshd

# --- Skript för SSH-nyckelspridning ---
# Skapar ett hjälpskript som distribuerar den genererade SSH-nyckeln till interna servrar
cat > /home/azureuser/setup_ssh_access.sh << 'EOL'
#!/bin/bash
# Detta skript konfigurerar SSH-åtkomst till interna servrar

# Funktion för att vänta tills en server är redo
# Använder netcat för att testa om SSH-porten är öppen
wait_for_ssh() {
    local host=$1
    local max_retries=30
    local retry=0
    
    echo "Väntar på att $host ska vara redo för SSH..."
    while ! nc -z $host 22 2>/dev/null; do
        retry=$((retry+1))
        if [ $retry -ge $max_retries ]; then
            echo "Timeout: Kunde inte ansluta till $host efter $max_retries försök"
            return 1
        fi
        echo "Försök $retry av $max_retries - $host är inte redo. Väntar 10 sekunder..."
        sleep 10
    done
    echo "$host är nu redo för SSH!"
    return 0
}

# IP-adresser till interna servrar
REVERSEPROXY_IP="10.0.2.4"
APPSERVER_IP="10.0.3.4"

# Vänta tills servrarna är redo att ta emot SSH-anslutningar
# Detta är viktigt eftersom VMs kan starta i olika takt
wait_for_ssh $REVERSEPROXY_IP
wait_for_ssh $APPSERVER_IP

# Kopierar SSH-nyckeln till varje server med ssh-copy-id
# -o StrictHostKeyChecking=no: Ignorerar host key-verifiering vid första anslutning
echo "Kopierar SSH-nyckeln till ReverseProxy..."
ssh-copy-id -i ~/.ssh/internal_id_rsa.pub -o StrictHostKeyChecking=no azureuser@$REVERSEPROXY_IP

echo "Kopierar SSH-nyckeln till AppServer..."
ssh-copy-id -i ~/.ssh/internal_id_rsa.pub -o StrictHostKeyChecking=no azureuser@$APPSERVER_IP

echo "SSH-åtkomst har konfigurerats för alla interna servrar!"
echo "Du kan nu använda: ssh reverseproxy eller ssh appserver"
EOL

# Gör skriptet körbart och sätt rätt ägare
chmod +x /home/azureuser/setup_ssh_access.sh
chown azureuser:azureuser /home/azureuser/setup_ssh_access.sh

# --- Loggmeddelande ---
# Skriver slutmeddelanden till loggfilen för att dokumentera installationen
echo "Bastion-konfiguration slutförd $(date)" >> /var/log/bastion-setup.log
echo "Du behöver köra: ./setup_ssh_access.sh för att konfigurera SSH-åtkomst till interna servrar" >> /var/log/bastion-setup.log