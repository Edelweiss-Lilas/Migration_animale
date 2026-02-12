-- SCRIPT : Suppression des tables temporaires de traitement de la donnée

-- Marque le début de ma transaction (début du script)
BEGIN ;

-- Toujours utiliser le même schéma. !!ATTENTION!! si vous ne le configurez pas, vous serez obligé de préciser {nom_schema}.{nom_table} pour chaque requête ! Le nom dus schéma ici doit être le même que dans le fichier .env du script python
SET search_path TO CREC;

--  
-- drop table travail PLACE 


-- drop table travail FALCON 

DROP TABLE falcon_positions_clean;
DROP TABLE selected_falcons;
DROP TABLE falcon_positions_30_downsampled;

-- 7. SUPPRESSION DES TABLES BRUTES
DROP TABLE _ebd;

-- drop table travail BIRD DETECTION 


-- drop table travail WEATHER STATION 
-- 5. SUPPRESSION DE LA TABLE TEMPORAIRE
DROP TABLE weather_daily_work;


-- 6. SUPPRESSION DES TABLES BRUTES
DROP TABLE meteo_almonte;
DROP TABLE meteo_ceuta;
DROP TABLE meteo_jerez;
DROP TABLE meteo_las_cabezas_de_san_juan;
DROP TABLE meteo_maspalomas;
DROP TABLE meteo_palencia;
DROP TABLE meteo_san_roque;
DROP TABLE meteo_tarifa;
DROP TABLE meteo_villarasa;


-- drop table  travail WEATHER MEASUREMENT 

-- Marque la fin du script
COMMIT ;

-- La base de données est désormais terminée ! Suite logique : création des vues pour leur exploitation par TABLEAU
