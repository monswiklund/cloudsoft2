// ===================================================================
// NETWORKING.BICEP
// ===================================================================
// Här definierar jag hela nätverksarkitekturen för min säkra molnmiljö.
// Skapar virtuellt nätverk (VNet), subnät och alla nätverkssäkerhetsgrupper (NSG)
// för att implementera min "defense-in-depth"-strategi.
// 
// Min säkerhetsdesign:
// 1. Bastion: Enda servern med extern SSH-åtkomst
// 2. Reverse Proxy: Extern HTTP-åtkomst, SSH endast från Bastion
// 3. App Server: Helt isolerad - endast tillgänglig internt
// 
// Senast uppdaterad: 2024-03-23
// ===================================================================

// --- Inparametrar som styr resursskapandet ---
@description('Prefix för alla resurser i deploymentet')
param prefix string

@description('Plats för alla resurser')
param location string

@description('Miljöns typ (dev, test, prod)')
param environmentType string

// --- Nätverkskonfiguration ---
// Här definierar jag alla IP-adressrymder för mitt virtuella nätverk och subnät
// Använder 10.0.0.0/16 med separata /24-subnät

var vnetAddressPrefix = '10.0.0.0/16'  // Ger mig 65,536 IP-adresser totalt
var bastionSubnetPrefix = '10.0.1.0/24'  // 254 tillgängliga IP-adresser, 
var reverseProxySubnetPrefix = '10.0.2.0/24'  // 254 tillgängliga IP-adresser
var appServerSubnetPrefix = '10.0.3.0/24'  // 254 tillgängliga IP-adresser

// ===================================================================
// NÄTVERKSSÄKERHETSGRUPPER (NSG)
// ===================================================================
// NSG:er är virtuella brandväggar som kontrollerar inkommande och utgående 
// trafik till Azure-resurser i virtuella nätverk.

// --- Bastion NSG --- 
// Denna NSG tillåter endast SSH (port 22) från internet till min Bastion-server
// Bastion fungerar som min "jump server" - den enda servern med extern SSH-åtkomst
resource bastionNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-bastion-nsg'
  location: location
  properties: {
    securityRules: [
      // Tillåter SSH-anslutningar från internet
      {
        name: 'AllowSshInbound'
        properties: {
          priority: 100  // Lägre nummer = högre prioritet
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'  // Använder tjänstetagg istället för * för ökad säkerhet
          sourcePortRange: '*'  // Källportar är dynamiska
          destinationAddressPrefix: '*'  // Gäller alla IP-adresser i subnätet
          destinationPortRange: '22'  // SSH-port
          description: 'Tillåt SSH från internet'
        }
      }
      // Nekar all annan inkommande trafik (fallback-regel)
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096  // Högst möjliga prioritet (körs sist)
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'  // Alla protokoll
          sourceAddressPrefix: '*'  // Alla källor
          sourcePortRange: '*'  // Alla källportar
          destinationAddressPrefix: '*'  // Alla mål
          destinationPortRange: '*'  // Alla målportar
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

// --- Reverse Proxy NSG ---
// Denna NSG tillåter:
// 1. HTTP (port 80) från internet
// 2. SSH (port 22) ENDAST från Bastion-subnätet
// 3. Nekar all annan trafik
resource reverseProxyNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-reverseproxy-nsg'
  location: location
  properties: {
    securityRules: [
      // Tillåter HTTP från internet (för webbapplikationen)
      {
        name: 'AllowHttpInbound'
        properties: {
          priority: 100 // Lägre prioritet än SSH-regeln
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
          description: 'Tillåt HTTP från internet'
        }
      }
      // Tillåter SSH ENDAST från Bastion-subnätet (för säker administration)
      {
        name: 'AllowSshFromBastion'
        properties: {
          priority: 200 // Lägre prioritet än HTTP-regeln
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix  // Endast från Bastion
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Tillåt SSH endast från Bastion'
        }
      }
      // Nekar all annan inkommande trafik
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096 // Högsta prioritet (körs sist)
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

// --- App Server NSG ---
// Denna NSG är mest restriktiv och tillåter:
// 1. HTTP på port 5000 ENDAST från Reverse Proxy-subnätet
// 2. SSH (port 22) ENDAST från Bastion-subnätet
// 3. Nekar all annan trafik
// Detta gör min App Server helt isolerad från internet
resource appServerNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-appserver-nsg'
  location: location
  properties: {
    securityRules: [
      // Tillåter HTTP (5000) ENDAST från Reverse Proxy
      {
        name: 'AllowHttpFromReverseProxy'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: reverseProxySubnetPrefix  // Endast från Reverse Proxy
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5050'  // Lyssnar på 5000
          description: 'Tillåt HTTP (5000) endast från Reverse Proxy'
        }
      }
      // Tillåter SSH ENDAST från Bastion-subnätet (för säker administration)
      {
        name: 'AllowSshFromBastion'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix  // Endast från Bastion
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'Tillåt SSH endast från Bastion'
        }
      }
      // Nekar all annan inkommande trafik
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

// ===================================================================
// VIRTUELLT NÄTVERK MED SUBNÄT
// ===================================================================
// Skapar mitt huvudsakliga virtuella nätverk med tre separata subnät
// Varje subnät är kopplat till sin egen NSG för granulär säkerhetskontroll
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    // Definerar tre logiskt separerade subnät
    subnets: [
      {
        name: 'BastionSubnet'  // Min Jump för säker åtkomst
        properties: {
          addressPrefix: bastionSubnetPrefix
          networkSecurityGroup: {
            id: bastionNsg.id  // Kopplar till tidigare definierade NSG
          }
        }
      }
      {
        name: 'ReverseProxySubnet'  // Min Nginx-proxy som exponerar HTTP
        properties: {
          addressPrefix: reverseProxySubnetPrefix
          networkSecurityGroup: {
            id: reverseProxyNsg.id  // Kopplar till tidigare definierade NSG
          }
        }
      }
      {
        name: 'AppServerSubnet'  // Min isolerade .NET-applikationsserver
        properties: {
          addressPrefix: appServerSubnetPrefix
          networkSecurityGroup: {
            id: appServerNsg.id  // Kopplar till tidigare definierade NSG
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

// ===================================================================
// OUTPUTS
// ===================================================================
// Exporterar subnäts-ID för användning i andra Bicep-moduler
// Detta gör att jag kan referera till subnäten när jag skapar VM:ar
output bastionSubnetId string = vnet.properties.subnets[0].id
output reverseProxySubnetId string = vnet.properties.subnets[1].id
output appServerSubnetId string = vnet.properties.subnets[2].id
