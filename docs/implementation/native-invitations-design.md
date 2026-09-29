# Invitations et entrée dans l’école

## Périmètre

Vues d’invitation et d’entrée dans l’école. Références : E02, E16, J20–J22, R98, scénarios T175 et T190 ; extension actuelle [trajets et codes](api-trajets-codes.md). Les liens historiques restent acceptés ; aucun transport e-mail n’est ajouté.

## Codes élèves — reprise du 29 septembre 2026

L’action **Inviter un élève** ouvre directement les permis (1 à 16 offres) et, pour un administrateur, le moniteur actif. Une seule offre ou un seul moniteur est présélectionné ; un administrateur qui enseigne retrouve sa propre affectation. Le moniteur sans rôle ADMIN s’affecte lui-même. **Créer le code** enregistre une seule invitation `trainings`, puis montre le code à copier ou partager avec la feuille iOS. Les formations seront créées ou retrouvées à l’acceptation. Une erreur de chargement des options propose Réessayer et ne prétend plus qu’aucune formation n’existe.

Le code reste en mémoire seulement. Le corps de la commande de création est conservé dans l’outbox chiffrée avant envoi. Si une réponse perdue est confirmée par reçu, le code secret n’est pas reconstitué : **Nouveau code** renouvelle l’invitation existante et invalide le précédent. La liste ne conserve jamais le code.

Les tests Swift couvrent la sélection multiple, l’affectation ADMIN/moniteur, le défaut issu du contexte, le chargement impossible et la reprise d’une réponse sans code. Leur exécution Apple est suivie dans `STATUS.md`.

## Rejoindre

La page présente directement le lien, puis le nom d’école, les rôles, l’adresse masquée et la notice. Les grands blocs d’accueil et de félicitations sont retirés. Les textes de notice restent complets et sélectionnables, la conservation se déplie, la prise de connaissance reste un choix manuel.

Une commande principale en bas suit l’état réel : consulter, accepter, vérifier la confirmation ou ouvrir l’école après relecture des accès. Ses conditions sont celles du workspace. Une erreur sur la demande reste visible près de cette commande ; la demande incertaine garde sa référence et son renvoi à l’identique. Le champ du lien reste protégé et n’est pas exposé dans un résumé.

## Gérer les invitations

La liste utilise les couleurs natives de sélection ; elle ne force plus du texte blanc sans garantir son fond. Les états restent textuels. La fiche présente adresse masquée, rôles et échéance, sans panneau décoratif. Une invitation révoquée ne propose plus dans son explication un renvoi inaccessible.

La création du code utilise les choix visibles sans feuille de confirmation supplémentaire. La feuille reste ouverte pendant l’écriture, puis présente Copier et Partager. Une erreur, l’actualisation requise et la vérification d’une demande incertaine s’effectuent sur place. Les invitations par e-mail existantes restent lisibles ; leur renvoi conserve son erreur explicite si aucun transport n’est configuré.

La révocation conserve son motif et sa confirmation destructrice distincte. Une réponse incertaine expose les mêmes commandes de vérification sur cet écran. Les fermetures sont désactivées pendant l’envoi ; aucun accord ni rôle n’est ajouté automatiquement par la présentation.

## Preuve

La revue du 29 septembre a compilé les vues natives et inspecté le résultat du code à partager sur iPhone et iPad, en clair et en sombre, avec des données fictives. Les tests et versions livrées sont suivis dans [STATUS.md](STATUS.md). Ces captures ne qualifient pas la connexion OIDC ni l’appairage sur appareil physique.
