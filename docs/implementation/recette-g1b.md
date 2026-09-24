# Recette de configuration scolaire sur appareil

Le build 0.3.0 contient G1A et G1B. Les essais ci-dessous complètent les tests serveur et simulateurs ; aucun résultat physique n'est déduit de leur réussite. Les identifiants restent dans le fichier d'accès privé fourni sur le PC.

## Connexion et préparation

1. Installer l'IPA avec iLoader en conservant le même identifiant d'application. Ouvrir Drivy, choisir la connexion scolaire et se connecter avec le compte initial. Au premier accès, choisir son propre mot de passe dans le navigateur système, puis vérifier le retour dans l'app.
2. Ouvrir « Luc auto école ». Une école DRAFT doit afficher sa préparation. Le bouton de configuration doit être disponible pour l'ADMIN ; aucun élève ou agenda d'exemple ne doit apparaître.
3. Ouvrir « Préparer mon école ». Vérifier les coordonnées puis enregistrer une correction après la confirmation. Fermer et rouvrir la configuration : la correction doit être relue depuis le serveur.
4. Saisir des textes d'essai explicitement reconnaissables dans « Information des personnes » et « Conservation des données ». Relire la feuille de confirmation, puis annuler une première fois : aucune adoption ne doit être annoncée. Recommencer et adopter volontairement ces textes. La version doit être indiquée comme adoptée. Pour cet environnement d'essai, n'utiliser aucune donnée réelle d'élève.
5. Vérifier la préparation puis confirmer l'activation de l'école. L'espace doit s'ouvrir sans ajouter de dossiers. Fermer et relancer l'app : le statut actif doit être relu depuis le serveur. Ne pas créer une seconde école pour répéter cette recette ; relever plutôt le résultat et la version de l'app.

## Réseau, relance et droits

- Avant d'enregistrer des coordonnées, couper le réseau. Une demande dont le résultat est incertain reste conservée, avec sa référence. Fermer puis rouvrir l'app et rétablir le réseau : vérifier le résultat ou renvoyer la même demande. Une seule modification doit être confirmée. Un 404 de recherche d'opération ne doit jamais être interprété comme une annulation.
- Si une demande attend une réponse, fermer la configuration. Une réponse tardive peut résoudre la demande conservée, mais ne doit pas rouvrir l'écran ni restaurer les anciens champs après déconnexion.
- Sur deux appareils, afficher la même version de l'école puis enregistrer une correction depuis le premier. La nouvelle commande du second doit demander une actualisation et une nouvelle confirmation en cas de conflit ; elle ne doit pas écraser silencieusement la correction.
- Les essais de changement d'appartenance, perte du Trousseau, fichier chiffré altéré et droits révoqués sont couverts de façon synthétique par les tests. Ne pas modifier les accès de l'unique administrateur hébergé pour les simuler manuellement.

## Affichage et relevé

Vérifier les champs, feuilles de confirmation, messages d'attente et boutons sur iPhone et iPad, en apparence claire puis sombre, avec une taille de texte agrandie et VoiceOver. Le clavier doit laisser accéder aux actions. Les textes de données sont consultables avant adoption ; aucun accord ne doit être précoché.

Consigner le build, modèle/version iOS, scénario, résultat observé et défaut éventuel. Ne jamais joindre mot de passe, jeton, URL de retour OAuth, donnée d'élève ou trace de localisation au dépôt public. Cette recette valide seulement l'accès et la configuration scolaire ; le GPS, l'autonomie, les leçons scolaires et les bilans publiés suivent leurs propres preuves.
