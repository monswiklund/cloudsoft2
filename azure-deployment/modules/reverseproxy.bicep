// ===================================================================
// REVERSEPROXY.BICEP
// ===================================================================
// Den här filen definierar min Reverse Proxy-server (Nginx) som fungerar
// som frontserver för min applikation. Reverse Proxy tar emot all extern
// HTTP-trafik och skickar den vidare till min interna App Server.
//
// Funktioner:
// - Publik IP för HTTP-åtkomst från internet
// - Intern åtkomst till App Server på port 5000
// - Automatisk konfiguration via Custom Script Extension
//
// Senast uppdaterad: 2024-03-23
// ===================================================================

// --- Grundläggande parametrar ---
@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Subnet-ID för Reverse Proxy')
param subnetId string

@description('Admin-användarnamn för VM')
param adminUsername string

@description('SSH-nyckel för admin-användaren')
@secure()  // Säkerhetsmarkering för att skydda nyckeln
param adminPublicKey string

@description('Miljöns typ (dev, test, prod)')
param environmentType string

// --- VM-konfiguration ---
var vmSize = environmentType == 'prod' ? 'Standard_B2s' : 'Standard_B1s'

// --- Nätverksgränssnitt för Reverse Proxy ---
// Detta konfigureras med både intern och publik IP
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${prefix}-reverseproxy-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: subnetId
          }
          publicIPAddress: {
            id: publicIp.id  // Kopplar till den publika IP
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

// --- Publik IP för Reverse Proxy ---
// Detta är den IP som användare kommer att ansluta till
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-reverseproxy-ip'
  location: location
  sku: {
    name: 'Standard'  // Standard ger bättre tillförlitlighet och säkerhet
  }
  properties: {
    publicIPAllocationMethod: 'Static'  // Statisk så att den inte ändras om VM:en startas om
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// --- Laddar Bash-skriptet för Nginx-konfiguration ---
// Skriptet installerar och konfigurerar Nginx som reverse proxy mot App Server
var nginxSetupScript = loadFileAsBase64('../../azure-deployment/scripts/nginx-setup.sh')

// --- Reverse Proxy VM ---
resource reverseProxyVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: '${prefix}-reverseproxy-vm'
  location: location
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
          id: nic.id  // Kopplar till nätverksgränssnittet
        }
      ]
    }
    osProfile: {
      computerName: '${prefix}-reverseproxy'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true  // Inaktiverar lösenordsautentisering för säkerhet
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey  // Använder SSH-nyckeln från parameter
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

// --- Custom Script Extension för Nginx-konfiguration ---
// Kör automatiskt nginx-setup.sh efter VM-skapande
// Detta installerar Nginx och konfigurerar det som reverse proxy mot App Server
resource reverseProxyVmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: reverseProxyVm  // Kopplar som child-resurs till VM:en
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
      script: nginxSetupScript  // Base64-kodade skriptet
    }
  }
}

// --- Outputs ---
// Exporterar både publik och privat IP för användning i andra moduler
// Publik IP behövs för att nå tjänsten, privat IP för intern kommunikation
output publicIpAddress string = publicIp.properties.ipAddress
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
