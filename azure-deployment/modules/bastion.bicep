// modules/bastion.bicep
@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Subnet-ID för Bastion')
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

// Skapa NSG för Bastion med SSH-regel
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-bastion-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// Skapa publik IP för Bastion
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${prefix}-bastion-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${prefix}-bastion'
    }
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// Skapa nätverksgränssnitt för Bastion
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
            id: subnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: bastionNsg.id
    }
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// Hämta innehållet i Bash-skriptet för Bastion-konfiguration
var bastionSetupScript = loadFileAsBase64('../scripts/bastion-setup.sh')

// Skapa Bastion VM
resource bastionVm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: '${prefix}-bastion-vm'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
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
      computerName: '${prefix}-bastion'
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

// Använd Custom Script Extension för att konfigurera Bastion
resource bastionVmExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: bastionVm
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
      script: bastionSetupScript
    }
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// Outputs
output publicIpAddress string = publicIp.properties.ipAddress
output privateIpAddress string = nic.properties.ipConfigurations[0].properties.privateIPAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
