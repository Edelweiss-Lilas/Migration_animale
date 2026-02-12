-- Marque le début de ma transaction (début du script)
BEGIN ;

-- Toujours utiliser le même schéma. !!ATTENTION!! si vous ne le configurez pas, vous serez obligé de préciser {nom_schema}.{nom_table} pour chaque requête ! Le nom dus schéma ici doit être le même que dans le fichier .env du script python
SET search_path TO CREC;


-- Mise à jour des foreign keys 


-- update Bird detection / place id + falcon id 



-- update weather station / place id


-- update weather measurement / station id

-- Marque la fin de ma transaction (fin du script)
COMMIT ;
