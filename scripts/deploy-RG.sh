#!/bin/zsh

# Definiera variabler
RESOURCE_GROUP="AppRG"
LOCATION="westeurope"  # Välj lämplig region

# Metod 1: Skapa resursgruppen direkt
echo "Skapar resursgrupp $RESOURCE_GROUP i $LOCATION..."
az group create --name $RESOURCE_GROUP --location $LOCATION


echo "Fortsätter med deployment av resurser..."
