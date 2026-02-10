-- Marque le début de ma transaction
BEGIN;

-- Toujours utiliser le même schéma. !!ATTENTION!! si vous ne le configurez pas, vous serez obligé de préciser {nom_schema}.{nom_table} pour chaque requête ! Le nom dus schéma ici doit être le même que dans le fichier .env du script python
SET search_path TO CREC;

-- CREATION et nettoyage PLACE 


-- CREATION et nettoyage FALCON 


-- CREATION et nettoyage BIRD DETECTION 


-- CREATION et nettoyage WEATHER STATION 


-- CREATION et nettoyage  WEATHER MEASUREMENT 


-- Marque la fin de ma transaction (et donc de mon script)
COMMIT ;
