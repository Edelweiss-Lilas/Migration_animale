-- ============================================================
-- 02_tables_finales.sql
-- Objectif :
--  - Créer les tables finales "propres" : PLACE, FALCON, BIRD_DETECTION, WEATHER_STATION, WEATHER_MEASUREMENT
--  - Mettre les PK et FK
--  - Charger les données depuis les tables de staging (script 01)
--
-- Important :
--  - On NE remplit pas place_id dans bird_detection ici.
--    Le rattachement géographique (nearest place) se fait dans le script 03.
-- Prérequis :
--  - space_complet, selected_falcons, falcon_positions_30_downsampled, weather_daily_work existent
-- ============================================================

BEGIN; -- Transaction : si un bloc plante, rien ne reste en base
SET search_path TO CREC;

-- ============================================================
-- 1) TABLE FINALE : PLACE
-- ============================================================
-- Rôle : stocker tous les lieux (villes + espaces verts) dans UNE table
-- But : avoir un référentiel unique "place" pour relier :
--   - bird_detection.place_id (détections)
--   - weather_station.place_id (stations météo)

-- On recrée la table à zéro
DROP TABLE IF EXISTS place CASCADE;

-- Table finale PLACE
-- place_id = clé primaire auto-générée
CREATE TABLE place (
  place_id        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  space_label     VARCHAR(255),
  wikidata_id     VARCHAR(255),
  type_label      VARCHAR(255),
  ccaa_label      VARCHAR(255),
  province_label  VARCHAR(255),
  coordonnees     VARCHAR(255),      -- format "Point(lon lat)" (texte)
  elevation       NUMERIC(7,3),
  area            NUMERIC,
  population      INTEGER
);

-- Chargement depuis la table staging space_complet (script 01)
INSERT INTO place (
  space_label,
  wikidata_id,
  type_label,
  ccaa_label,
  province_label,
  coordonnees,
  elevation,
  area,
  population
)
SELECT
  space_label,
  wikidata_id,
  type_label,
  ccaa_label,
  province_label,
  coordonnees,
  elevation,
  area,
  population
FROM space_complet;

-- ============================================================
-- 2) TABLE FINALE : FALCON
-- ============================================================
-- Rôle : table de référence des faucons sélectionnés (les 30)
-- pour éviter de répéter le texte de l'identifiant partout dans bird_detection
-- On crée un falcon_id + falcon_code (clé métier = identifiant individu)

DROP TABLE IF EXISTS falcon CASCADE;

CREATE TABLE falcon (
  falcon_id   SERIAL PRIMARY KEY,      -- identifiant auto (clé technique)
  falcon_code TEXT UNIQUE NOT NULL,    -- identifiant individu (clé métier)
  tag_id      TEXT,                    -- identifiant du tag GPS
  nickname    TEXT NOT NULL DEFAULT 'NONE' -- optionnel (futur usage)
);

-- Insertion des 30 faucons sélectionnés (table selected_falcons du script 01)
-- tag_id : on prend 1 valeur non vide si possible parmi les positions downsampled
INSERT INTO falcon (falcon_code, tag_id, nickname)
SELECT
  s.individual_local_identifier,

  -- Sous-requête :
  -- on cherche un tag_local_identifier associé à cet individu
  -- on prend le "meilleur" : non NULL si possible
  (
    SELECT NULLIF(BTRIM(p.tag_local_identifier), '')
    FROM falcon_positions_30_downsampled p
    WHERE p.individual_local_identifier = s.individual_local_identifier
    ORDER BY (p.tag_local_identifier IS NULL), p.tag_local_identifier
    LIMIT 1
  ) AS tag_id,

  -- Pour l’instant : pas de surnom, donc valeur par défaut
  'NONE' AS nickname
FROM selected_falcons s;

-- ============================================================
-- 3) TABLE FINALE : BIRD_DETECTION
-- ============================================================
-- Rôle : table principale avec un énorme volume = les points GPS
-- Chaque ligne = 1 détection (position) d’un faucon à un instant donné
-- On relie :
--   - falcon_id (obligatoire) -> table falcon
--   - place_id (optionnel) -> table place (remplie plus tard script 03)

DROP TABLE IF EXISTS bird_detection CASCADE;

CREATE TABLE bird_detection (
  detection_id SERIAL PRIMARY KEY,      -- identifiant auto
  time         TIMESTAMP,               -- date/heure de la détection
  coordinate   DOUBLE PRECISION[],      -- tableau [latitude, longitude]
  speed        DOUBLE PRECISION,        -- vitesse au sol
  altitude     DOUBLE PRECISION,        -- altitude (height_above_msl)
  falcon_id    INT NOT NULL,            -- FK obligatoire : chaque détection appartient à un faucon
  place_id     INT,                     -- FK optionnelle : lieu le plus proche (calculé en script 03)

  -- FK vers falcon
  CONSTRAINT fk_bird_detection_falcon
    FOREIGN KEY (falcon_id) REFERENCES falcon(falcon_id),

  -- FK vers place
  CONSTRAINT fk_bird_detection_place
    FOREIGN KEY (place_id) REFERENCES place(place_id)
);

-- Chargement depuis falcon_positions_30_downsampled (script 01)
-- On convertit ts_epoch en timestamp UTC
-- On joint avec falcon pour convertir falcon_code (texte) -> falcon_id (int)
INSERT INTO bird_detection (
  time,
  coordinate,
  speed,
  altitude,
  falcon_id
)
SELECT
  to_timestamp(p.ts_epoch) AT TIME ZONE 'UTC',   -- epoch -> timestamp (UTC)
  ARRAY[p.latitude, p.longitude],                -- stockage tableau [lat, lon]
  p.ground_speed,
  p.height_above_msl,
  f.falcon_id
FROM falcon_positions_30_downsampled p
JOIN falcon f
  ON f.falcon_code = p.individual_local_identifier
-- On élimine les points sans coordonnées (impossible à cartographier et matcher)
WHERE p.latitude IS NOT NULL
  AND p.longitude IS NOT NULL;

-- ============================================================
-- 4) TABLE FINALE : WEATHER_STATION
-- ============================================================
-- Rôle : table de référence des stations météo (9 stations)
--  - 1 ligne par station
--  - station_code unique (clé métier)
--  - place_id sera rempli dans script 03 (matching par nom puis patch)

DROP TABLE IF EXISTS weather_station CASCADE;

CREATE TABLE weather_station (
  station_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- identifiant technique
  station_code TEXT NOT NULL UNIQUE,                            -- code station (clé métier)
  name         TEXT,
  province     TEXT,
  place_id     INT,                                             -- FK vers place, rempli plus tard

  CONSTRAINT fk_weather_station_place
    FOREIGN KEY (place_id) REFERENCES place(place_id)
);

-- On crée 1 ligne par station_code
-- DISTINCT ON = technique Postgres pour garder 1 seule ligne par station_code
-- ORDER BY : on essaye de garder la ligne la plus propre (nom non NULL en priorité)
INSERT INTO weather_station (station_code, name, province, place_id)
SELECT DISTINCT ON (w.station_code)
  w.station_code,
  w.station_name,
  w.province,
  NULL::INT AS place_id  -- volontairement NULL ici : enrichi au script 03
FROM weather_daily_work w
WHERE w.station_code IS NOT NULL
  AND BTRIM(w.station_code) <> ''
ORDER BY
  w.station_code,
  (w.station_name IS NULL) ASC, -- FALSE (non NULL) avant TRUE (NULL)
  w.station_name ASC;

-- Index utile pour chercher vite une station par code
CREATE INDEX ix_weather_station_code
ON weather_station (station_code);

-- ============================================================
-- 5) TABLE FINALE : WEATHER_MEASUREMENT
-- ============================================================
-- Rôle : table "fact" météo (mesures quotidiennes)
-- Chaque ligne = 1 station + 1 date (obs_date)
-- On impose une unicité : (station_id, obs_date) unique pour éviter les doublons si on relance l'insert

DROP TABLE IF EXISTS weather_measurement CASCADE;

CREATE TABLE weather_measurement (
  measurement_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  obs_date         DATE NOT NULL,       -- date de la mesure
  time             TIMESTAMP NOT NULL,  -- timestamp associé (ici : minuit UTC)

  temperature_min  DOUBLE PRECISION,
  temperature_mid  DOUBLE PRECISION,
  temperature_max  DOUBLE PRECISION,

  humidity_min     DOUBLE PRECISION,
  humidity_mid     DOUBLE PRECISION,
  humidity_max     DOUBLE PRECISION,

  precip           DOUBLE PRECISION,

  wind_speed_mid   DOUBLE PRECISION,
  wind_gust        DOUBLE PRECISION,
  wind_direction   DOUBLE PRECISION,

  station_id       BIGINT NOT NULL,     -- FK obligatoire vers station

  CONSTRAINT fk_weather_measurement_station
    FOREIGN KEY (station_id) REFERENCES weather_station(station_id),

  -- Contrainte d'unicité : 1 station = 1 mesure par jour
  CONSTRAINT ux_weather_measurement_station_date
    UNIQUE (station_id, obs_date)
);

-- Chargement depuis weather_daily_work
-- On joint avec weather_station pour convertir station_code -> station_id
-- time = obs_date à minuit UTC (choix simple pour une donnée journalière)
INSERT INTO weather_measurement (
  obs_date,
  time,
  temperature_min,
  temperature_mid,
  temperature_max,
  humidity_min,
  humidity_mid,
  humidity_max,
  precip,
  wind_speed_mid,
  wind_gust,
  wind_direction,
  station_id
)
SELECT
  w.obs_date,
  (w.obs_date::timestamp AT TIME ZONE 'UTC')::timestamp AS time,

  w.tmin AS temperature_min,
  w.tmed AS temperature_mid,
  w.tmax AS temperature_max,

  w.hr_min  AS humidity_min,
  w.hr_mean AS humidity_mid,
  w.hr_max  AS humidity_max,

  w.precip,

  w.wind_mean AS wind_speed_mid,
  w.wind_gust,
  w.wind_direction,

  s.station_id
FROM weather_daily_work w
JOIN weather_station s
  ON s.station_code = w.station_code
WHERE w.obs_date IS NOT NULL
  AND w.station_code IS NOT NULL
  AND BTRIM(w.station_code) <> ''
-- Si doublon station/date : on ignore (script relançable sans casse)
ON CONFLICT (station_id, obs_date) DO NOTHING;

-- Index utiles (perf) :
-- - jointures station_id
-- - filtres par date
-- - séries temporelles sur time
CREATE INDEX ix_weather_measurement_station
ON weather_measurement (station_id);

CREATE INDEX ix_weather_measurement_date
ON weather_measurement (obs_date);

CREATE INDEX ix_weather_measurement_time
ON weather_measurement (time);

-- ============================================================
-- 6) TABLE FINALE : USER_ACCOUNT et COMMENT
-- ============================================================
-- Rôle : Cela permet de conserver les données une fois le compte utilisateur créer.

DROP TABLE IF EXISTS user_account CASCADE;
DROP TABLE IF EXISTS comment CASCADE;

CREATE TABLE user_account (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(80) UNIQUE NOT NULL,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    bio TEXT
);

CREATE TABLE comment (
    comment_id SERIAL PRIMARY KEY,
    content TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    user_id INTEGER NOT NULL REFERENCES crec.user_account(user_id),
    falcon_id INTEGER NOT NULL REFERENCES crec.falcon(falcon_id)
);

-- Index pour accélérer les requêtes (ex: "tous les commentaires du faucon X")
CREATE INDEX ix_comment_user_id ON comment (user_id);
CREATE INDEX ix_comment_falcon_id ON comment (falcon_id);

COMMIT; -- Fin