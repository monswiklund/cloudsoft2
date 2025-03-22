// modules/appserver.bicep
@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Subnet-ID för App Server')
param subnetId string

@description('Admin-användarnamn för VM')
param adminUsername string

@description('SSH-nyckel för admin-användaren')
@secure()
param adminPublicKey string

@description('Miljöns typ (dev, test, prod)')
param environmentType string

// VM-storlek baserat på miljö
var vmSize = environmentType == 'prod' ? 'Standard_B2s' : 'Standard_B1s'

// Skapa nätverksgränssnitt för App Server
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${prefix}-appserver-nic'
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
        }
      }
    ]
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// Hämta innehållet i Bash-skriptet för App Server-konfiguration
var appServerSetupScript = loadFileAsBase64('../scripts/appserver-setup.sh')

// Skapa App Server VM
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
        offer: '0001-com-ubuntu-server-jammy' // Ubuntu 22.04 LTS
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
          id: nic.id
        }
      ]
    }
    osProfile: {
      computerName: '${prefix}-appserver'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
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

// Använd Custom Script Extension för att konfigurera App Server
resource appServerVmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: appServerVm
  name: 'setup-script'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      skipDos2Unix: false
    }
    protectedSettings: {
      script: appServerSetupScript
    }
  }
}

// Outputs
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
