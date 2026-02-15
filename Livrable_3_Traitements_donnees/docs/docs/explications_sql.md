# Explication complète du pipeline SQL  
## Choix techniques, vocabulaire, et raisonnement derrière chaque étape

---

# 0. Contexte et objectif du projet

Le projet consiste à construire un pipeline data en SQL (PostgreSQL) à partir de fichiers CSV bruts.  
L’idée est de passer de données importées “telles quelles” à une base relationnelle propre, reliée et exploitable dans Tableau.

Les données couvrent trois thèmes :

- des lieux (villes et espaces verts, provenant de Wikidata) ;
- des positions GPS de faucons (données de tracking) ;
- des données météo (9 stations, mesures quotidiennes).

L’objectif final n’est pas juste de “stocker” ces données, mais de pouvoir faire des analyses concrètes :

- repérer où passent les faucons ;
- comparer les passages selon la région et selon l’année ;
- comparer l’activité des faucons et la météo (par mois, par province) ;
- comparer les détections en milieu urbain vs milieu naturel ;
- produire des datasets déjà prêts pour Tableau.

---

# 1. Définitions rapides (pour comprendre le document)

## 1.1 Table

Une table est un tableau : des colonnes (champs) et des lignes (enregistrements).  
Exemple : la table `place` contient une ligne par lieu.

## 1.2 Schéma (schema)

Un schéma est un “dossier” dans PostgreSQL.  
Ici, toutes les tables du projet sont rangées dans le schéma `CREC`.

## 1.3 Clé primaire (PK)

Une clé primaire est un identifiant unique pour une ligne.  
Exemple : `place.place_id` identifie un lieu de manière unique.

## 1.4 Clé étrangère (FK)

Une clé étrangère est une colonne qui pointe vers une autre table.  
Exemple : `bird_detection.falcon_id` pointe vers `falcon.falcon_id`.

Cela sert à relier les tables.

## 1.5 Staging (tables de travail)

Le staging correspond aux tables intermédiaires utilisées pour nettoyer et transformer.  
On ne les garde pas dans le résultat final.

## 1.6 Vue (view)

Une vue est une requête enregistrée (`CREATE VIEW`).  
Une vue ne stocke pas de nouvelles données : elle calcule un résultat quand on l’utilise.  
C’est pratique pour Tableau, car on peut lui donner directement une vue comme “dataset”.

## 1.7 Outlier (valeur aberrante)

Un outlier est un point clairement anormal par rapport au reste (souvent lié à une erreur de mesure).  
Dans le tracking GPS, cela correspond typiquement à un point “impossible” (saut énorme, vitesse incohérente, etc.).  
Dans le projet, les outliers sont indiqués dans la source via `import-marked-outlier`.

---

# 2. Pourquoi le pipeline est découpé en 5 scripts

Le découpage en 5 scripts permet de séparer des responsabilités différentes.

## Script 01 : staging et nettoyage  
Objectif : partir des CSV bruts, nettoyer, standardiser, préparer.

## Script 02 : création des tables finales  
Objectif : construire le modèle relationnel final (PK/FK, tables stables).

## Script 03 : enrichissement des clés étrangères  
Objectif : créer des liens géographiques qui nécessitent des calculs (matching).

## Script 04 : vues pour Tableau  
Objectif : produire des datasets simples, déjà agrégés, prêts pour la dataviz.

## Script 05 : cleanup  
Objectif : supprimer staging + bruts, ne garder que le final.

Ce découpage a plusieurs avantages :

- on peut rejouer un script sans refaire tout le projet ;
- on sait où se trouve chaque logique ;
- on sépare nettoyage (qualité) et analyse (dataviz).

---

# 3. Script 01 — Staging et nettoyage

Ce script est celui où se prennent la plupart des décisions de qualité de données.

## 3.1 Pourquoi faire du staging avant de créer les tables finales

Les CSV importés contiennent souvent :

- des colonnes inutiles ;
- des textes pas standardisés ;
- des valeurs vides ;
- des types mal interprétés (texte au lieu de nombre) ;
- des doublons.

Si on met directement ces données dans le modèle final :

- les jointures deviennent instables ;
- des lieux identiques peuvent être dupliqués ;
- certaines analyses donnent des résultats faux ou incohérents.

Le staging permet de nettoyer proprement en amont et de construire un modèle final plus fiable.

---

## 3.2 Traitement des lieux : villes + espaces verts

### 3.2.1 Choix : fusionner villes et espaces verts

Les lieux viennent de deux tables différentes :

- une table pour les villes ;
- une table pour les espaces verts.

Dans le projet, on veut rattacher des événements (détections, stations météo) à un “lieu”.  
Une ville et un parc jouent donc le même rôle : ce sont des repères géographiques.

Le choix est donc de créer un référentiel unique (`space_complet`) qui mélange les deux types de lieux.

Cela simplifie la suite :

- on n’a qu’une seule table à joindre ;
- toutes les analyses géographiques s’appuient sur le même référentiel ;
- le futur matching “détection → lieu” n’a pas besoin de décider à l’avance si un faucon est plutôt proche d’une ville ou d’un parc.

---

### 3.2.2 Choix : normaliser les textes (noms, régions, provinces)

Les textes sont nettoyés pour éviter les faux doublons.

Exemple : un même lieu peut apparaître avec :

- des accents ;
- des apostrophes ;
- des majuscules ;
- des caractères spéciaux.

En SQL, ces variantes sont différentes, donc elles cassent les comparaisons et les jointures.

Le nettoyage fait notamment :

- suppression des espaces inutiles (`TRIM`) ;
- uniformisation visuelle (`INITCAP`) ;
- suppression accents et caractères spéciaux (`unaccent` + regex).

---

### 3.2.3 Choix : supprimer des colonnes non utilisées

Les sources Wikidata peuvent donner beaucoup de colonnes.

Le projet ne garde que ce qui sert aux analyses et au rattachement :

- nom (`space_label`) ;
- type (`type_label`) ;
- région/province ;
- coordonnées ;
- quelques attributs optionnels (population, area, elevation).

Ce choix évite de garder des données inutiles, rend la table plus lisible et diminue le risque de confusion.

---

### 3.2.4 Choix : gestion des doublons

Des doublons peuvent exister (même lieu répété, ou extraction Wikidata imparfaite).

Le projet supprime certains doublons en gardant une seule ligne par coordonnée.

L’objectif est d’éviter qu’un même lieu apparaisse plusieurs fois dans les analyses.  
Sans ça, les détections pourraient être réparties entre plusieurs “copies” du même lieu.

---

### 3.2.5 IMPORTANT : ajout manuel de certains lieux (patch manuel)

Lors du nettoyage des lieux issus de Wikidata, le pipeline part d’une hypothèse :  
chaque station météo doit pouvoir être reliée à un lieu dans `place`.

Ce lien est important car il sert de “pont” entre météo et géographie.

Plus précisément, les vues analytiques ont besoin de rattacher la météo à une province standardisée (celle de la table `place`).  
Le chemin logique est :

`weather_measurement` → `weather_station` → `place` → `province_label`

Le problème est le suivant : certaines stations météo présentes dans les fichiers météo n’ont pas trouvé de correspondance exploitable dans les lieux importés depuis Wikidata.  
Cela peut arriver pour plusieurs raisons :

- le lieu n’était pas présent dans le dataset Wikidata importé ;
- le nom n’était pas exactement le même ;
- le lieu existe mais n’était pas correctement exploitable (valeurs manquantes, coordonnées absentes, etc.).

Sans correction, cela entraîne des conséquences concrètes :

- `weather_station.place_id` reste NULL ;
- la station ne peut pas être rattachée à une province issue de `place` ;
- la météo de cette station devient difficile à agréger proprement par province ;
- la vue “migration vs météo” perd des données et devient incomplète.

Trois cas ont été identifiés : Ceuta, Melilla et Maspalomas.  
Ces lieux existent bien dans la réalité, et une station météo est associée à ces zones dans les données source.  
Ils ont donc été ajoutés manuellement afin de garantir que les 9 stations puissent être rattachées à un lieu.

Ce choix est volontairement limité à quelques lignes contrôlées, car :

- il est plus simple de corriger quelques cas que de complexifier tout le pipeline ;
- il sécurise la cohérence du modèle relationnel ;
- il garantit l’exploitabilité des vues analytiques basées sur la province.

---

## 3.3 Traitement des données GPS des faucons

### 3.3.1 Problème : volume très important

Les trackers GPS produisent énormément de points.

Si on garde tous les points :

- les requêtes sont lourdes ;
- Tableau devient lent ;
- les cartes sont illisibles ;
- les individus les mieux suivis dominent les analyses.

---

### 3.3.2 Choix : supprimer les outliers

Les points marqués comme outliers (valeurs extrêmes) sont exclus.

Dans un dataset GPS, un seul point aberrant peut :

- créer un “saut” énorme sur une carte ;
- fausser les vitesses ;
- produire un rattachement à un lieu très éloigné.

Le pipeline supprime donc ces points avant toute analyse.

---

### 3.3.3 Choix : sélectionner les 30 faucons les plus documentés

Le pipeline garde uniquement les 30 individus ayant le plus de données valides.

Ce choix sert à :

- avoir un dataset consistant ;
- éviter des individus avec trop peu d’observations ;
- garder un volume gérable pour le projet.

---

### 3.3.4 Choix : downsampling (1 point / 10 minutes / individu)

Même après sélection, le dataset reste volumineux.

Le downsampling consiste à ne garder qu’un point toutes les 10 minutes pour chaque faucon.

Le raisonnement est :

- la trajectoire générale est conservée ;
- on retire des points redondants ;
- les analyses et la dataviz deviennent plus rapides.

Le script applique ce downsampling avec une logique stable (le premier point dans chaque tranche de 10 minutes).

---

## 3.4 Traitement des données météo

### 3.4.1 Problème : 9 tables séparées

Chaque station météo est dans sa propre table brute.  
Cela empêche une analyse globale simple.

Le pipeline regroupe toutes les stations en une table unique : `weather_daily_work`.

Cela permet :

- d’avoir une seule structure ;
- d’avoir un seul endroit où nettoyer les données ;
- de charger ensuite facilement les tables finales météo.

---

### 3.4.2 Choix : normalisation de la colonne des précipitations

Dans les tables météo brutes, la pluie est stockée dans la colonne `prec`.  
Lors de l’insertion dans `weather_daily_work`, cette donnée est chargée dans une colonne `precip` avec un type numérique homogène.

Même si les fichiers utilisés dans ce projet contiennent uniquement des valeurs numériques, la transformation prévoit le traitement de valeurs non numériques possibles dans d’autres exports de même origine.  
Le but est de garantir que `precip` reste toujours exploitable pour les agrégations (moyennes, sommes) et que le pipeline ne casse pas en cas de variation des formats.

---

# 4. Script 02 — Création des tables finales

Ce script construit le modèle relationnel final.

## 4.1 Table PLACE

`place` est le référentiel central des lieux.

Un identifiant numérique `place_id` est utilisé pour :

- éviter les jointures sur texte ;
- accélérer les relations ;
- stabiliser les liens (les noms peuvent varier, l’ID non).

## 4.2 Table FALCON

`falcon` contient une ligne par individu sélectionné.

Créer une table séparée évite de répéter les identifiants texte du faucon dans chaque détection.

## 4.3 Table BIRD_DETECTION

`bird_detection` contient les observations GPS.

Chaque ligne représente un événement : un faucon, un instant, une position, et des attributs (vitesse, altitude).

`place_id` existe déjà comme colonne, mais il n’est pas rempli ici car il dépend d’un calcul géographique fait dans le script 03.

## 4.4 Tables météo : WEATHER_STATION et WEATHER_MEASUREMENT

Les stations (`weather_station`) sont séparées des mesures (`weather_measurement`) afin de ne pas répéter les informations station chaque jour.

Une contrainte d’unicité (station + date) empêche les doublons lors des relances.

---

# 5. Script 03 — Enrichissement des clés étrangères (matching géographique)

Ce script crée les liens géographiques manquants.

## 5.1 Extraction des coordonnées des lieux

Les coordonnées des lieux sont stockées sous forme de texte `Point(lon lat)`.  
Le script extrait latitude et longitude dans deux colonnes numériques (`place_lat`, `place_lon`) pour pouvoir comparer des positions.

## 5.2 Rattachement des stations météo aux lieux

Les stations météo sont rattachées à un lieu via le nom :

- sans accents ;
- sans distinction majuscule/minuscule ;
- avec un patch pour certains suffixes ;
- et un patch spécifique Maspalomas.

## 5.3 Rattachement des détections aux lieux

Les détections n’ont pas de ville associée.  
Le pipeline choisit donc de rattacher chaque point au lieu le plus proche, sans PostGIS.

### Choix : méthode simple de proximité (en degrés)

On compare les écarts de latitude/longitude entre une détection et un lieu, puis on retient le lieu le plus proche selon cet écart.

L’objectif est d’obtenir un “lieu de référence” pour agréger par province, pas de mesurer des distances exactes en kilomètres.

### Choix : seuil maximal de 2 degrés

Sans seuil, chaque point aurait toujours un lieu associé, même très éloigné.

Le seuil empêche des rattachements incohérents.  
Si aucun lieu n’est assez proche, on laisse `place_id = NULL`.

Ce choix vise à préserver la qualité des analyses : un lien incorrect est pire qu’une valeur manquante.

### Choix : bounding box

Pour éviter des calculs trop longs, la recherche du lieu le plus proche est limitée à une zone autour du point (fenêtre latitude/longitude).

Cela réduit fortement le nombre de lieux candidats et améliore les performances.

---

# 6. Script 04 — Vues SQL pour Tableau (datasets)

Ce script crée des vues SQL destinées à être utilisées directement dans Tableau.

L’objectif principal est de déplacer la complexité côté SQL :

- les jointures entre tables ;
- les agrégations (COUNT, AVG) ;
- la préparation des colonnes temporelles (année, mois).

Ainsi, Tableau consomme des datasets déjà prêts.

## 6.1 v_weather_measurement (dataset météo propre)

Cette vue joint `weather_measurement` et `weather_station`.

Elle sert à :

- disposer d’un dataset météo complet ;
- éviter de refaire la jointure dans Tableau ;
- conserver une structure simple (une ligne = une mesure + ses infos station).

## 6.2 v_dataviz1_passages_region_year (passages par région/province/année)

Question visée : quelles zones voient le plus de passages, et comment cela évolue dans le temps ?

La vue agrège par :

- région autonome (`ccaa_label`) ;
- province (`province_label`) ;
- année.

Elle fournit :

- `nb_detections` : volume total de points (intensité de passage) ;
- `nb_faucons` : nombre d’individus distincts (évite le biais d’un seul faucon très présent).

Dans Tableau, cette vue sert à :

- des classements des provinces ;
- des comparaisons par année ;
- des cartes agrégées (par province ou par région).

## 6.3 v_dataviz2_migration_vs_meteo_province_month (migration vs météo)

Question visée : l’activité des faucons varie-t-elle avec la météo selon les mois ?

La vue fait deux agrégations séparées :

- côté faucons : détections et faucons distincts par province et par mois ;
- côté météo : moyennes météo par province et par mois.

Puis elle joint les deux sur (province + mois).

Le choix du mois sert à :

- lisser les variations quotidiennes ;
- produire un niveau comparable entre météo (journalière) et détections (très fréquentes) ;
- faire apparaître des tendances saisonnières.

Dans Tableau, cette vue sert à :

- nuages de points (ex : activité vs température) ;
- courbes mensuelles ;
- comparaisons entre provinces.

## 6.4 v_dataviz3_urban_vs_green (urbain vs espaces verts)

Question visée : les détections sont-elles plus fréquentes en milieu urbain ou naturel ?

Les lieux sont regroupés en catégories simples à partir de `place.type_label` :

- urbain (city, town, municipalité, etc.) ;
- naturel/vert (park, natural, reserve, forest, etc.) ;
- autre.

Le regroupement est nécessaire car les types Wikidata peuvent être très nombreux.  
Sans regroupement, la dataviz devient illisible.

Dans Tableau, cette vue sert à :

- comparer la distribution des détections par type d’environnement ;
- comparer le nombre d’individus observés par catégorie.

## 6.5 v_dataviz3_map_points (points pour carte)

Cette vue fournit les points GPS individuels :

- latitude ;
- longitude ;
- date (année, mois) ;
- identifiant du faucon ;
- `place_id` si disponible.

Elle sert à construire des cartes détaillées dans Tableau, avec filtres (par mois, par année, par individu).

---

# 7. Script 05 — Cleanup (suppression staging + bruts)

Ce script supprime :

- les tables de staging ;
- les tables brutes importées (CSV).

Le but est de ne garder que :

- les tables finales ;
- les vues Tableau.

Cela rend la base plus claire et évite que quelqu’un utilise par erreur une table intermédiaire au lieu des tables finales.

---

# 8. Résultat final du pipeline

Après exécution :

- les lieux sont nettoyés et réunis dans un référentiel unique (`place`) ;
- les faucons sont normalisés dans `falcon` ;
- les observations GPS sont dans `bird_detection` ;
- la météo est structurée en `weather_station` + `weather_measurement` ;
- les stations météo sont rattachées à des lieux ;
- une grande partie des détections est rattachée au lieu le plus proche avec un seuil de qualité ;
- des vues prêtes pour Tableau existent pour analyser espace, temps, météo, et environnement.