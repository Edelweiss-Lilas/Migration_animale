-- ============================================================
-- 04_views_dataviz.sql
-- Objectif :
--  - Créer des VUES "prêtes pour Tableau" (datasets faciles à utiliser)
--  - Les vues reposent UNIQUEMENT sur les tables finales :
--      place, falcon, bird_detection, weather_station, weather_measurement
--  - Fournir des datasets déjà agrégés (COUNT / AVG / GROUP BY) pour la dataviz
--
-- Prérequis :
--  - script 01 exécuté (staging)
--  - script 02 exécuté (tables finales)
--  - script 03 exécuté (place_id enrichis au moins partiellement)
-- ============================================================

BEGIN;
SET search_path TO CREC;

-- ============================================================
-- VUE 0 (dataset météo propre) : v_weather_measurement
-- ============================================================
-- Rôle :
--  - fournir un dataset météo "propre" en joignant :
--      weather_measurement (mesures) + weather_station (infos station)
--  - pratique pour Tableau : tout est déjà sur une seule vue
--  - ajoute aussi time_epoch_utc (utile pour certains graphiques temps)

DROP VIEW IF EXISTS v_weather_measurement CASCADE;

CREATE VIEW v_weather_measurement AS
SELECT
  m.measurement_id,

  -- date + timestamp
  m.obs_date,
  m.time,

  -- time en epoch (secondes) : parfois utile pour certains outils / calculs
  EXTRACT(EPOCH FROM (m.time AT TIME ZONE 'UTC'))::BIGINT AS time_epoch_utc,

  -- températures
  m.temperature_min,
  m.temperature_mid,
  m.temperature_max,

  -- humidités
  m.humidity_min,
  m.humidity_mid,
  m.humidity_max,

  -- précipitations
  m.precip,

  -- vent
  m.wind_speed_mid,
  m.wind_gust,
  m.wind_direction,

  -- infos station (dimension)
  s.station_id,
  s.station_code,
  s.name AS station_name,
  s.province,
  s.place_id
FROM weather_measurement m
JOIN weather_station s
  ON s.station_id = m.station_id;

-- ============================================================
-- DATAVIZ 1 : v_dataviz1_passages_region_year
-- ============================================================
-- Question : "Quelles régions / provinces sont les plus concernées
--             par le passage des faucons ?" + comparaison par années
--
-- Principe :
--  - Chaque détection (bird_detection) est rattachée à un lieu (place)
--  - On agrège par :
--      région autonome (ccaa_label)
--      province
--      année
--  - On calcule :
--      nb_detections = nombre de points GPS (volume de passage)
--      nb_faucons = nombre de faucons distincts présents

DROP VIEW IF EXISTS v_dataviz1_passages_region_year CASCADE;

CREATE VIEW v_dataviz1_passages_region_year AS
SELECT
  p.ccaa_label     AS region_autonome,     -- région autonome (ex : Andalusia)
  p.province_label AS province,            -- province (ex : Cadiz)
  EXTRACT(YEAR FROM bd.time) AS year,      -- année de la détection

  COUNT(bd.detection_id) AS nb_detections, -- nombre total de points (intensité)
  COUNT(DISTINCT bd.falcon_id) AS nb_faucons -- combien de faucons différents
FROM bird_detection bd
JOIN place p
  ON p.place_id = bd.place_id              -- on garde seulement les détections rattachées
GROUP BY
  p.ccaa_label,
  p.province_label,
  EXTRACT(YEAR FROM bd.time)
ORDER BY
  year,
  nb_detections DESC;                      -- on affiche d’abord les provinces les plus "actives"

-- ============================================================
-- DATAVIZ 2 : v_dataviz2_migration_vs_meteo_province_month
-- ============================================================
-- Question : "La période migratoire (mois) évolue-t-elle avec la météo ?"
-- (Exemple Tableau : nuage de points / corrélations)
--
-- Idée :
--  1) côté faucons : on agrège les détections par (province, mois)
--  2) côté météo  : on agrège la météo par (province, mois)
--  3) on joint les deux sur (province + mois)
--
-- Résultat : dataset mensuel qui mélange :
--   nb_detections / nb_faucons + moyennes météo (temp, pluie, vent, humidité)

DROP VIEW IF EXISTS v_dataviz2_migration_vs_meteo_province_month CASCADE;

CREATE VIEW v_dataviz2_migration_vs_meteo_province_month AS
WITH
-- ----------------------------
-- 1) Agrégation faucons par province + mois
-- ----------------------------
falcon_by_province_month AS (
  SELECT
    p.province_label AS province,

    -- month_start = début du mois (format date)
    -- très pratique pour joindre avec météo et pour les axes temporels Tableau
    DATE_TRUNC('month', bd.time) AS month_start,

    -- on garde aussi year et month séparés pour des filtres / labels simples
    EXTRACT(YEAR FROM bd.time) AS year,
    EXTRACT(MONTH FROM bd.time) AS month,

    -- volume de passage (nombre de points)
    COUNT(bd.detection_id) AS nb_detections,

    -- nombre de faucons distincts présents ce mois-là dans cette province
    COUNT(DISTINCT bd.falcon_id) AS nb_faucons
  FROM bird_detection bd
  JOIN place p
    ON p.place_id = bd.place_id
  GROUP BY
    p.province_label,
    DATE_TRUNC('month', bd.time),
    EXTRACT(YEAR FROM bd.time),
    EXTRACT(MONTH FROM bd.time)
),

-- ----------------------------
-- 2) Agrégation météo par province + mois
-- ----------------------------
-- On part des mesures météo (weather_measurement)
-- On remonte à la station (weather_station)
-- Puis au lieu (place) via ws.place_id
-- => on récupère la province "standardisée" depuis place.province_label
meteo_by_province_month AS (
  SELECT
    p.province_label AS province,
    DATE_TRUNC('month', wm.time) AS month_start,

    -- On calcule des moyennes mensuelles des variables météo
    AVG(wm.temperature_mid) AS avg_temp,
    AVG(wm.precip)          AS avg_precip,
    AVG(wm.wind_speed_mid)  AS avg_wind,
    AVG(wm.humidity_mid)    AS avg_humidity
  FROM weather_measurement wm
  JOIN weather_station ws
    ON ws.station_id = wm.station_id
  JOIN place p
    ON p.place_id = ws.place_id  -- IMPORTANT : nécessite que ws.place_id soit rempli (script 03)
  GROUP BY
    p.province_label,
    DATE_TRUNC('month', wm.time)
)

-- ----------------------------
-- 3) Jointure faucons + météo
-- ----------------------------
SELECT
  f.province,
  f.year,
  f.month,
  f.nb_detections,
  f.nb_faucons,

  -- variables météo associées au même mois + même province
  m.avg_temp,
  m.avg_precip,
  m.avg_wind,
  m.avg_humidity
FROM falcon_by_province_month f
JOIN meteo_by_province_month m
  ON m.province = f.province
 AND m.month_start = f.month_start
ORDER BY
  f.year, f.month, f.province;

-- ============================================================
-- DATAVIZ 3 : v_dataviz3_urban_vs_green
-- ============================================================
-- Question : "Les faucons sont-ils plus détectés en zone urbaine
--             ou dans les espaces verts ?"
--
-- Méthode :
--  - On classe chaque place en 3 catégories simples :
--      * urban : city / municipality / town...
--      * green : park / natural / reserve / forest / protected...
--      * other : tout le reste
--
-- Important :
--  - LEFT JOIN pour compter aussi les lieux sans détection (optionnel)
--  - COUNT(bd.detection_id) : le nombre total de points sur chaque catégorie
--  - COUNT(DISTINCT bd.falcon_id) : nombre de faucons différents

DROP VIEW IF EXISTS v_dataviz3_urban_vs_green CASCADE;

CREATE VIEW v_dataviz3_urban_vs_green AS
SELECT
  CASE
    -- Catégorie "urban" : on détecte des mots-clés typiques de ville
    WHEN p.type_label ILIKE 'city%'
      OR p.type_label ILIKE '%municip%'
      OR p.type_label ILIKE '%town%'
    THEN 'urban'

    -- Catégorie "green" : on détecte des mots-clés typiques d'espaces naturels
    WHEN p.type_label ILIKE '%park%'
      OR p.type_label ILIKE '%natural%'
      OR p.type_label ILIKE '%reserve%'
      OR p.type_label ILIKE '%protected%'
      OR p.type_label ILIKE '%forest%'
    THEN 'green'

    -- Sinon : on met dans "other"
    ELSE 'other'
  END AS category,

  -- Nombre total de détections (points)
  COUNT(bd.detection_id) AS nb_detections,

  -- Nombre de faucons distincts
  COUNT(DISTINCT bd.falcon_id) AS nb_faucons
FROM place p
LEFT JOIN bird_detection bd
  ON bd.place_id = p.place_id
GROUP BY category
ORDER BY nb_detections DESC;

-- ============================================================
-- BONUS : v_dataviz3_map_points (points pour carte)
-- ============================================================
-- Rôle :
--  - dataset "points" pour faire une carte dans Tableau
--  - pas une agrégation : chaque ligne = 1 détection
--  - on expose :
--      * latitude/longitude
--      * date (year/month)
--      * falcon_id
--      * place_id (si rattaché)
--
-- Très pratique pour :
--  - une map (nuage de points)
--  - des filtres par mois/année/faucon

DROP VIEW IF EXISTS v_dataviz3_map_points CASCADE;

CREATE VIEW v_dataviz3_map_points AS
SELECT
  bd.detection_id,
  bd.time,
  EXTRACT(YEAR FROM bd.time) AS year,
  EXTRACT(MONTH FROM bd.time) AS month,
  bd.falcon_id,
  bd.coordinate[1] AS latitude,
  bd.coordinate[2] AS longitude,
  bd.place_id
FROM bird_detection bd
-- On garde uniquement les points avec de vraies coordonnées
WHERE bd.coordinate IS NOT NULL
  AND bd.coordinate[1] IS NOT NULL
  AND bd.coordinate[2] IS NOT NULL;

COMMIT;
