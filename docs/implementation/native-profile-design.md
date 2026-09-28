# Profil et champs demandés

## Périmètre

Présentation native de `SchoolProfileView` et `SchoolProfilePolicyView`, sans changement de workspace, de contrat ni de validation. Références relues : E40, E48, R97, R99, R100, AP169–AP176 et les scénarios T173, T179, T189. La charte UI/UX AS03–AS07 guide la densité, les mots et les états difficiles.

## Profil

L’école destinataire précède les champs. Les libellés restent visibles pendant la saisie ; les finalités viennent toujours de la politique chargée. Les erreurs de format se placent près du champ en réutilisant la validation existante, sans troncature de noms ni règle d’âge ajoutée.

L’enregistrement reste accessible en bas du formulaire, avec confirmation explicite et état d’écriture. Une erreur de sauvegarde apparaît aussi près de ce geste. La fermeture reste bloquée pendant l’envoi ; les changements non enregistrés conservent leur confirmation d’abandon. Une ancienne confirmation de sauvegarde n’est plus affichée quand le formulaire a de nouvelles modifications.

## Règles de l’école

Les versions affichent date d’effet et statut ; leurs règles se déplient. La version applicable vient du workspace, sans nouveau calcul dans la vue. L’éditeur sépare date et heure, garde une explication persistante pour chaque champ et indique pourquoi la création est indisponible.

Créer un brouillon et publier restent deux gestes distincts. La relecture affiche la notice exacte liée à cette version avant la publication. Les erreurs, la vérification d’un résultat incertain et le renvoi de la demande conservée restent dans la feuille. Une actualisation relit la version courante avant de réactiver sa publication. Une version effectivement publiée ferme la relecture ; un brouillon confirmé après vérification ferme son éditeur.

Les surfaces de commande ont une largeur de lecture bornée sur iPad ; les formulaires et textes suivent les tailles système. Le clavier peut se retirer avec le défilement.

## Limites et preuve

Relecture ciblée et `git diff --check` seulement pour ce lot ; compilation Apple groupée et rendu natif restent à confirmer. Aucune qualification VoiceOver, clavier externe ou appareil physique n’est revendiquée.

Deux limites existantes restent visibles pour l’intégration : la photo est un état de dossier, son dépôt requiert encore le parcours document ; le menu de reprise d’arrivée enregistre une étape, mais l’écran ne constitue pas encore un assistant à étapes courtes. Aucun bouton de dépôt ni navigation fictive n’a été ajouté pour les masquer.
