#h1 Extraction de données web avec Python : automatisez vos collectes 

Si vous souhaitez capturer des données à partir de nombreux sites Web, vous devrez vous adonner au web scraping, lequel permet de faire face à des données non structurées que vous pourrez choisir de rapatrier en totalité ou préférer filtrer avant d'en télécharger une sélection.

#h2 Comment fonctionne le web scraping en python ?

Certains sites web proposent des ensembles de données téléchargeables au format CSV ou accessibles via une interface de programmation d'application (API)
Une des possibilités : bibliothèque Beautiful Soup.
Pour analyser les données collecter : utiliser la bibliothèque Pandas
Rédaction : écrire une requête au serveur qui héberge la page que nous avons spécifiée.
règle générale : notre code télécharge le code source de cette page, tout comme le ferait un navigateur. Affichage : il filtre la page à la recherche des éléments HTML que nous avons spécifiés et en extrait le contenu que nous lui avons demandé d'extraire.

#h2 Pourquoi utiliser Python pour le web scraping ?

Possible de faire du web scraping avec de nombreu autres langages de programmation.
- Beautiful Soup : l'une des approches les plus populaires du web scraping. 
    bonnes pratiques d'utilisation :
    * ne récupérez jamais plus de pages que nécesaire
    * pensez à mettre en cache le contenu que vous récupérez afin qu'il ne soit téléchagé qu'une seule fois lorsque vous travaillez sur le code que vous utilisez pou le filtrer et l'analyser, plutôt que de le retélécharger chaque fois que vous exécuter votre code
    * envisagez de créer des pauses dans votre code en utilisant des fonctions telles que _time.sleep()_ pour éviter de surcharger les serveurs avec trop de requêtes dans un laps de temps trop court

#h2 La bibliothèque requests

La première chose à faire pour faire du web scraping sur une page Web est de la télécharger. Nous pouvons télécharger des pages en utilisant la bibliothèque requests. Cette dernière fera une requête _GET_ à un serveur qui téléchargera le contenu HTML d'une page Web donnée. 
télécharger à l'aide de la méthode requests.get :
    demandes d'importation 
    page = requests.get(<<http:// dataquestio.github.io/web-scraping-pages/simple.html>>) page 
    <Réponse [200]>

#h2 Analyse d'une page avec Beautiful Soup 

cas d'une page HTML :
possibilité d'utiliser la méthode prettify sur l'objet BeautifulSoup
possible d'utiliser la propriété children de soup qui renvoie un générateur de liste => appeler la fonction de liste : list(soup.children)
utiliser la méthode get_text() pour extraire tout le texte à l'intérieur de la balise.
rechercher toutes les instantces d'un tag : utiliser la méthode find_all, qui trouvera toutes les instances d'une balise sur une page.
    exemple de redaction : soup.find_all ('p') [0] .get_text()
méthode find : renverra un seul objet BeautifulSoup.
existe aussi la méthode find_all

#h1 exemple utiliser pour ce sujet : 
    #h1 télécharger des données météo à partir du site Web du National Weather Service (pas d'API):

#h2 Extraire toutes les informations de la page 

extraire le nom de l'élément de prévision, la brève description et la température, car ils sont tous similaires :
    period = tonight.find (class_= <<period-namee>>). get_text() 
    short_desc = ce soir.find(class_ = <<short-desc>>). get_text()
    temp = ce soir.find(classe_=<<temp>>).get_text()
    print(période)
    print(short_desc)
    print(temp)

pour tout extraire en même temps en combinant des sélecteurs et des listes de compréhension
Pour ce faire, nous allons appeler la classe DataFrame et transmettre dans le framework d'un dictionnnaire. Chaque clé de dictionnaire deviendra une colonne dans le DataFrame, et chaque liste deviendra les valeurs de la colonne :
import pandas as pd

meteo = pd.DtaFrame({
    <<période>> : periods,
    <<short_desc>> : short_descs,
    <<temp>> : temps,
    <<desc>> : descs
})

ensuite procéder à l'analyse des données. Par exemple, nous pouvons utiliser une expression régulière et la méthode Series.str.extract pour extraire les valeurs de température numériques comme suit :
temp_nums = weather [<<temp>>]. str.extract (<<( ? P <temp_num> d +) >>, expand = False)
weather [<< temp_num >>] = temp_nums.astype ('int')
temp_nums

Quelques bibliothèques Python utiles pour le Web Scrapin :
* requests : cette bibliothèque est nécessaire pour obtenir les données du serveur Weeb sur votre machine, et elle contient également des fonctionnalités intéressantes supplémentaires teelles que la mise en cache.
* Beautiful Soup 4 : c'est la bibliothèque que nous avons utilisée ici, et elle est conçue pour rendre le filtrage des données basé sr des balises HTML plus simple.
* lmxl : un analyseur HTML et XML rapide (et désormais intégré à Beuatiful Soup)
* Selenium : Un outil Web qui est utile lorsque vous avez besoin d'obtenir des données d'un site Web auquel la bibliothèque resquests ne peut pas accéder, lorsqu'elles sont dissimulées derrère des éléments tels que des formulaires de connexion ou des clics de souris obligatoires.
* Scrapy : un framework complet de web scraping qui peut être surdimensionné pour des projets d'analyse de données ponctuels, mais qui convient pour les projets de production, les pipelines, etc.