# CI/CD för Azure Infrastruktur & Applikation

Detta repository innehåller både infrastrukturkod (IaC) och applikationskod för en .NET-webbtjänst som körs i en säker flerlagerarkitektur i Azure.

## Arkitekturöversikt

Lösningen består av:

1. **Bastion Host** - En hopstation för säker SSH-åtkomst
2. **Reverse Proxy** - En Nginx-server som exponerar applikationen för internet
3. **App Server** - En .NET-server som kör applikationen

## CI/CD-pipelineöversikt

Vi har två separata CI/CD-pipelines:

1. **Infrastruktur-deployment** (`azure-deploy.yml`)
   - Validerar och deployar Bicep-mallar till Azure
   - Konfigurerar det virtuella nätverket, subnät, NSGs och virtuella maskiner
   - Körs när ändringar görs i `bicep/`- eller `scripts/`-mapparna

2. **Applikations-deployment** (`app-deploy.yml`) 
   - Bygger och testar .NET-applikationen
   - Deployar applikationskod till App Server
   - Körs när ändringar görs i `src/`-mappen

## Förutsättningar för CI/CD

För att CI/CD-pipelinen ska fungera behöver du:

1. Ett Azure-konto och en resursgrupp
2. En Service Principal med behörigheter att deployra resurser
3. SSH-nycklar för deployment till virtuella maskiner
4. GitHub Secrets konfigurerade (se nedan)

## Konfigurera CI/CD-pipelinen

### 1. Azure Service Principal

```bash
az ad sp create-for-rbac --name "github-cicd-sp" --role contributor \
                          --scopes /subscriptions/{din-subscription-id} \
                          --sdk-auth
```

### 2. GitHub Secrets

Konfigurera följande secrets i ditt GitHub-repository:

- `AZURE_CREDENTIALS`: JSON-output från service principal-skapandet
- `AZURE_SUBSCRIPTION`: Din Azure-prenumerations-ID
- `AZURE_RESOURCE_GROUP`: Namnet på din resursgrupp
- `SSH_PRIVATE_KEY`: SSH-privat nyckel för att ansluta till virtuella maskiner

### 3. GitHub Environments

Skapa en environment med namn "production" med följande konfiguration:
- Required reviewers (godkännande för deployments)
- Endast deployment från main-branch

## Workflow-översikt

### Infrastruktur-deployment (`azure-deploy.yml`)

1. **Validera** - Validerar Bicep-mallar mot Azure
2. **Preview** - Kör en what-if-analys för att visa ändringar utan att applicera dem (på pull requests)
3. **Deploy** - Deployar infrastrukturen till Azure (efter godkännande)

### Applikations-deployment (`app-deploy.yml`)

1. **Build & Test** - Bygger och testar .NET-applikationen
2. **Package** - Paketerar applikationen för deployment
3. **Deploy** - Deployar applikationen till App Server via SSH (efter godkännande)

## Manuell körning av CI/CD

Du kan köra pipelinen manuellt via GitHub Actions-fliken:

1. Gå till **Actions**-fliken i ditt repository
2. Välj den workflow du vill köra
3. Klicka på **Run workflow**
4. Välj branch och klicka på **Run workflow**

## Felsökning av CI/CD

Om pipelinen misslyckas, kontrollera:

1. **Actions-loggar** - Kolla de detaljerade loggarna från GitHub Actions
2. **Azure-resurser** - Kontrollera om resurserna skapades/uppdaterades korrekt
3. **SSH-anslutning** - Verifiera att SSH-nycklar och behörigheter är korrekt konfigurerade
4. **App Server-loggarna** - SSH till App Server och kontrollera systemd-loggarna:
   ```bash
   sudo journalctl -u dotnet-app -n 100
   ```

## Best Practices

1. **Alltid arbeta i feature-branches** - Skapa PR:er mot main
2. **Testa ändringar lokalt** - Använd Azure CLI och Bicep för att testa infrastrukturändringar
3. **Incrementell utveckling** - Gör små, kontinuerliga ändringar hellre än stora uppdateringar
4. **Kodgranskning** - Se till att någon annan granskar din kod innan den mergas
5. **Övervaka deployments** - Granska loggar och prestanda efter varje deployment

## Miljöhantering

För att hantera flera miljöer (dev, test, prod), rekommenderar vi att:

1. Skapa separata parameterfiler för varje miljö
2. Använda GitHub Environments för deployment-godkännande
3. Konfigurera branch-skydd på main-branchen
