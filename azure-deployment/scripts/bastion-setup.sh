#!/bin/bash
# scripts/bastion-setup.sh
# Konfigurationsscript för Bastion-värden med förbättrad SSH-konfiguration

# Uppdatera systemet
apt-get update
apt-get upgrade -y

# Installera fail2ban för att skydda mot brute force-attacker
apt-get install -y fail2ban
apt-get install -y netcat-openbsd

# Konfigurera fail2ban för SSH-skydd
cat > /etc/fail2ban/jail.local << 'EOL'
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOL

# Starta om fail2ban för att ladda konfigurationen
systemctl restart fail2ban

# Konfigurera SSH för mer säkerhet
cat > /etc/ssh/sshd_config.d/security.conf << 'EOL'
# Säkrare SSH-konfiguration
PermitRootLogin no
PasswordAuthentication no
AllowAgentForwarding yes
X11Forwarding no
EOL

# Generera en intern SSH-nyckel för Bastion-användaren
# Denna nyckel kommer användas för att ansluta från Bastion till de interna servrarna
su - azureuser -c "ssh-keygen -t rsa -b 4096 -f ~/.ssh/internal_id_rsa -N ''"

# Skapa en katalog för SSH-konfigurationen om den inte finns
mkdir -p /etc/ssh/ssh_config.d/
mkdir -p /home/azureuser/.ssh/

# Konfigurera global SSH-agentvidarebefordran
cat > /etc/ssh/ssh_config.d/agent_forwarding.conf << 'EOL'
# SSH-agentvidarebefordran
Host *
    ForwardAgent yes
EOL

# Skapa en SSH-konfigurationsfil för användaren
cat > /home/azureuser/.ssh/config << 'EOL'
# SSH-konfiguration för enkel åtkomst till interna servrar

# Allmänna inställningar för alla hosts
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 10
    ForwardAgent yes

# ReverseProxy - direkt åtkomst från Bastion
Host reverseproxy
    HostName 10.0.2.4
    User azureuser
    IdentityFile ~/.ssh/internal_id_rsa

# AppServer - direkt åtkomst från Bastion
Host appserver
    HostName 10.0.3.4
    User azureuser
    IdentityFile ~/.ssh/internal_id_rsa
EOL

# Sätta lämpliga behörigheter på SSH-konfigurationsfiler
chmod 644 /etc/ssh/sshd_config.d/security.conf
chmod 644 /etc/ssh/ssh_config.d/agent_forwarding.conf
chmod 700 /home/azureuser/.ssh
chmod 600 /home/azureuser/.ssh/config
chmod 600 /home/azureuser/.ssh/internal_id_rsa
chmod 644 /home/azureuser/.ssh/internal_id_rsa.pub
chown -R azureuser:azureuser /home/azureuser/.ssh

# Starta om SSH-tjänsten för att ladda ny konfiguration
systemctl restart sshd

# Skapa ett skript för att distribuera den genererade nyckeln till interna servrar
cat > /home/azureuser/setup_ssh_access.sh << 'EOL'
#!/bin/bash
# Detta skript konfigurerar SSH-åtkomst till interna servrar

# Funktion för att vänta tills en server är redo
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

# Vänta tills servrar är redo
wait_for_ssh $REVERSEPROXY_IP
wait_for_ssh $APPSERVER_IP

# Kopiera SSH-nyckeln till varje server
echo "Kopierar SSH-nyckeln till ReverseProxy..."
ssh-copy-id -i ~/.ssh/internal_id_rsa.pub -o StrictHostKeyChecking=no azureuser@$REVERSEPROXY_IP

echo "Kopierar SSH-nyckeln till AppServer..."
ssh-copy-id -i ~/.ssh/internal_id_rsa.pub -o StrictHostKeyChecking=no azureuser@$APPSERVER_IP

echo "SSH-åtkomst har konfigurerats för alla interna servrar!"
echo "Du kan nu använda: ssh reverseproxy eller ssh appserver"
EOL

# Gör distributionsskriptet körbart
chmod +x /home/azureuser/setup_ssh_access.sh
chown azureuser:azureuser /home/azureuser/setup_ssh_access.sh

# Loggmeddelande
echo "Bastion-konfiguration slutförd $(date)" >> /var/log/bastion-setup.log
echo "Du behöver köra: ./setup_ssh_access.sh för att konfigurera SSH-åtkomst till interna servrar" >> /var/log/bastion-setup.log

####################################