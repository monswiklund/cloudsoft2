@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Miljöns typ (dev, test, prod)')
param environmentType string

// Nätverksadressrymder
var vnetAddressPrefix = '10.0.0.0/16'
var bastionSubnetPrefix = '10.0.1.0/24'
var reverseProxySubnetPrefix = '10.0.2.0/24'  // Tidigare webServerSubnetPrefix
var appServerSubnetPrefix = '10.0.3.0/24'

// NSG för Bastion - tillåt SSH från internet
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-bastion-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSshInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'  // Använder tjänstetagg istället för *
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Tillåt SSH från internet'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Neka all annan inkommande trafik'
        }
      }
    ]
  }
  tags: { 
    application: prefix
    environment: environmentType
  
  }
}

// NSG för Reverse Proxy - tillåt HTTP från internet och SSH endast från Bastion
resource reverseProxyNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-reverseproxy-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpInbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'  // Använder tjänstetagg istället för *
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          description: 'Tillåt HTTP från internet'
        }
      }
      {
        name: 'AllowSshFromBastion'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Tillåt SSH endast från Bastion'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Neka all annan inkommande trafik'
        }
      }
    ]
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// NSG för App Server - tillåt HTTP (5000) endast från Reverse Proxy och SSH endast från Bastion
resource appServerNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-appserver-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHttpFromReverseProxy'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: reverseProxySubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5000'
          description: 'Tillåt HTTP (5000) endast från Reverse Proxy'
        }
      }
      {
        name: 'AllowSshFromBastion'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Tillåt SSH endast från Bastion'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Neka all annan inkommande trafik'
        }
      }
    ]
  }
  tags: {
    application: prefix
    environment: environmentType
  }
}

// Skapa ett virtuellt nätverk med tre subnät
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'BastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: {
            id: bastionNsg.id
          }
        }
      }
      {
        name: 'ReverseProxySubnet'
        properties: {
          addressPrefix: reverseProxySubnetPrefix
          networkSecurityGroup: {
            id: reverseProxyNsg.id
          }
        }
      }
      {
        name: 'AppServerSubnet'
        properties: {
          addressPrefix: appServerSubnetPrefix
          networkSecurityGroup: {
            id: appServerNsg.id
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

// Outputs för subnäts-ID:n
output bastionSubnetId string = vnet.properties.subnets[0].id
output reverseProxySubnetId string = vnet.properties.subnets[1].id
output appServerSubnetId string = vnet.properties.subnets[2].id
