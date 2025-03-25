#!/bin/bash
# Färgkoder för utskrifter
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Konfiguration
RESOURCE_GROUP="myapp-rg"
LOCATION="westeurope"
DEPLOYMENT_NAME="myapp-deployment"
TEMPLATE_FILE="main.bicep"
PARAMETERS_FILE="parameters/main.parameters.json"
CONNECT_SCRIPT="./connect-to-cloud.sh"

echo -e "${YELLOW}Starting deployment process...${NC}"

# Kontrollera om resursgruppen finns, skapa den annars
echo "Checking if resource group exists..."
if ! az group show --name $RESOURCE_GROUP &> /dev/null; then
    echo -e "${YELLOW}Resource group '$RESOURCE_GROUP' not found. Creating it...${NC}"
    az group create --name $RESOURCE_GROUP --location $LOCATION
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create resource group. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Resource group created successfully.${NC}"
else
    echo -e "${GREEN}Resource group '$RESOURCE_GROUP' already exists.${NC}"
fi

# Validera mallen innan deployment
echo "Validating template..."
VALIDATION=$(az deployment group validate \
  --resource-group $RESOURCE_GROUP \
  --template-file $TEMPLATE_FILE \
  --parameters @$PARAMETERS_FILE 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Template validation failed:${NC}"
    echo "$VALIDATION"
    echo -e "${YELLOW}Do you want to continue anyway? (y/n)${NC}"
    read answer
    if [ "$answer" != "y" ]; then
        echo "Deployment cancelled by user."
        exit 1
    fi
fi

# Skapa deploymentet
echo -e "${YELLOW}Creating deployment...${NC}"
DEPLOYMENT_RESULT=$(az deployment group create \
  --name $DEPLOYMENT_NAME \
  --resource-group $RESOURCE_GROUP \
  --template-file $TEMPLATE_FILE \
  --parameters @$PARAMETERS_FILE)

# Kontrollera om deploymentet lyckades
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Deployment successful!${NC}"
    
    # Hämta outputs från deploymentet
    echo -e "${YELLOW}Deployment outputs:${NC}"
    OUTPUTS=$(echo $DEPLOYMENT_RESULT | jq -r '.properties.outputs')
    
    # Visa IP-adresser
    echo "Bastion Public IP: $(echo $OUTPUTS | jq -r '.bastionPublicIp.value')"
    echo "Reverse Proxy Private IP: $(echo $OUTPUTS | jq -r '.reverseProxyPrivateIp.value')"
    echo "App Server Private IP: $(echo $OUTPUTS | jq -r '.appServerPrivateIp.value')"
    
    echo -e "${GREEN}Deployment completed successfully.${NC}"
    
    # Kontrollera om connect-skriptet finns
    if [ -f "$CONNECT_SCRIPT" ]; then
        echo -e "${YELLOW}Startar uppkoppling till molninfrastrukturen...${NC}"
        
        # Gör skriptet körbart om det inte redan är det
        chmod +x "$CONNECT_SCRIPT"
        
        # Kör connect-skriptet
        "$CONNECT_SCRIPT"
    else
        echo -e "${RED}Kunde inte hitta $CONNECT_SCRIPT${NC}"
        echo -e "${YELLOW}Kontrollera att filen finns och försök köra den manuellt.${NC}"
    fi
else
    echo -e "${RED}Deployment failed:${NC}"
    echo "$DEPLOYMENT_RESULT"
    echo -e "${RED}Check the error details above and fix the issues before redeploying.${NC}"
    exit 1
fi
