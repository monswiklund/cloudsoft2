// main.bicep
@description('Prefix för alla resurser i deploymentet')
param prefix string = 'myapp'

@description('Miljöns typ (dev, test, prod)')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentType string = 'dev'

@description('Plats för alla resurser')
param location string = resourceGroup().location

@description('Admin-användarnamn för virtuella maskiner')
param adminUsername string

@description('SSH-nyckel för admin-användaren')
@secure()
param adminPublicKey string

// Först skapar vi nätverksdelarna
module networking './modules/networking.bicep' = {
  name: 'networkingDeployment'
  params: {
    prefix: prefix
    location: location
    environmentType: environmentType
  }
}

// Sedan Bastion-värden
module bastion './modules/bastion.bicep' = {
  name: 'bastionDeployment'
  params: {
    prefix: prefix
    location: location
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: networking.outputs.bastionSubnetId
    environmentType: environmentType
  }
}

// ReverseProxy med Nginx 
module reverseProxy './modules/reverseproxy.bicep' = {
  name: 'reverseProxyDeployment'
  params: {
    prefix: prefix
    location: location
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: networking.outputs.reverseProxySubnetId
    environmentType: environmentType
  }
}

// App Server med .NET
module appServer './modules/appserver.bicep' = {
  name: 'appServerDeployment'
  params: {
    prefix: prefix
    location: location
    adminUsername: adminUsername
    adminPublicKey: adminPublicKey
    subnetId: networking.outputs.appServerSubnetId
    environmentType: environmentType
  }
}

// Outputs för att få IP-adresser
output bastionPublicIp string = bastion.outputs.publicIpAddress
output reverseProxyPublicIp string = reverseProxy.outputs.publicIpAddress
output reverseProxyPrivateIp string = reverseProxy.outputs.privateIpAddress
output appServerPrivateIp string = appServer.outputs.privateIpAddress
