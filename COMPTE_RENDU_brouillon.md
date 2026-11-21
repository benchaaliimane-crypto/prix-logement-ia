# Compte rendu — TP Cloud Native AI Deployment (brouillon)

Imane Ben Chaali — EIDIA / UEMF
Dépôt GitHub : `<à compléter>` — URL Cloud : `<à compléter, voir deploy/azure/url.txt>`

> Les sorties ci-dessous proviennent d'une exécution réelle (Linux, Python 3.13, versions figées).
> Remplace-les par tes propres sorties/captures après exécution sur ta machine (elles doivent être identiques ou très proches).

---

## Phase 2 — Modèle

### Sortie de l'entraînement
```
[1] Lecture : 21613 lignes, 21 colonnes
[2] Après suppression des reventes : 21436 lignes
[3] Après nettoyage : 21418 lignes
[4] Découpage : 17134 pour l'entraînement, 4284 pour le test
[5] Régression linéaire       : {'MAE_usd': 120707.0, 'RMSE_usd': 309809.0, 'R2': 0.4182}
[5] Gradient boosting (choisi): {'MAE_usd': 99383.0, 'RMSE_usd': 178802.0, 'R2': 0.8062}
[6] Modèle enregistré : model/model.joblib (205 Ko)
    Empreinte SHA-256 : 1adff9588f0286bb22936012981f5c9ef7976f8ed36db04331f01277cb017032
[7] Exemple : maison de 150 m², 3 chambres, à 12 km -> 392,337 USD
```
**Interprétation.** Le gradient boosting explique ~81 % de la variance du prix sur le jeu de test (R² = 0,81) contre 0,42 pour la régression linéaire : la relation prix ↔ variables (surface, localisation, qualité) est fortement non linéaire. L'erreur absolue moyenne est ~99 k$ ; le RMSE (179 k$) est nettement plus grand que la MAE, signe que quelques biens très chers (jusqu'à 7,7 M$) produisent de grosses erreurs qui pèsent au carré.

### Questions
**1) Pourquoi évaluer sur le test et non sur l'entraînement ?**
Le modèle a vu les données d'entraînement : son erreur dessus est optimiste (il peut les avoir mémorisées — surapprentissage). Le jeu de test, jamais utilisé pour l'apprentissage, simule des logements nouveaux et mesure donc la capacité de généralisation, c'est-à-dire la performance réelle attendue en production.

**2) Et si l'on gardait les 177 reventes ?**
Un même logement (même `id`, mêmes caractéristiques) pourrait se retrouver à la fois dans le train et dans le test : c'est une **fuite de données**. Le modèle « reconnaîtrait » la maison et prédirait un prix proche de la vente déjà vue ; les métriques de test seraient artificiellement meilleures et ne refléteraient plus la performance sur un logement réellement inconnu. On garde la vente la plus récente (`drop_duplicates(subset="id", keep="last")`).

**3) Une MAE de ~99 000 $ est-elle acceptable ?**
Rapportée au prix médian (~450 000 $), c'est ~20 % d'écart en moyenne.
- *Agent immobilier* : acceptable comme **première estimation** / ordre de grandeur pour orienter un client ou repérer une annonce incohérente, mais insuffisant pour fixer un prix de mise en vente, qui demande une expertise (comparables, état réel, rénovations).
- *Acheteur* : non acceptable pour décider d'un prix d'offre : 99 k$ représente souvent plus que l'apport. De plus l'erreur est plus forte sur les biens chers (RMSE ≫ MAE) et les données datent de 2014-2015 dans le comté de King : le modèle ne vaut pas hors de ce contexte.

---

## Phase 3 — API

12 tests pytest : `12 passed in 1.92s`.
Captures Swagger à ajouter : une réponse **200** (`exemples/logement.json`) et une **422** (`exemples/logement_invalide.json`).

Réponse 422 obtenue avec le fichier invalide (3 erreurs détectées par Pydantic) :
```
surface_m2 : Input should be greater than or equal to 20      (input -5)
salles_de_bain : doit être un multiple de 0,25                 (input 1.3)
etat : Input should be less than or equal to 5                 (input 9)
```

### Questions
**1) Pourquoi charger le modèle dans le `lifespan` et non dans `predire` ?**
Le chargement (`joblib.load` + import scikit-learn) coûte ~1 s et lit 205 Ko sur disque ; le faire à chaque requête multiplierait la latence et la charge disque/CPU. Dans le lifespan il est fait **une seule fois** au démarrage, le modèle reste en mémoire et chaque requête ne fait que l'inférence. Cela permet aussi de détecter un modèle absent/incompatible au démarrage (mode dégradé, `/health` → 503) plutôt qu'à la première requête d'un utilisateur.
Mesure : 1ʳᵉ requête `duree_ms = 18.33`, 10ᵉ requête `duree_ms = 6.12` (la première paie l'initialisation des chemins de code / caches ; ensuite seule l'inférence compte). Chargement seul du modèle mesuré à ~988 ms.

**2) JSON syntaxiquement invalide (accolade manquante) ?**
**422 Unprocessable Content**, avec `"type": "json_invalid", "msg": "JSON decode error"`. FastAPI renvoie 422 (et non 400) car il traite toute erreur sur le corps de la requête comme une erreur de validation.

**3) Clé d'API.**
```
# sans en-tête
{"detail":"Clé d'API absente ou invalide"}  [401]
# avec -H "X-API-Key: secret123"
{"prix_estime_usd":392337.35,"devise":"USD","version_modele":"1.0.0","duree_ms":19.35}  [200]
```
(PowerShell : `$env:API_KEY="secret123"` avant `uvicorn`, puis `curl.exe ... -H "X-API-Key: secret123"`, et `Remove-Item Env:API_KEY` à la fin.)

---

## Phase 5 — Docker

`tester_url.py` contre le conteneur (`http://localhost:8080`) : **6/6 cas conformes** ; conteneur `healthy`, `whoami` → `appuser` (non root).

### Questions
**1) Modification de `style.css` puis rebuild : quelles étapes CACHED ?**
```
[2/7] WORKDIR /app                     CACHED
[3/7] COPY requirements.txt .          CACHED
[4/7] RUN pip install -r requirements  CACHED
[5/7] COPY app/ ./app/                 refait
[6/7] COPY model/ ./model/             refait
[7/7] RUN useradd ...                  refait
```
Docker construit l'image en couches et réutilise une couche tant que son instruction **et ses entrées** (fichiers copiés) sont inchangées. `style.css` est dans `app/` : la couche `COPY app/` change, donc elle et **toutes les suivantes** sont invalidées. Les dépendances sont copiées et installées *avant* le code : l'étape la plus longue (`pip install`) reste en cache. C'est pour cela que le Dockerfile copie `requirements.txt` seul en premier.

**2) Pourquoi `data/` est exclu mais `model/` inclus ?**
Le conteneur ne fait que **servir** des prédictions : il a besoin de l'artefact entraîné (`model.joblib` + `metadata.json`), pas des données brutes, qui ne servent qu'à l'entraînement (fait en amont). Exclure `data/` (2,4 Mo, et `training/`, `tests/`…) rend l'image plus légère, le build plus rapide (contexte envoyé plus petit) et évite de publier des données dans un registre (sécurité / confidentialité dans un cas réel).

**3) Second conteneur sur 8081.**
```
NAMES            PORTS                    STATUS
api-logement-2   0.0.0.0:8081->8000/tcp   Up 30 seconds (healthy)
api-logement     0.0.0.0:8080->8000/tcp   Up 30 seconds (healthy)
```
Deux conteneurs indépendants issus de la **même image**, chacun écoutant sur son port interne 8000, mappés sur deux ports différents de l'hôte. Les deux URL `http://localhost:8080` et `http://localhost:8081` répondent la même chose (même modèle, même empreinte). C'est le principe de la mise à l'échelle horizontale que fait le service Cloud (répliques).

---

## Phase 6/7 — Cloud et validation (à compléter)
- Sortie `tester_url.py` : local ✅, Docker ✅, **URL Cloud : à coller** (`validation_cloud.txt`).
- Captures des journaux : `az containerapp logs show ...`.
- **Empreintes** : `sha256_modele` = `sha256_fichier_charge` = `1adff958…7032`, `integrite_ok: true` (local et Docker). À vérifier aussi sur l'URL Cloud (`/model-info`).
- Preuve de suppression : `az group exists --name rg-prix-logement` → `false`.

## Schéma d'architecture
```
 Navigateur ──HTTPS──▶ Azure Container Apps (ingress, TLS, port cible 8000)
                         └─ réplique(s) du conteneur prix-logement-api:1.0.0
                              uvicorn ─▶ FastAPI ─┬─ /            (interface static/)
                                                  ├─ /health
                                                  ├─ /model-info
                                                  └─ /predict ─▶ Pydantic ─▶ modèle en mémoire
 Image tirée depuis Azure Container Registry (acrprixXXXXX)  ◀── docker push (poste local)
 Journaux ─▶ Log Analytics workspace
```

## Trajet d'une requête
L'utilisateur remplit le formulaire ; `app.js` vérifie les champs puis envoie un `fetch` POST `/predict` avec un JSON. La requête part en HTTPS vers l'URL publique de Container Apps ; l'ingress termine le TLS et la transmet en HTTP au port 8000 d'une réplique du conteneur (démarrée à la demande si elle était à zéro). Dans le conteneur, uvicorn reçoit la requête et la passe à FastAPI, qui la route vers `/predict` ; Pydantic valide le corps (types, bornes) et renvoie 422 si une valeur est invalide. Sinon, le service construit un DataFrame avec les 9 variables dans l'ordre attendu et appelle le modèle déjà chargé en mémoire au démarrage ; le pipeline retransforme la prédiction (entraînée sur log1p du prix) en dollars. La réponse JSON (prix, version du modèle, durée) remonte le même chemin ; l'API écrit une ligne de journal visible dans Log Analytics, et le navigateur affiche le prix.
