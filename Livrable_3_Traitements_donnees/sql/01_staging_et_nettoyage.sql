-- ============================================================
-- 01_staging_et_nettoyage.sql
-- Objectif :
--  - Préparer des "tables de travail" propres (staging)
--  - Nettoyer les textes (trim, accents, caractères spéciaux)
--  - Uniformiser les types (NUMERIC, INTEGER, etc.)
--  - Filtrer les outliers côté faucons
--  - Fusionner villes + espaces verts dans une table unique
--  - Préparer une météo propre dans une table unique
-- ============================================================

-- Active l'extension unaccent (permet de comparer "Séville" et "Seville")
-- IF NOT EXISTS = ne fait rien si déjà installée
CREATE EXTENSION IF NOT EXISTS unaccent;

BEGIN; -- Début transaction : tout ou rien (propre et sûr)

-- Crée le schéma "CREC" si besoin (comme un dossier de projet)
CREATE SCHEMA IF NOT EXISTS CREC;

-- On travaille par défaut dans CREC (puis public si besoin)
SET search_path TO CREC, public;

-- ============================================================
-- PATCH : rendre la table brute kestrel34 insensible à la casse
-- Si le CSV s'appelle KESTREL34.csv, Pandas crée une table "KESTREL34", 
-- on renomme/normalise toujours vers "kestrel34"
-- ============================================================

DO $$
BEGIN
  IF to_regclass('crec.kestrel34') IS NULL THEN
    IF to_regclass('crec."KESTREL34"') IS NOT NULL THEN
      EXECUTE 'ALTER TABLE crec."KESTREL34" RENAME TO kestrel34';
    ELSIF to_regclass('crec."Kestrel34"') IS NOT NULL THEN
      EXECUTE 'ALTER TABLE crec."Kestrel34" RENAME TO kestrel34';
    END IF;
  END IF;
END $$;

-- ============================================================
-- ===================== PLACE (STAGING) ======================
-- ============================================================
-- On prépare les lieux (villes + espaces verts)
-- On nettoie, puis on fusionne dans une table unique : space_complet
-- Cette table servira au script 02 pour créer la table finale PLACE

-- ----------------------------
-- 1) CITY (staging)
-- ----------------------------

-- On repart d'une table vide pour éviter les doublons si on relance le script
DROP TABLE IF EXISTS city CASCADE;

-- Table de travail pour les villes (format "propre")
-- On choisit les colonnes qu'on veut garder / nettoyer
CREATE TABLE city (
  commune             VARCHAR,
  city_label          VARCHAR,
  wikidata_id         VARCHAR,
  type_label          VARCHAR,
  continent           VARCHAR,
  continentlabel      VARCHAR,
  pays                VARCHAR,
  payslabel           VARCHAR,
  communauteautonome  VARCHAR,
  province_label      VARCHAR,
  coordonnees         VARCHAR,   -- texte de type "Point(lon lat)"
  latitude            FLOAT,
  longitude           FLOAT,
  elevation           INTEGER,
  pointculminant      VARCHAR,
  pointculminantlabel VARCHAR,
  superficie          FLOAT,
  population          INTEGER
);

-- On charge les données depuis la table brute (CSV importé)
INSERT INTO city (
  commune,
  city_label,
  wikidata_id,
  type_label,
  continent,
  continentlabel,
  pays,
  payslabel,
  communauteautonome,
  province_label,
  coordonnees,
  latitude,
  longitude,
  elevation,
  pointculminant,
  pointculminantlabel,
  superficie,
  population
)
SELECT
  commune,
  city_label,
  wikidata_id,
  type_label,
  continent,
  "contientLabel",         -- colonne brute
  pays,
  "paysLabel",
  "communauteAutonome",
  province_label,
  coordonnees,
  latitude,
  longitude,
  elevation,
  "pointCulminant",
  "pointCulminantLabel",
  superficie,
  population
FROM communes_global;

-- Suppression des colonnes qu'on ne veut pas garder dans city
-- pour alléger le modèle et ne garder que ce qui sert
ALTER TABLE city
  DROP COLUMN commune,
  DROP COLUMN continent,
  DROP COLUMN continentlabel,
  DROP COLUMN pays,
  DROP COLUMN payslabel,
  DROP COLUMN latitude,
  DROP COLUMN longitude,
  DROP COLUMN pointculminant,
  DROP COLUMN pointculminantlabel;

-- Renommer des colonnes pour avoir un modèle commun "place"
-- (ex : espace vert ou ville = space_label)
ALTER TABLE city
  RENAME COLUMN communauteautonome TO ccaa_label;

ALTER TABLE city
  RENAME COLUMN city_label TO space_label;

-- Nettoyage simple : trim / initcap / nullif
-- - TRIM = enlève les espaces inutiles
-- - INITCAP = met en "jolie forme" (première lettre majuscule)
-- - NULLIF = transforme "" en NULL, ou 0 en NULL si 0 veut dire "inconnu"
UPDATE city
SET
  space_label    = INITCAP(TRIM(space_label)),
  wikidata_id    = TRIM(wikidata_id),
  type_label     = INITCAP(TRIM(type_label)),
  ccaa_label     = INITCAP(TRIM(ccaa_label)),
  province_label = INITCAP(TRIM(province_label)),
  coordonnees    = NULLIF(TRIM(coordonnees), ''),
  elevation      = NULLIF(elevation, 0),
  population     = NULLIF(population, 0);

-- Conversion de types : on fixe des types cohérents
-- (évite les soucis ensuite pour calculs/agrégations)
ALTER TABLE city
  ALTER COLUMN elevation   TYPE NUMERIC USING elevation::NUMERIC,
  ALTER COLUMN superficie  TYPE NUMERIC USING superficie::NUMERIC,
  ALTER COLUMN population  TYPE INTEGER USING population::INTEGER;

-- Normalisation des textes : suppression accents + caractères spéciaux
-- pour éviter les faux doublons ("Ávila" vs "Avila") et faciliter les jointures
UPDATE city
SET
  space_label = REGEXP_REPLACE(
    REPLACE(unaccent(TRIM(space_label)), '''', ''), -- enlève aussi les apostrophes
    '[^a-zA-Z0-9\s]', '', 'g'                       -- garde lettres/chiffres/espaces
  ),
  ccaa_label = REGEXP_REPLACE(
    REPLACE(unaccent(TRIM(ccaa_label)), '''', ''),
    '[^a-zA-Z0-9\s]', '', 'g'
  ),
  province_label = REGEXP_REPLACE(
    REPLACE(unaccent(TRIM(province_label)), '''', ''),
    '[^a-zA-Z0-9\s]', '', 'g'
  );

-- Gestion des doublons : on garde 1 ligne par coordonnees
-- ctid = identifiant interne d'une ligne Postgres (pratique en staging)
DELETE FROM city
WHERE ctid NOT IN (
  SELECT MIN(ctid)
  FROM city
  GROUP BY coordonnees
);

-- Suppression d'une ligne problématique (ID Wikidata incorrect)
DELETE FROM city
WHERE wikidata_id = 'Q113502358';

-- Patch manuel : ajout de 3 lieux pour pouvoir matcher les stations météo
-- (les stations comme Ceuta/Melilla/Maspalomas auront un place_id ensuite)
INSERT INTO city (space_label, wikidata_id, type_label, ccaa_label, province_label, coordonnees, elevation, superficie, population)
VALUES
  ('Melilla','Q5831','City', NULL, NULL, 'Point(-2.9475 35.2825)', 30, 12.3338, 86780),
  ('Ceuta','Q5823','City', NULL, NULL, 'Point(-5.3 35.886667)', 10, 18.5, 83595),
  ('Maspalomas','Q580743','City','Canary Islands','Las Palmas','Point(-15.586017 27.760562)', 0, NULL, NULL);

-- ----------------------------
-- 2) ESPACES VERTS (staging)
-- ----------------------------

-- On recrée la table staging à chaque exécution
DROP TABLE IF EXISTS espacesvert CASCADE;

-- Table de travail pour les espaces verts (parcs, réserves, etc.)
CREATE TABLE espacesvert (
  espace           VARCHAR,
  space_label      VARCHAR,
  wikidata_id      VARCHAR,
  type_label       VARCHAR,
  communaute_label VARCHAR,
  province_label   VARCHAR,
  coordonnees      VARCHAR,
  area             FLOAT,
  visiteurs        INTEGER,
  climatlabel      VARCHAR
);

-- Chargement depuis table brute
INSERT INTO espacesvert (
  espace,
  space_label,
  wikidata_id,
  type_label,
  communaute_label,
  province_label,
  coordonnees,
  area,
  visiteurs,
  climatlabel
)
SELECT
  espace,
  space_label,
  wikidata_id,
  type_label,
  communaute_label,
  province_label,
  coordonnees,
  area,
  visiteurs,
  "climatLabel"
FROM espacesvert_complet;

-- On supprime les colonnes inutiles pour le projet final
ALTER TABLE espacesvert
  DROP COLUMN espace,
  DROP COLUMN visiteurs,
  DROP COLUMN climatlabel;

-- Harmonisation des noms de colonnes (comme city)
ALTER TABLE espacesvert
  RENAME COLUMN communaute_label TO ccaa_label;

-- Nettoyage (trim/initcap/nullif)
UPDATE espacesvert
SET
  space_label    = INITCAP(TRIM(space_label)),
  wikidata_id    = TRIM(wikidata_id),
  type_label     = INITCAP(TRIM(type_label)),
  ccaa_label     = INITCAP(TRIM(ccaa_label)),
  province_label = INITCAP(NULLIF(TRIM(province_label), '')),
  coordonnees    = NULLIF(TRIM(coordonnees), ''),
  area           = NULLIF(area, 0);

-- Conversion type : surface en NUMERIC(10,2)
ALTER TABLE espacesvert
  ALTER COLUMN area TYPE NUMERIC(10,2) USING area::NUMERIC(10,2);

-- Normalisation texte (unaccent + suppression caractères spéciaux)
UPDATE espacesvert
SET
  space_label = REGEXP_REPLACE(
    REPLACE(unaccent(TRIM(space_label)), '''', ''),
    '[^a-zA-Z0-9\s]', '', 'g'
  ),
  ccaa_label = REGEXP_REPLACE(
    REPLACE(unaccent(TRIM(ccaa_label)), '''', ''),
    '[^a-zA-Z0-9\s]', '', 'g'
  ),
  province_label = REGEXP_REPLACE(
    REPLACE(unaccent(TRIM(province_label)), '''', ''),
    '[^a-zA-Z0-9\s]', '', 'g'
  );

-- Gestion doublons : même area, on garde 1 ligne
DELETE FROM espacesvert
WHERE ctid NOT IN (
  SELECT MIN(ctid)
  FROM espacesvert
  GROUP BY area
);

-- ============================================================
-- PATCH DE NORMALISATION : Fusion des provinces
-- On harmonise "Provincia de X" vers "X" pour éviter les doublons
-- ============================================================

UPDATE city
SET province_label = CASE 
    WHEN province_label ILIKE '%Cadiz%' THEN 'Cadiz'
    WHEN province_label ILIKE '%Ciudad Real%' THEN 'Ciudad Real'
    ELSE province_label
END
WHERE province_label ILIKE '%Provincia%';

-- On fait la même chose pour les espaces verts au cas où
UPDATE espacesvert
SET province_label = CASE 
    WHEN province_label ILIKE '%Cadiz%' THEN 'Cadiz'
    WHEN province_label ILIKE '%Ciudad Real%' THEN 'Ciudad Real'
    ELSE province_label
END
WHERE province_label ILIKE '%Provincia%';

-- ----------------------------
-- 3) SPACE_COMPLET (union)
-- ----------------------------

-- Table staging unique des lieux : villes + espaces verts
-- Elle servira à charger la table finale PLACE dans le script 02
DROP TABLE IF EXISTS space_complet CASCADE;

-- UNION ALL = on concatène
CREATE TABLE space_complet AS
SELECT
  space_label,
  wikidata_id,
  type_label,
  ccaa_label,
  province_label,
  coordonnees,
  elevation,
  superficie AS area,
  population
FROM city

UNION ALL

SELECT
  space_label,
  wikidata_id,
  type_label,
  ccaa_label,
  province_label,
  coordonnees,
  NULL::NUMERIC(7,3) AS elevation, -- espaces verts : pas d'altitude
  area,
  NULL::INTEGER AS population      -- espaces verts : pas de population
FROM espacesvert;

-- ============================================================
-- ===================== FALCON (STAGING) =====================
-- ============================================================

-- On supprime les tables staging si elles existent déjà
DROP TABLE IF EXISTS falcon_positions_clean CASCADE;
DROP TABLE IF EXISTS selected_falcons CASCADE;
DROP TABLE IF EXISTS falcon_positions_30_downsampled CASCADE;

-- Table de travail : positions faucons nettoyées
CREATE TABLE falcon_positions_clean (
  event_id BIGINT,
  ts_epoch BIGINT,                    -- timestamp en secondes (UTC)
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  ground_speed DOUBLE PRECISION,
  external_temperature DOUBLE PRECISION,
  height_above_msl DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  import_marked_outlier INT,          -- 1 = outlier, 0 = normal
  tag_local_identifier TEXT,
  individual_local_identifier TEXT     -- identifiant de l'individu (faucon)
);

-- Nettoyage et conversion depuis la table brute kestrel34
-- - on supprime les champs vides -> NULL
-- - on convertit le timestamp en epoch UTC
-- - on transforme import-marked-outlier en 0/1
INSERT INTO falcon_positions_clean
SELECT
  NULLIF(BTRIM("event-id"::text), '')::BIGINT,

  -- Conversion du timestamp texte en epoch (UTC)
  CASE
    WHEN NULLIF(BTRIM("timestamp"::text), '') IS NULL THEN NULL
    ELSE EXTRACT(
      EPOCH FROM (
        substring(BTRIM("timestamp"::text) FROM 1 FOR 19)::timestamp
        AT TIME ZONE 'UTC'
      )
    )::BIGINT
  END,

  NULLIF(BTRIM("location-lat"::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("location-long"::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("ground-speed"::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("external-temperature"::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("height-above-msl"::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("heading"::text), '')::DOUBLE PRECISION,

  -- outlier bool -> int
  CASE
    WHEN "import-marked-outlier" IS TRUE  THEN 1
    WHEN "import-marked-outlier" IS FALSE THEN 0
    ELSE NULL
  END,

  NULLIF(BTRIM("tag-local-identifier"::text), ''),
  NULLIF(BTRIM("individual-local-identifier"::text), '')
FROM kestrel34
-- On garde uniquement les lignes exploitables : un individu doit exister
WHERE NULLIF(BTRIM("individual-local-identifier"::text), '') IS NOT NULL;

-- Sélection des 30 faucons avec le plus de points (hors outliers)
-- pour limiter le dataset et garder de la qualité
CREATE TABLE selected_falcons AS
SELECT individual_local_identifier
FROM falcon_positions_clean
WHERE import_marked_outlier = 0
GROUP BY individual_local_identifier
ORDER BY COUNT(*) DESC
LIMIT 30;

-- Downsampling : 1 point / 10 minutes / individu
-- pour réduire le volume tout en gardant une trajectoire lisible
-- (p.ts_epoch / 600) crée un "bucket" de 10 minutes
CREATE TABLE falcon_positions_30_downsampled AS
WITH ranked AS (
  SELECT
    p.*,
    ROW_NUMBER() OVER (
      PARTITION BY p.individual_local_identifier, (p.ts_epoch / 600)
      ORDER BY p.ts_epoch ASC, p.event_id ASC
    ) AS rn
  FROM falcon_positions_clean p
  JOIN selected_falcons s
    ON p.individual_local_identifier = s.individual_local_identifier
  WHERE p.ts_epoch IS NOT NULL
    AND p.import_marked_outlier = 0
)
-- On garde le premier point (rn=1) pour chaque bucket de 10 minutes
SELECT *
FROM ranked
WHERE rn = 1;

-- ============================================================
-- ===================== WEATHER (STAGING) ====================
-- ============================================================

-- Table météo unifiée (les 9 stations)
DROP TABLE IF EXISTS weather_daily_work CASCADE;

-- Table de travail météo "propre"
-- pour avoir 1 seul format, mêmes noms de colonnes, mêmes types
CREATE TABLE weather_daily_work (
  station_code   TEXT,
  station_name   TEXT,
  province       TEXT,
  obs_date       DATE,

  tmin           DOUBLE PRECISION,
  tmed           DOUBLE PRECISION,
  tmax           DOUBLE PRECISION,

  hr_min         DOUBLE PRECISION,
  hr_mean        DOUBLE PRECISION,
  hr_max         DOUBLE PRECISION,

  precip         DOUBLE PRECISION,   -- cas spéciaux Ip/TR/T -> 0.0
  wind_mean      DOUBLE PRECISION,
  wind_gust      DOUBLE PRECISION,
  wind_direction DOUBLE PRECISION
);

-- Chargement : on empile (UNION ALL) les 9 tables brutes
-- Nettoyage :
-- - TRIM
-- - conversion en types numériques
-- - précip : Ip / TR / T = trace -> 0.0
INSERT INTO weather_daily_work (
  station_code, station_name, province, obs_date,
  tmin, tmed, tmax,
  hr_min, hr_mean, hr_max,
  precip, wind_mean, wind_gust, wind_direction
)
SELECT
  NULLIF(BTRIM(indicativo::text), ''),
  NULLIF(BTRIM(nombre::text), ''),
  NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE
    WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
    WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
    ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION
  END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_almonte

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_ceuta

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_jerez

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_las_cabezas_de_san_juan

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_maspalomas

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_palencia

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_san_roque

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_tarifa

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''), NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_villarasa;

-- Index de travail pour accélérer les jointures et filtres station/date
CREATE INDEX ix_weather_work_station_date
ON weather_daily_work (station_code, obs_date);

COMMIT; -- Fin