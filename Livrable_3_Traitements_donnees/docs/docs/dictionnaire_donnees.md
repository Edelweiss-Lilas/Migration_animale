# Dictionnaire des données

Ce document décrit la structure logique et physique des données utilisées dans le projet de traitement et d’analyse des migrations de faucons.

Il accompagne les scripts SQL permettant de reconstruire intégralement la base PostgreSQL.

---

# 1. Principes de modélisation

Le modèle repose sur trois sources principales :

- données géographiques (Wikidata),
- données de tracking GPS des oiseaux (Movebank),
- données météorologiques quotidiennes (AEMET).

Les choix de modélisation poursuivent trois objectifs :

1. **Séparer les entités métiers** (lieux, oiseaux, mesures météo) ;
2. **Faciliter les analyses spatiales et temporelles** ;
3. **Permettre des agrégations rapides pour la datavisualisation (Tableau).**

Les relations principales sont :

- un oiseau → plusieurs détections,
- une station météo → plusieurs mesures,
- un lieu → observations oiseaux et stations météo.

---

# 2. Tables finales

## 2.1 Table `place`

Contient les lieux géographiques (villes et espaces naturels).

| Colonne | Type | Description | Remarques |
|---|---|---|---|
| place_id | INTEGER (PK) | Identifiant unique du lieu | Généré automatiquement |
| space_label | VARCHAR | Nom du lieu | Nettoyé (accents retirés) |
| wikidata_id | VARCHAR | Identifiant Wikidata | Peut être NULL |
| type_label | VARCHAR | Type de lieu (city, park, reserve…) | Utilisé pour la dataviz urbain vs naturel |
| ccaa_label | VARCHAR | Communauté autonome | |
| province_label | VARCHAR | Province administrative | Utilisée pour agrégations |
| coordonnees | VARCHAR | Coordonnées au format `Point(lon lat)` | Donnée brute |
| elevation | NUMERIC | Altitude | NULL si inconnue |
| area | NUMERIC | Superficie | Valeur décimale exacte |
| population | INTEGER | Population | Principalement pour les villes |
| place_lon | DOUBLE PRECISION | Longitude extraite | Ajout script 03 |
| place_lat | DOUBLE PRECISION | Latitude extraite | Ajout script 03 |

### Choix de modélisation

**Coordonnées (`coordonnees`)**

Les coordonnées sont stockées dans la donnée source sous forme textuelle (`Point(lon lat)`), car elles proviennent directement des exports Wikidata.  
Ce format brut est conservé pour :

- garder la donnée originale traçable,
- garantir la reproductibilité du pipeline,
- éviter une dépendance à PostGIS.

Les colonnes numériques `place_lat` et `place_lon` sont extraites ensuite afin de permettre les calculs de distance.

**Type `NUMERIC` pour `area`**

Le champ `area` utilise `NUMERIC` :

- `INT` ne permet pas les valeurs décimales ;
- `FLOAT` introduit des approximations ;
- `NUMERIC` garantit des calculs exacts lors des agrégations analytiques.

---

## 2.2 Table `falcon`

Référentiel des individus suivis.

| Colonne | Type | Description | Remarques |
|---|---|---|---|
| falcon_id | SERIAL (PK) | Identifiant interne | |
| falcon_code | TEXT | Identifiant original de l’oiseau | Unique |
| tag_id | TEXT | Identifiant de balise GPS | Peut être NULL |
| nickname | TEXT | Surnom | Valeur par défaut : `NONE` |

---

## 2.3 Table `bird_detection`

Contient les positions GPS des oiseaux.

| Colonne | Type | Description | Remarques |
|---|---|---|---|
| detection_id | SERIAL (PK) | Identifiant de détection | |
| time | TIMESTAMP | Date et heure de la mesure | UTC |
| coordinate | DOUBLE PRECISION[] | Coordonnées [latitude, longitude] | Tableau de 2 valeurs |
| speed | DOUBLE PRECISION | Vitesse au sol | |
| altitude | DOUBLE PRECISION | Altitude de vol | |
| falcon_id | INT (FK) | Référence à l’oiseau | FK → falcon |
| place_id | INT (FK) | Lieu administratif le plus proche | FK → place, peut être NULL |

### Note méthodologique

Le rattachement géographique (`place_id`) est calculé par proximité spatiale :

- recherche du lieu le plus proche,
- filtrage par **bounding box** (zone carrée autour du point),
- seuil maximal de distance pour éviter les rattachements incohérents.

Les détections non rattachées sont conservées afin d’éviter la perte d’information.

---

## 2.4 Table `weather_station`

Référentiel des stations météorologiques.

| Colonne | Type | Description | Remarques |
|---|---|---|---|
| station_id | BIGINT (PK) | Identifiant interne | |
| station_code | TEXT | Code officiel station | Unique |
| name | TEXT | Nom station | |
| province | TEXT | Province administrative | |
| place_id | INT (FK) | Lieu associé | FK → place |

---

## 2.5 Table `weather_measurement`

Mesures météo quotidiennes.

| Colonne | Type | Description | Remarques |
|---|---|---|---|
| measurement_id | BIGINT (PK) | Identifiant mesure | |
| obs_date | DATE | Date d’observation | |
| time | TIMESTAMP | Timestamp associé | Utilisé pour dataviz |
| temperature_min | DOUBLE PRECISION | Température minimale | |
| temperature_mid | DOUBLE PRECISION | Température moyenne | |
| temperature_max | DOUBLE PRECISION | Température maximale | |
| humidity_min | DOUBLE PRECISION | Humidité minimale | |
| humidity_mid | DOUBLE PRECISION | Humidité moyenne | |
| humidity_max | DOUBLE PRECISION | Humidité maximale | |
| precip | DOUBLE PRECISION | Précipitations | |
| wind_speed_mid | DOUBLE PRECISION | Vent moyen | |
| wind_gust | DOUBLE PRECISION | Rafale maximale | |
| wind_direction | DOUBLE PRECISION | Direction du vent | |
| station_id | BIGINT (FK) | Station associée | FK → weather_station |

Contrainte : unicité `(station_id, obs_date)`.

---

# 3. Relations principales

- Un `falcon` possède plusieurs `bird_detection` ;
- Un `place` peut être associé à plusieurs `bird_detection` ;
- Un `place` peut être associé à plusieurs `weather_station` ;
- Une `weather_station` possède plusieurs `weather_measurement`.

---

# 4. Vues analytiques (Dataviz)

Le projet contient plus de trois vues afin de séparer :

- les vues analytiques utilisées directement pour les visualisations,
- les vues techniques servant de datasets préparatoires.

## `v_weather_measurement`
Dataset météo enrichi avec les informations de station.

## `v_dataviz1_passages_region_year`
Agrégation des passages de faucons par province et année.

## `v_dataviz2_migration_vs_meteo_province_month`
Croisement entre météo et activité migratoire.

## `v_dataviz3_urban_vs_green`
Comparaison des passages selon le type d’environnement.

## `v_dataviz3_map_points`
Vue technique contenant les points GPS bruts pour la cartographie.

---

# 5. Choix méthodologiques importants

- Nettoyage et harmonisation des labels (trim, accents, normalisation) ;
- Downsampling GPS (1 point / 10 minutes) pour réduire le bruit ;
- Association spatiale par proximité (absence de PostGIS) ;
- Conservation des données non rattachées pour éviter la perte d’information.

---

# 6. Justifications techniques

### 1. Pourquoi une table `place` unique ?
Un référentiel unique évite la duplication des lieux et simplifie les jointures entre météo et migration.

### 2. Pourquoi un downsampling des données GPS ?
Le dataset brut est très volumineux. Réduire à 1 point / 10 minutes conserve la trajectoire tout en améliorant les performances.

### 3. Pourquoi une bounding box ?
Limiter la recherche spatiale autour d’un point réduit fortement le temps d’exécution lors du rattachement spatial.

### 4. Pourquoi garder les `NULL` sur `place_id` ?
Un rattachement incertain est pire qu’une absence de rattachement : les analyses restent cohérentes.

### 5. Pourquoi plusieurs vues dataviz ?
Séparer datasets analytiques et vues techniques simplifie le travail dans Tableau et améliore la lisibilité du projet.
