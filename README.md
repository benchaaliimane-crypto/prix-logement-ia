# Prix logement IA : API de prédiction déployée dans le Cloud

Application d'intelligence artificielle qui estime le prix d'un logement à partir de
9 caractéristiques, exposée par une API FastAPI, conteneurisée avec Docker et
déployée sur AWS (ECS Express Mode) ou Azure (Container Apps).

## Données
« House Sales in King County, USA » : 21 613 ventes de maisons du comté de King
(Seattle, États-Unis), mai 2014 à mai 2015, licence CC0.
Source : https://www.kaggle.com/datasets/harlfoxem/housesalesprediction
Le fichier `data/kc_house_data.csv` doit être placé dans le dossier `data/`.

Variables du modèle (calculées à partir des colonnes réelles du fichier) :
surface habitable en m² (sqft_living × 0,0929), chambres, salles de bain, niveaux,
âge du bâtiment à la vente, distance au centre de Seattle (calculée à partir de la
latitude et de la longitude), bord de l'eau, état (1 à 5), qualité de construction (1 à 13).
Prix en dollars américains.

## Installation locale (Windows PowerShell)
    python -m venv .venv
    .\.venv\Scripts\Activate.ps1
    pip install -r requirements-dev.txt

## Entraîner le modèle
    python training/explorer.py      # exploration du jeu de données
    python training/train.py         # produit model/model.joblib et model/metadata.json

## Lancer et tester l'API
    uvicorn app.main:app --reload --port 8000
    # Interface Web : http://127.0.0.1:8000/   Documentation : http://127.0.0.1:8000/docs
    python -m pytest -v
    python outils/tester_url.py http://127.0.0.1:8000

## Docker
    docker build -t prix-logement-api:1.0.0 .
    docker run -d --name api-logement -p 8080:8000 prix-logement-api:1.0.0
    python outils/tester_url.py http://127.0.0.1:8080

## Routes
| Méthode | Route         | Rôle                                         |
|---------|---------------|----------------------------------------------|
| GET     | `/`           | Interface Web                                |
| GET     | `/health`     | Sonde de santé (200 si le modèle est chargé) |
| GET     | `/model-info` | Version, métriques et empreinte du modèle    |
| POST    | `/predict`    | Prix estimé à partir d'un JSON de 9 champs   |

## Variables d'environnement
| Variable    | Rôle                                                   | Défaut  |
|-------------|--------------------------------------------------------|---------|
| `MODEL_DIR` | Dossier contenant model.joblib et metadata.json        | `model` |
| `API_KEY`   | Si définie, POST /predict exige l'en-tête `X-API-Key`  | (vide)  |
| `LOG_LEVEL` | Niveau de journalisation                               | `INFO`  |

## URL de déploiement
À compléter : https://...
