// ===================================================================
// BASTION.BICEP
// ===================================================================
// Denna fil definierar min Bastion-server (Jump station) som utgör
// det första säkerhetslagret i min arkitektur. Bastion-servern är den
// enda servern med publik SSH-åtkomst och fungerar som ingångspunkt
// till resten av min miljö.
//
// Funktioner:
// - Publik IP-adress för åtkomst från internet
// - SSH-nyckelbaserad autentisering (inga lösenord)
// - Automatisk konfiguration via Custom Script Extension
//
// Senast uppdaterad: 2024-03-23
// ===================================================================

// --- Grundläggande parametrar ---
@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Subnet-ID för Bastion')
param subnetId string

@description('Admin-användarnamn för VM')
param adminUsername string

@description('SSH-nyckel för admin-användaren')
@secure()  // Markerad som säker så att den inte loggas
param adminPublicKey string

@description('Miljöns typ (dev, test, prod)')
param environmentType string

// --- VM-konfiguration ---
var vmSize = environmentType == 'prod' ? 'Standard_B2s' : 'Standard_B1s'

// --- Publik IP för Bastion ---
// Skapar en statisk publik IP så att den inte ändras vid omstart
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-bastion-ip'
  location: location
  sku: {
    name: 'Standard'  // Standard SKU ger bättre SLA och säkerhet
  }
  properties: {
    publicIPAllocationMethod: 'Static'  // Statisk IP så den inte ändras
    dnsSettings: {
      domainNameLabel: '${prefix}-bastion'
    }
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// --- Nätverksgränssnitt för Bastion ---
// Konfigurerar nätverkskortet för VM:en med publik IP
// och kopplar direkt till min NSG för extra säkerhet
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${prefix}-bastion-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId  // Kopplar till det subnet som skickats in som parameter
          }
          publicIPAddress: {
            id: publicIp.id  // Refererar till den publika IP jag skapade ovan
          }
        }
      }
    ]
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// --- Laddar Bash-skriptet för konfiguration ---
// Konverterar skriptet till base64 för att det ska kunna skickas till VM:en
var bastionSetupScript = loadFileAsBase64('../../azure-deployment/scripts/bastion-setup.sh')

// --- Bastion VM ---
resource bastionVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: '${prefix}-bastion-vm'
  location: location
  identity: {
    type: 'SystemAssigned'  // Managed identity för att hantera autentisering
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy' 
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'  
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id  // Kopplar till nätverksgränssnittet jag skapade ovan
        }
      ]
    }
    osProfile: {
      computerName: '${prefix}-bastion'  
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true  // Inaktiverar lösenordsautentisering för säkerhet
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey  // Använder SSH-nyckeln från parametern
            }
          ]
        }
      }
    }
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// --- Custom Script Extension för Bastion ---
// Kör bastion-setup.sh skriptet automatiskt efter VM-skapande
// Detta installerar fail2ban, konfigurerar SSH och skapar SSH-nycklar för interna servrar
resource bastionVmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: bastionVm  // Kopplar som child-resurs till VM:en
  name: 'setup-script'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      skipDos2Unix: false  // Viktigt för att hantera linjeändelser korrekt
    }
    protectedSettings: {
      script: bastionSetupScript  // Base64-kodade skriptet
    }
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// --- Outputs ---
// Exporterar viktiga värden som behövs i andra moduler eller för åtkomst
output publicIpAddress string = publicIp.properties.ipAddress
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
