# Invitations et entrée dans l’école

## Périmètre

Vues `SchoolJoinView` et `SchoolInvitationsView` seulement. Références : E02, E16, J20–J22, R98, scénarios T175 et T190 ; types et gardes des deux workspaces relus. Aucun contrat, rôle, stockage ou traitement du lien n’est modifié.

## Rejoindre

La page présente directement le lien, puis le nom d’école, les rôles, l’adresse masquée et la notice. Les grands blocs d’accueil et de félicitations sont retirés. Les textes de notice restent complets et sélectionnables, la conservation se déplie, la prise de connaissance reste un choix manuel.

Une commande principale en bas suit l’état réel : consulter, accepter, vérifier la confirmation ou ouvrir l’école après relecture des accès. Ses conditions sont celles du workspace. Une erreur sur la demande reste visible près de cette commande ; la demande incertaine garde sa référence et son renvoi à l’identique. Le champ du lien reste protégé et n’est pas exposé dans un résumé.

## Gérer les invitations

La liste utilise les couleurs natives de sélection ; elle ne force plus du texte blanc sans garantir son fond. Les états restent textuels. La fiche présente adresse masquée, rôles et échéance, sans panneau décoratif. Une invitation révoquée ne propose plus dans son explication un renvoi inaccessible.

La création garde une relecture portant les valeurs exactes. Cette feuille reste ouverte pendant l’écriture ; une erreur, l’actualisation requise et la vérification d’une demande incertaine s’effectuent sur place. Elle se ferme après confirmation durable, y compris après vérification ou renvoi de la demande conservée. La création ne prétend toujours pas que l’e-mail a été reçu.

La révocation conserve son motif et sa confirmation destructrice distincte. Une réponse incertaine expose les mêmes commandes de vérification sur cet écran. Les fermetures sont désactivées pendant l’envoi ; aucun accord ni rôle n’est ajouté automatiquement par la présentation.

## Preuve

Relecture du diff et `git diff --check` effectués. Compilation Apple groupée à confirmer, sans nouvelle campagne de tests. Les captures iPad catalogue/dossier/bilan précédentes ne qualifient pas ces deux écrans ; aucun rendu Join/Invitations ni résultat physique n’est revendiqué ici.
