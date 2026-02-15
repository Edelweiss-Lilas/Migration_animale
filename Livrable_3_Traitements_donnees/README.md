# Projet SQL — Analyse des migrations de faucons

## Objectif du projet

Ce projet a pour objectif de construire une base de données PostgreSQL permettant d’analyser les migrations de faucons à partir de :

- données GPS de suivi des oiseaux,
- données géographiques (villes et espaces naturels),
- données météorologiques quotidiennes.

La base est entièrement reproductible à partir des CSV bruts via les scripts SQL orchestrés et l’exécution de `python run.py`.

---

## Structure du projet

```text
.
├── run.py
├── requirements.txt
├── .env (non versionné)
├── csv/ (données brutes)
│
├── sql/
│   ├── 01_staging_et_nettoyage.sql
│   ├── 02_tables_finales.sql
│   ├── 03_enrichissement_fk.sql
│   ├── 04_views_dataviz.sql
│   └── 05_cleanup.sql
│
└── docs/
    ├── README.md
    ├── mld.png
    └── dictionnaire_donnees.md
```

---

## Modèle logique de données

Le modèle logique est disponible ici (format image exportée depuis le modèle logique réalisé en amont) :


- `docs/mld.png`

Le modèle relie :

- lieux (`place`)
- oiseaux (`falcon`)
- détections GPS (`bird_detection`)
- stations météo (`weather_station`)
- mesures météo (`weather_measurement`)

---

## Pipeline de traitement des données

Les données sont traitées en plusieurs étapes :

### 01 — Staging et nettoyage

- nettoyage des labels (trim, accents, normalisation) ;
- harmonisation des types ;
- fusion des sources géographiques ;
- sélection des 30 oiseaux les mieux documentés ;
- downsampling GPS (1 point / 10 min) ;
- fusion des stations météo.

### 02 — Création des tables finales

- création des tables métiers ;
- clés primaires / étrangères ;
- insertion des données nettoyées.

### 03 — Enrichissement des relations

- extraction latitude / longitude depuis les coordonnées texte ;
- rattachement des stations météo aux lieux ;
- rattachement spatial des détections au lieu le plus proche ;
- optimisation via bounding box pour limiter le temps d’exécution.

### 04 — Vues analytiques

Création de datasets prêts pour Tableau :

- passages par région et année ;
- migration vs météo ;
- urbain vs naturel ;
- points GPS cartographiques.

### 05 — Nettoyage final

- suppression des tables temporaires et brutes (conservation uniquement des tables finales et vues).

---

## Vues analytiques (Dataviz)

Le projet contient plus de trois vues afin de séparer :

- les vues directement utilisées pour les visualisations,
- les vues techniques servant de datasets préparatoires.

### `v_weather_measurement`
Dataset météo enrichi avec les informations des stations.

### `v_dataviz1_passages_region_year`
Agrégation des passages de faucons par province et année.

### `v_dataviz2_migration_vs_meteo_province_month`
Croisement entre météo et activité migratoire.

### `v_dataviz3_urban_vs_green`
Comparaison des passages selon le type d’environnement.

### `v_dataviz3_map_points` (vue bonus)
Vue technique contenant les points GPS bruts pour la cartographie.

---

## Méthodologie spatiale

Le rattachement géographique des détections repose sur :

- le lieu le plus proche,
- une limitation géographique (bounding box),
- un seuil maximal de distance.

Les détections trop éloignées ne sont pas supprimées mais conservées sans rattachement afin de préserver la cohérence spatiale des analyses.

---

## Installation et exécution

### 1. Créer un environnement virtuel

```bash
python -m venv env
```

### 2. Activer l’environnement

Linux / Mac :

```bash
source env/bin/activate
```

Windows :

```bash
source env/Scripts/activate
```

### 3. Installer les dépendances

```bash
pip install -r requirements.txt
```

### 4. Configurer le fichier `.env`

Copier le fichier `.env.example` en `.env`, puis adapter les valeurs à votre configuration locale.

```env
pgHost=127.0.0.1
pgPort=5432
pgUser=postgres
pgPassword=YOUR_PASSWORD
pgDatabase=crec
pgSchemaImportsCsv=crec
failOnFirstSqlError=True
failOnFirstCsvError=True
```

### 5. Lancer le projet

```bash
python run.py
```

Le script :

- crée la base si nécessaire,
- importe les CSV,
- exécute les scripts SQL automatiquement dans l’ordre alphabétique.

---

## Résumé (exécution rapide)

```bash
python -m venv env
source env/bin/activate   # Windows : source env/Scripts/activate
pip install -r requirements.txt
python run.py
```
