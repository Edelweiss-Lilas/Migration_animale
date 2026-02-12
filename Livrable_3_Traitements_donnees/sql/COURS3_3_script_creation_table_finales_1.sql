-- Marque le début de ma transaction (début du script)
BEGIN ;

-- Toujours utiliser le même schéma. !!ATTENTION!! si vous ne le configurez pas, vous serez obligé de préciser {nom_schema}.{nom_table} pour chaque requête ! Le nom dus schéma ici doit être le même que dans le fichier .env du script python
SET search_path TO CREC;


-- CREATION et nettoyage PLACE finale


-- CREATION et nettoyage FALCON finale
-- 4. TABLE FINALE : FALCON

CREATE TABLE falcon (
  falcon_id SERIAL PRIMARY KEY,
  falcon_code TEXT UNIQUE NOT NULL,
  tag_id TEXT,
  nickname TEXT NOT NULL DEFAULT 'NONE'
);

INSERT INTO falcon (falcon_code, tag_id, nickname)
SELECT
  s.individual_local_identifier,
  (
    SELECT NULLIF(BTRIM(p.tag_local_identifier), '')
    FROM falcon_positions_30_downsampled p
    WHERE p.individual_local_identifier = s.individual_local_identifier
    ORDER BY (p.tag_local_identifier IS NULL), p.tag_local_identifier
    LIMIT 1
  ),
  'NONE'
FROM selected_falcons s;


-- 5. TABLE FINALE : BIRD_DETECTION

CREATE TABLE bird_detection (
  detection_id SERIAL PRIMARY KEY,
  time TIMESTAMP,
  coordinate DOUBLE PRECISION[],
  speed DOUBLE PRECISION,
  altitude DOUBLE PRECISION,
  falcon_id INT NOT NULL,
  CONSTRAINT fk_bird_detection_falcon
    FOREIGN KEY (falcon_id) REFERENCES falcon(falcon_id)
);

INSERT INTO bird_detection (
  time,
  coordinate,
  speed,
  altitude,
  falcon_id
)
SELECT
  to_timestamp(p.ts_epoch) AT TIME ZONE 'UTC',
  ARRAY[p.latitude, p.longitude],
  p.ground_speed,
  p.height_above_msl,
  f.falcon_id
FROM falcon_positions_30_downsampled p
JOIN falcon f
  ON f.falcon_code = p.individual_local_identifier
WHERE p.latitude IS NOT NULL
  AND p.longitude IS NOT NULL;


-- CREATION et nettoyage BIRD DETECTION finale


-- CREATION et nettoyage WEATHER STATION finale
-- 2. TABLE FINALE : WEATHER_STATION (référentiel)
CREATE TABLE weather_station (
  station_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  station_code TEXT NOT NULL UNIQUE,
  name         TEXT,
  province     TEXT,
  place_id     INT                   -- NULL tant que PLACE n'est pas implémenté
);

INSERT INTO weather_station (station_code, name, province, place_id)
SELECT DISTINCT ON (w.station_code)
  w.station_code,
  w.station_name,
  w.province,
  NULL::INT AS place_id
FROM weather_daily_work w
WHERE w.station_code IS NOT NULL
  AND BTRIM(w.station_code) <> ''
ORDER BY
  w.station_code,
  (w.station_name IS NULL) ASC,
  w.station_name ASC;

CREATE INDEX ix_weather_station_code
ON weather_station (station_code);


-- 3. TABLE FINALE : WEATHER_MEASUREMENT
CREATE TABLE weather_measurement (
  measurement_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  obs_date         DATE NOT NULL,
  time             TIMESTAMP NOT NULL,

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

  station_id       BIGINT NOT NULL,

  CONSTRAINT fk_weather_measurement_station
    FOREIGN KEY (station_id) REFERENCES weather_station(station_id),

  CONSTRAINT ux_weather_measurement_station_date
    UNIQUE (station_id, obs_date)
);

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
ON CONFLICT (station_id, obs_date) DO NOTHING;

-- INDEXATION
CREATE INDEX ix_weather_measurement_station
ON weather_measurement (station_id);

CREATE INDEX ix_weather_measurement_date
ON weather_measurement (obs_date);

CREATE INDEX ix_weather_measurement_time
ON weather_measurement (time);


-- CREATION et nettoyage  WEATHER MEASUREMENT finale


-- Marque la fin de ma transaction (script)
COMMIT ;

