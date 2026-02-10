-- SCRIPT : Suppression des tables temporaires de traitement de la donnée

-- Marque le début de ma transaction (début du script)
BEGIN ;

-- Toujours utiliser le même schéma. !!ATTENTION!! si vous ne le configurez pas, vous serez obligé de préciser {nom_schema}.{nom_table} pour chaque requête ! Le nom dus schéma ici doit être le même que dans le fichier .env du script python
SET search_path TO film_fr_2026;

--  
-- drop table travail PLACE 


-- drop table travail FALCON 


-- drop table travail BIRD DETECTION 


-- drop table travail WEATHER STATION 


-- drop table  travail WEATHER MEASUREMENT 

-- Marque la fin du script
COMMIT ;

-- La base de données est désormais terminée ! Suite logique : création des vues pour leur exploitation par TABLEAU
