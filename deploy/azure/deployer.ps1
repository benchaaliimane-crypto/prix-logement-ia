# Déploiement Azure (Container Registry + Container Apps) — phase 6, parcours A.
# Prérequis : Docker Desktop démarré, image prix-logement-api:1.0.0 construite, az login fait.
# Usage (depuis la racine du projet) :  .\deploy\azure\deployer.ps1
$ErrorActionPreference = "Stop"

$RG = "rg-prix-logement"
$LOC = "francecentral"
$ENVIRONNEMENT = "env-prix-logement"
$APP = "api-prix-logement"

# Le nom du registre doit être unique dans tout Azure : on le génère une fois et on le garde.
$FICHIER_ACR = "deploy\azure\nom_registre.txt"
if (Test-Path $FICHIER_ACR) { $ACR = (Get-Content $FICHIER_ACR).Trim() }
else { $ACR = "acrprix" + (Get-Random -Minimum 10000 -Maximum 99999); Set-Content $FICHIER_ACR $ACR }
$IMAGE = "$ACR.azurecr.io/prix-logement-api:1.0.0"
"Registre : $ACR   Image : $IMAGE"

az extension add --name containerapp --upgrade --only-show-errors
foreach ($ns in "Microsoft.App","Microsoft.OperationalInsights","Microsoft.ContainerRegistry") {
  az provider register --namespace $ns --wait
}

az group create --name $RG --location $LOC --query properties.provisioningState --output tsv
az acr create --resource-group $RG --name $ACR --sku Basic --admin-enabled true --query provisioningState --output tsv

az acr login --name $ACR
docker tag prix-logement-api:1.0.0 $IMAGE
docker push $IMAGE
az acr repository show-tags --name $ACR --repository prix-logement-api --output table

az containerapp env create --name $ENVIRONNEMENT --resource-group $RG --location $LOC --query properties.provisioningState --output tsv

$MDP_ACR = az acr credential show --name $ACR --query "passwords[0].value" --output tsv
az containerapp create `
  --name $APP --resource-group $RG --environment $ENVIRONNEMENT `
  --image $IMAGE `
  --registry-server "$ACR.azurecr.io" --registry-username $ACR --registry-password $MDP_ACR `
  --target-port 8000 --ingress external `
  --cpu 0.5 --memory 1.0Gi --min-replicas 0 --max-replicas 2 `
  --query properties.configuration.ingress.fqdn --output tsv

$URL = "https://" + (az containerapp show --name $APP --resource-group $RG --query properties.configuration.ingress.fqdn --output tsv)
Set-Content "deploy\azure\url.txt" $URL
"URL publique : $URL"

# Validation (phase 7) : 1re requête lente = démarrage à froid (min-replicas 0), c'est normal.
python outils\tester_url.py $URL | Tee-Object -FilePath validation_cloud.txt
az containerapp logs show --name $APP --resource-group $RG --tail 30
