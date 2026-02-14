-- ============================================================
-- 03_enrichissement_fk.sql (FINAL : PATCH 5960 + MASPALOMAS + SEUIL EFFECTIF)
-- Objectif :
--  - Enrichir / remplir des clés étrangères (FK) après création des tables finales
--  - Remplir weather_station.place_id (matching par nom + patches)
--  - Remplir bird_detection.place_id (nearest place) SANS PostGIS
--    avec un SEUIL de distance (2° ~ ~200 km) pour éviter les rattachements absurdes
--
-- Stratégie bird_detection -> place :
--  1) extraire lat/lon des lieux depuis place.coordonnees (Point(lon lat))
--  2) corriger : annuler les affectations trop lointaines (> 2°)
--  3) recalculer nearest place seulement pour les place_id = NULL
--     en limitant la recherche à une "bbox" (fenêtre autour du point)
--     + appliquer le seuil final dist < 2°
-- ============================================================

BEGIN;

-- Extension utile pour comparer des noms sans accents
CREATE EXTENSION IF NOT EXISTS unaccent;

-- On travaille dans CREC (et public en secours)
SET search_path TO CREC, public;

-- ============================================================
-- 0) place_lat / place_lon depuis coordonnees (relançable)
-- ============================================================
-- Problème :
--  - place.coordonnees est un TEXTE "Point(lon lat)"
--  - pour calculer une distance, on a besoin de colonnes numériques lat/lon
--
-- Solution :
--  - on ajoute 2 colonnes si elles n'existent pas
--  - puis on les remplit en extrayant lon/lat avec une regex

-- Ajoute les colonnes si elles n'existent pas (script relançable)
ALTER TABLE place ADD COLUMN IF NOT EXISTS place_lon DOUBLE PRECISION;
ALTER TABLE place ADD COLUMN IF NOT EXISTS place_lat DOUBLE PRECISION;

-- Remplit les colonnes uniquement si :
--  - coordonnees n'est pas NULL
--  - et place_lon / place_lat sont encore NULL (évite de recalculer inutilement)
UPDATE place
SET
  -- regexp_match(...) renvoie un tableau de matches
  -- [1] = longitude, [2] = latitude (car format Point(lon lat))
  place_lon = (regexp_match(coordonnees,'Point\(([-0-9\.]+)\s+([-0-9\.]+)\)'))[1]::DOUBLE PRECISION,
  place_lat = (regexp_match(coordonnees,'Point\(([-0-9\.]+)\s+([-0-9\.]+)\)'))[2]::DOUBLE PRECISION
WHERE coordonnees IS NOT NULL
  AND (place_lon IS NULL OR place_lat IS NULL);

-- Index utile pour accélérer les recherches sur lat/lon (même sans PostGIS)
CREATE INDEX IF NOT EXISTS ix_place_lat_lon
ON place (place_lat, place_lon);

-- ============================================================
-- 1) weather_station.place_id (matching + patches)
-- ============================================================
-- Objectif :
--  - rattacher chaque station météo à un lieu dans place
--  - on remplit weather_station.place_id
--
-- Méthode :
--  A) matching EXACT sur le nom (sans accents / sans casse)
--  B) patch "suffixe" : station_name = "X AEROPUERTO" doit matcher "X"
--  C) patch manuel Maspalomas via wikidata_id

-- A) Matching exact : ws.name == p.space_label
-- On ignore la casse et les accents (unaccent + upper)
-- On limite aux villes (type_label "city") si possible
UPDATE weather_station ws
SET place_id = p.place_id
FROM place p
WHERE ws.place_id IS NULL                      -- on ne modifie que celles pas encore matchées
  AND ws.name IS NOT NULL
  AND p.space_label IS NOT NULL
  AND upper(unaccent(btrim(ws.name))) = upper(unaccent(btrim(p.space_label)))
  AND (p.type_label ILIKE 'city%' OR p.type_label IS NULL);

-- B) Patch suffixe :
-- Exemple : "JEREZ AEROPUERTO" doit matcher "Jerez"
-- Ici : on accepte que ws.name commence par p.space_label
UPDATE weather_station ws
SET place_id = p.place_id
FROM place p
WHERE ws.place_id IS NULL
  AND ws.name IS NOT NULL
  AND p.space_label IS NOT NULL
  AND (p.type_label ILIKE 'city%' OR p.type_label IS NULL)
  AND upper(unaccent(btrim(ws.name))) LIKE upper(unaccent(btrim(p.space_label))) || '%';

-- C) Patch spécifique Maspalomas :
-- On sait exactement quelle station_code correspond à Maspalomas
-- Donc on force le lien via l'id Wikidata (fiable)
UPDATE weather_station ws
SET place_id = p.place_id
FROM place p
WHERE ws.station_code = 'C689E'
  AND p.wikidata_id = 'Q580743';

-- ============================================================
-- 2) bird_detection.place_id : rendre le seuil EFFECTIF
-- ============================================================
-- Problème :
--  - On veut rattacher une détection au lieu le plus proche
--  - MAIS on veut éviter les liens absurdes (ex : point GPS en mer -> ville à 1000 km)
--
-- Choix projet :
--  - seuil = 2 degrés environ
--  - comme on calcule une "distance au carré" dist2 :
--      dist2 > 4  <=> distance > 2°
--
-- Ici :
--  - on annule d'abord les affectations trop lointaines
--  - comme ça, on repart propre avant de recalculer

-- Index utile si on filtre souvent sur place_id
CREATE INDEX IF NOT EXISTS ix_bird_detection_place_id
ON bird_detection (place_id);

-- Annule les rattachements trop loin (> 2°)
-- Conditions de sécurité :
--  - on vérifie que le point a bien une coordonnée lat/lon
--  - et que le lieu a bien place_lat/place_lon
UPDATE bird_detection bd
SET place_id = NULL
FROM place p
WHERE bd.place_id = p.place_id
  AND bd.coordinate IS NOT NULL
  AND bd.coordinate[1] IS NOT NULL  -- latitude
  AND bd.coordinate[2] IS NOT NULL  -- longitude
  AND p.place_lat IS NOT NULL
  AND p.place_lon IS NOT NULL
  AND (
    -- Distance au carré (approximation simple en degrés, sans PostGIS)
    ((p.place_lat - bd.coordinate[1]) * (p.place_lat - bd.coordinate[1])
   + (p.place_lon - bd.coordinate[2]) * (p.place_lon - bd.coordinate[2])) > 4
  );

-- ============================================================
-- 3) Recalculer le nearest uniquement pour les NULL (bbox + seuil)
-- ============================================================
-- Objectif :
--  - remplir bird_detection.place_id pour les détections non rattachées (place_id IS NULL)
--  - trouver le lieu le plus proche, MAIS :
--      * on limite la recherche à une zone locale (bbox) pour aller vite
--      * on applique le seuil final dist2 < 4 (distance < 2°)
--
-- Important :
--  - JOIN LATERAL permet de faire une "mini requête" place par place
--    pour trouver le meilleur lieu (le plus proche) pour une détection donnée.

WITH nearest_place AS (
  SELECT
    bd.detection_id,
    np.place_id
  FROM bird_detection bd

  -- Pour chaque détection bd, on cherche 1 seul place le plus proche (LIMIT 1)
  JOIN LATERAL (
    SELECT
      p.place_id,

      -- dist2 = distance^2 (évite SQRT, plus rapide)
      ((p.place_lat - bd.coordinate[1]) * (p.place_lat - bd.coordinate[1])
     + (p.place_lon - bd.coordinate[2]) * (p.place_lon - bd.coordinate[2])) AS dist2
    FROM place p
    WHERE p.place_lat IS NOT NULL
      AND p.place_lon IS NOT NULL

      -- BBOX : on restreint la recherche autour du point
      -- But : éviter de comparer avec les 7000 lieux à chaque détection
      -- Ici : +/- 0.30 degré autour du point (fenêtre carrée)
      -- (tu as noté : augmenter à 0.60 si trop de NULL)
      AND p.place_lat BETWEEN (bd.coordinate[1] - 0.30) AND (bd.coordinate[1] + 0.30)
      AND p.place_lon BETWEEN (bd.coordinate[2] - 0.30) AND (bd.coordinate[2] + 0.30)

    -- On trie par distance croissante = le plus proche en premier
    ORDER BY dist2 ASC
    LIMIT 1
  ) np ON TRUE

  -- On ne traite que les détections non rattachées
  WHERE bd.place_id IS NULL
    AND bd.coordinate IS NOT NULL
    AND bd.coordinate[1] IS NOT NULL
    AND bd.coordinate[2] IS NOT NULL

    -- SEUIL FINAL : si dist2 >= 4, on ne rattache pas (reste NULL)
    AND np.dist2 < 4
)

-- Mise à jour finale : on applique les nouveaux place_id calculés
UPDATE bird_detection bd
SET place_id = n.place_id
FROM nearest_place n
WHERE bd.detection_id = n.detection_id;

-- ============================================================
-- 4) Vérifications
-- ============================================================
-- But : donner un petit "rapport" de couverture après enrichissement

-- Couverture stations météo : combien ont un place_id ?
SELECT
  COUNT(*) AS weather_station_total,
  COUNT(place_id) AS weather_station_with_place_id,
  ROUND(100.0 * COUNT(place_id) / NULLIF(COUNT(*),0), 2) AS pct
FROM weather_station;

-- Couverture bird_detection : combien ont un place_id ?
SELECT
  COUNT(*) AS bird_detection_total,
  COUNT(place_id) AS bird_detection_with_place_id,
  ROUND(100.0 * COUNT(place_id) / NULLIF(COUNT(*),0), 2) AS pct
FROM bird_detection;

COMMIT;