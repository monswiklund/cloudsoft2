// modules/reverseproxy.bicep
@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Subnet-ID för Reverse Proxy')
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

// Skapa nätverksgränssnitt för Reverse Proxy
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
            id: publicIp.id
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

// Skapa publik IP för Reverse Proxy
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-reverseproxy-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// Hämta innehållet i Bash-skriptet för Nginx-konfiguration
var nginxSetupScript = loadFileAsBase64('../scripts/nginx-setup.sh')

// Skapa Reverse Proxy VM
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
      computerName: '${prefix}-reverseproxy'
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

// Använd Custom Script Extension för att konfigurera Nginx
resource reverseProxyVmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: reverseProxyVm
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
      script: nginxSetupScript
    }
  }
}

// Outputs
output publicIpAddress string = publicIp.properties.ipAddress
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
