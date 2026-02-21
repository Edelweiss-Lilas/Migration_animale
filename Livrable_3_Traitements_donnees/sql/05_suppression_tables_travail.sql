-- ============================================================
-- 05_cleanup.sql
-- Objectif :
--  - Nettoyer la base : supprimer les tables temporaires (staging) et les tables brutes (CSV)
--  - Conserver uniquement :
--      * les tables finales : place, falcon, bird_detection, weather_station, weather_measurement
--      * les vues dataviz : v_dataviz..., v_weather_measurement, etc.
--
-- CASCADE supprime aussi ce qui dépend des tables (ex : contraintes, vues liées, etc.)
-- ============================================================

BEGIN;
SET search_path TO CREC;

-- ----------------------------
-- TABLES DE TRAVAIL : PLACE (staging)
-- ----------------------------
-- Ces tables ne servent qu'au script 01 et au chargement dans place (script 02)
-- Une fois place créée et remplie, on peut les supprimer
DROP TABLE IF EXISTS city CASCADE;
DROP TABLE IF EXISTS communes_global CASCADE;
DROP TABLE IF EXISTS espacesvert_complet CASCADE;
DROP TABLE IF EXISTS espacesvert CASCADE;
DROP TABLE IF EXISTS parc CASCADE;
DROP TABLE IF EXISTS "POLYGONES_PARC" CASCADE;
drop table IF EXISTS polygones_parc CASCADE;
drop table IF EXISTS polygones_city CASCADE; 
DROP TABLE IF EXISTS space_complet CASCADE;
DROP TABLE IF EXISTS falcon_city2 CASCADE;
-- ----------------------------
-- TABLES DE TRAVAIL : FALCON (staging)
-- ----------------------------
-- Tables intermédiaires pour nettoyer + filtrer + downsample
-- Les données utiles sont déjà dans falcon et bird_detection
DROP TABLE IF EXISTS falcon_positions_clean CASCADE;
DROP TABLE IF EXISTS selected_falcons CASCADE;
DROP TABLE IF EXISTS falcon_positions_30_downsampled CASCADE;

-- ----------------------------
-- TABLE BRUTE : FALCON
-- ----------------------------
-- Table CSV importée brute (kestrel34)
-- On la supprime après transformation en tables finales
DROP TABLE IF EXISTS kestrel34 CASCADE;

-- ----------------------------
-- TABLES DE TRAVAIL : WEATHER (staging)
-- ----------------------------
-- Table météo unifiée "propre" utilisée pour remplir weather_station + weather_measurement
DROP TABLE IF EXISTS weather_daily_work CASCADE;

-- ----------------------------
-- TABLES BRUTES : WEATHER (CSV importés)
-- ----------------------------
-- Chaque station a sa table brute ; elles ne sont plus nécessaires après la pipeline
DROP TABLE IF EXISTS meteo_almonte CASCADE;
DROP TABLE IF EXISTS meteo_ceuta CASCADE;
DROP TABLE IF EXISTS meteo_jerez CASCADE;
DROP TABLE IF EXISTS meteo_las_cabezas_de_san_juan CASCADE;
DROP TABLE IF EXISTS meteo_maspalomas CASCADE;
DROP TABLE IF EXISTS meteo_palencia CASCADE;
DROP TABLE IF EXISTS meteo_san_roque CASCADE;
DROP TABLE IF EXISTS meteo_tarifa CASCADE;
DROP TABLE IF EXISTS meteo_villarasa CASCADE;

COMMIT;
