-- Marque le début de ma transaction
BEGIN;

-- Toujours utiliser le même schéma. !!ATTENTION!! si vous ne le configurez pas, vous serez obligé de préciser {nom_schema}.{nom_table} pour chaque requête ! Le nom dus schéma ici doit être le même que dans le fichier .env du script python
SET search_path TO CREC;

-- CREATION et nettoyage PLACE 

-- City

-- suppression des colonnes non souhaitées dans city
ALTER TABLE communes_global
 DROP COLUMN commune,
 DROP COLUMN  continent,
 DROP COLUMN "contientLabel",
 DROP COLUMN  pays,
 DROP COLUMN  "paysLabel",
DROP COLUMN latitude,
DROP COLUMN longitude,
 DROP COLUMN  "pointCulminant",
 DROP COLUMN "pointCulminantLabel";

-- Renommer les colonnes
ALTER TABLE communes_global
RENAME COLUMN "communauteAutonome" TO ccaa_label;

ALTER TABLE communes_global
RENAME COLUMN  city_label to space_label;

-- Traitement données
UPDATE communes_global
SET
   space_label = INITCAP(TRIM(space_label)),
   wikidata_id = TRIM(wikidata_id),
   type_label = INITCAP(TRIM(type_label)),
   ccaa_label = INITCAP(TRIM(ccaa_label)),
   province_label = INITCAP(TRIM(province_label)),
   coordonnees = NULLIF(TRIM(coordonnees), ''),
   elevation = NULLIF(elevation, 0),     
   population = NULLIF(population, 0);

-- Conversion type de données
ALTER TABLE communes_global
ALTER COLUMN elevation TYPE NUMERIC
   USING elevation::NUMERIC,
ALTER COLUMN superficie TYPE NUMERIC
   USING superficie::NUMERIC,
ALTER COLUMN population TYPE INTEGER
   USING population::INTEGER;

-- Enlever les accents et signes spécifiques
UPDATE communes_global
SET
   space_label = REGEXP_REPLACE(
       REPLACE(
           public.unaccent(TRIM(space_label)),
           '''',
           ''
       ),
       '[^a-zA-Z0-9\s]',
       '',
       'g'
   ),
   ccaa_label = REGEXP_REPLACE(
       REPLACE(
           public.unaccent(TRIM(ccaa_label)),
           '''',
           ''
       ),
       '[^a-zA-Z0-9\s]',
       '',
       'g'
   ),
   province_label = REGEXP_REPLACE(
       REPLACE(
           public.unaccent(TRIM(province_label)),
           '''',
           ''
       ),
       '[^a-zA-Z0-9\s]',
       '',
       'g'
   );

-- Gérer les doublons et faux-doublons
DELETE FROM communes_global
WHERE ctid NOT IN (
   SELECT MIN(ctid)
   FROM communes_global
   GROUP BY coordonnees);

-- Identifier les space_label qui prennent la forme d’un wikidata_id 
delete from communes_global cg
where "wikidata_id" = 'Q113502358';

-- Insérer les métdonnées de Ceuta et Melilla
insert  into communes_global (space_label,wikidata_id, type_label, ccaa_label,  province_label,coordonnees, elevation , superficie, population)
values ('Melilla','Q5831','City', NULL, NULL, 'Point(-2.9475 35.2825)',30,12.3338,86780);

insert  into communes_global (space_label,wikidata_id, type_label, ccaa_label,  province_label,coordonnees, elevation , superficie, population)
values ('Ceuta','Q5823','City', NULL, NULL, 'Point(-5.3 35.886667)',10,18.5,83595);

-- Natural spaces

-- suppression des colonnes non souhaitées dans natural spaces
alter table espacesvert_complet
drop column espace,
drop column visiteurs,
drop column "climatLabel";

-- Renommer les colonnes
ALTER TABLE espacesvert_complet
RENAME COLUMN communaute_label TO ccaa_label;

-- Traitement données
UPDATE espacesvert_complet
SET
   space_label = INITCAP(TRIM(space_label)),
   wikidata_id = TRIM(wikidata_id),
   type_label = INITCAP(TRIM(type_label)),
   ccaa_label = INITCAP(TRIM(ccaa_label)),
   province_label = INITCAP(nullif(TRIM(province_label), '')), --ajout d’un nullif car certaines données sur les provinces sont manquantes
   coordonnees = NULLIF(TRIM(coordonnees), ''),
   area = NULLIF(area, 0);    

-- Conversion type de données
ALTER TABLE espacesvert_complet
ALTER COLUMN area TYPE NUMERIC(10, 2)
   USING area::NUMERIC(10, 2);

-- Enlever les accents et signes spécifiques
UPDATE espacesvert_complet ec
SET
   space_label = REGEXP_REPLACE(
       REPLACE(
           public.unaccent(TRIM(space_label)),
           '''',
           ''
       ),
       '[^a-zA-Z0-9\s]',
       '',
       'g'
   ),
   ccaa_label = REGEXP_REPLACE(
       REPLACE(
           public.unaccent(TRIM(ccaa_label)),
           '''',
           ''
       ),
       '[^a-zA-Z0-9\s]',
       '',
       'g'
   ),
   province_label = REGEXP_REPLACE(
       REPLACE(
           public.unaccent(TRIM(province_label)),
           '''',
           ''
       ),
       '[^a-zA-Z0-9\s]',
       '',
       'g'
   );

-- Gérer les doublons et faux doublons
DELETE FROM espacesvert_complet
WHERE ctid NOT IN (
  SELECT MIN(ctid)
  FROM espacesvert_complet ec
  GROUP BY area);



-- Création de la table space_complet avec une jointure UNION ALL
DROP TABLE IF EXISTS space_complet;
CREATE TABLE space_complet AS
SELECT
   space_label,
   wikidata_id,
   type_label,
   ccaa_label,
   province_label,
   coordonnees,
   elevation,
   superficie as area,
   population
FROM communes_global
UNION ALL
SELECT
   space_label,
   wikidata_id,
   type_label,
   ccaa_label,
   province_label,
   coordonnees,
   NULL::NUMERIC(7,3) AS elevation, --colonne qui n’existe pas dans espacesvert
   area,
   NULL::INTEGER AS population --colonne qui n’existe pas dans espacesvert
FROM espacesvert_complet;


-- CREATION et nettoyage FALCON 

DROP TABLE IF EXISTS bird_detection CASCADE;
DROP TABLE IF EXISTS falcon CASCADE;

DROP TABLE IF EXISTS falcon_positions_clean CASCADE;
DROP TABLE IF EXISTS selected_falcons CASCADE;
DROP TABLE IF EXISTS falcon_positions_30_downsampled CASCADE;


-- 1. TABLE TEMPORAIRE : NETTOYAGE DES DONNÉES

CREATE TABLE falcon_positions_clean (
  event_id BIGINT,
  ts_epoch BIGINT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  ground_speed DOUBLE PRECISION,
  external_temperature DOUBLE PRECISION,
  height_above_msl DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  import_marked_outlier INT,
  tag_local_identifier TEXT,
  individual_local_identifier TEXT
);

INSERT INTO falcon_positions_clean
SELECT
  NULLIF(BTRIM("event-id"::text), '')::BIGINT,

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

  CASE
    WHEN "import-marked-outlier" IS TRUE  THEN 1
    WHEN "import-marked-outlier" IS FALSE THEN 0
    ELSE NULL
  END,

  NULLIF(BTRIM("tag-local-identifier"::text), ''),
  NULLIF(BTRIM("individual-local-identifier"::text), '')
FROM "KESTREL34"
WHERE NULLIF(BTRIM("individual-local-identifier"::text), '') IS NOT NULL;


-- 2. SÉLECTION DES 30 FAUCONS LES PLUS DOCUMENTÉS

CREATE TABLE selected_falcons AS
SELECT
  individual_local_identifier
FROM falcon_positions_clean
WHERE import_marked_outlier = 0
GROUP BY individual_local_identifier
ORDER BY COUNT(*) DESC
LIMIT 30;


-- 3. DOWNSAMPLING (1 POINT/10 MIN/INDIVIDU)

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
SELECT *
FROM ranked
WHERE rn = 1;

-- CREATION et nettoyage BIRD DETECTION 


-- CREATION et nettoyage WEATHER STATION 

DROP VIEW  IF EXISTS v_weather_measurement CASCADE;

DROP TABLE IF EXISTS weather_measurement CASCADE;
DROP TABLE IF EXISTS weather_station CASCADE;

DROP TABLE IF EXISTS weather_daily_work CASCADE;


-- 1. TABLE DE TRAVAIL : NETTOYAGE / HARMONISATION (MULTI-STATIONS)
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

  precip         DOUBLE PRECISION, 
  wind_mean      DOUBLE PRECISION,         
  wind_gust      DOUBLE PRECISION,      
  wind_direction DOUBLE PRECISION
);

-- INSERTION DEPUIS LES 9 TABLES BRUTES METEO (stations)
INSERT INTO weather_daily_work (
  station_code, station_name, province, obs_date,
  tmin, tmed, tmax,
  hr_min, hr_mean, hr_max,
  precip, wind_mean, wind_gust, wind_direction
)
SELECT
  NULLIF(BTRIM(indicativo::text), '')                  AS station_code,
  NULLIF(BTRIM(nombre::text), '')                      AS station_name,
  NULLIF(BTRIM(provincia::text), '')                   AS province,
  NULLIF(BTRIM(fecha::text), '')::DATE                 AS obs_date,

  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION      AS tmin,
  NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION      AS tmed,
  NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION      AS tmax,

  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION   AS hr_min,
  NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION AS hr_mean,
  NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION   AS hr_max,

  CASE
    WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
    WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
    ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION
  END                                                  AS precip,

  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION  AS wind_mean,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION     AS wind_gust,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION       AS wind_direction
FROM meteo_almonte

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_ceuta

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_tarifa

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_jerez

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_las_cabezas_de_san_juan

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_maspalomas

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_palencia

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_san_roque

UNION ALL SELECT
  NULLIF(BTRIM(indicativo::text), ''), NULLIF(BTRIM(nombre::text), ''), NULLIF(BTRIM(provincia::text), ''),
  NULLIF(BTRIM(fecha::text), '')::DATE,
  NULLIF(BTRIM(tmin::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmed::text), '')::DOUBLE PRECISION, NULLIF(BTRIM(tmax::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM("hrMin"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMedia"::text), '')::DOUBLE PRECISION, NULLIF(BTRIM("hrMax"::text), '')::DOUBLE PRECISION,
  CASE WHEN NULLIF(BTRIM(prec::text), '') IS NULL THEN NULL
       WHEN LOWER(BTRIM(prec::text)) IN ('ip','tr','t') THEN 0.0
       ELSE NULLIF(BTRIM(prec::text), '')::DOUBLE PRECISION END,
  NULLIF(BTRIM(velmedia::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(racha::text), '')::DOUBLE PRECISION,
  NULLIF(BTRIM(dir::text), '')::DOUBLE PRECISION
FROM meteo_villarasa;

-- Index de travail
CREATE INDEX ix_weather_work_station_date
ON weather_daily_work (station_code, obs_date);



-- CREATION et nettoyage  WEATHER MEASUREMENT 


-- Marque la fin de ma transaction (et donc de mon script)
COMMIT ;
