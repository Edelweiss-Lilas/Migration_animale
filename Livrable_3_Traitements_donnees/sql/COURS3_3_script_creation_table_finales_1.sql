-- Marque le début de ma transaction (début du script)
BEGIN ;

-- Toujours utiliser le même schéma. !!ATTENTION!! si vous ne le configurez pas, vous serez obligé de préciser {nom_schema}.{nom_table} pour chaque requête ! Le nom dus schéma ici doit être le même que dans le fichier .env du script python
SET search_path TO CREC;


-- CREATION et nettoyage PLACE finale


-- CREATION et nettoyage FALCON finale


-- CREATION et nettoyage BIRD DETECTION finale


-- CREATION et nettoyage WEATHER STATION finale


-- CREATION et nettoyage  WEATHER MEASUREMENT finale


-- Marque la fin de ma transaction (script)
COMMIT ;

