# Phase 7.7 : supprimer TOUTES les ressources Azure du TP (registre, environnement, app, Log Analytics).
$RG = "rg-prix-logement"
az group delete --name $RG --yes
az group exists --name $RG   # doit afficher false -> capture pour le compte rendu
docker rm -f api-logement 2>$null
