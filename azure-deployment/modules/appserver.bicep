// ===================================================================
// APPSERVER.BICEP
// ===================================================================
// Den här filen definierar min App Server som kör min .NET-applikation.
// App Server är den mest isolerade komponenten i min arkitektur och
// har ingen direkt exponering mot internet. All åtkomst sker via
// Reverse Proxy (HTTP) eller Bastion (SSH).
//
// Funktioner:
// - Helt intern VM utan publik IP
// - Kör min .NET-applikation
// - Automatisk konfiguration via Custom Script Extension
//
// Senast uppdaterad: 2024-03-23
// ===================================================================

// --- Grundläggande parametrar ---
@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Subnet-ID för App Server')
param subnetId string

@description('Admin-användarnamn för VM')
param adminUsername string

@description('SSH-nyckel för admin-användaren')
@secure()  // Säkerhetsmarkering för att skydda nyckeln
param adminPublicKey string

@description('Miljöns typ (dev, test, prod)')
param environmentType string

// --- VM-konfiguration ---
// Anpassar storleken baserat på miljö för kostnadsoptimering
var vmSize = environmentType == 'prod' ? 'Standard_B2s' : 'Standard_B1s'

// --- Nätverksgränssnitt för App Server ---
// Ingen publik IP kopplas här, endast internt nätverk
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${prefix}-appserver-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'  // Låter Azure välja en ledig IP
          subnet: {
            id: subnetId  // Kopplar till det isolerade App Server-subnätet
          }
          // Ingen publicIPAddress definierad här - detta är en säkerhetsåtgärd
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
// Skriptet installerar .NET SDK, skapar en demo-app och konfigurerar den som en tjänst
var appServerSetupScript = loadFileAsBase64('../scripts/appserver-setup.sh')

// --- App Server VM ---
resource appServerVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: '${prefix}-appserver-vm'
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
          id: nic.id  // Kopplar till det privata nätverksgränssnittet
        }
      ]
    }
    osProfile: {
      computerName: '${prefix}-appserver'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true  // Endast SSH-nyckelbaserad autentisering
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminPublicKey
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

// --- Custom Script Extension för App Server ---
// Kör appserver-setup.sh automatiskt efter VM-skapande för att
// installera .NET SDK, skapa demo-appen och konfigurera systemd-tjänsten
resource appServerVmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: appServerVm  // Kopplar som child-resurs till VM:en
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
      script: appServerSetupScript  // Base64-kodade skriptet
    }
  }
}

// --- Outputs ---
// Exporterar den privata IP-adressen för användning i andra moduler
// Speciellt viktigt för Reverse Proxy-konfigurationen som behöver veta var App Server finns
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
