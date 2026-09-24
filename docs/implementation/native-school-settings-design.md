# Catalogue et configuration natifs

## Références et périmètre

Lecture de la maquette `DESIGN/assets/application-v3-17/13_ecole_light.png`, de E39, du parcours J19, de F20 et R73–R76. Relecture du contrat `SchoolReadiness` et des scénarios T163–T166 ; aucune exécution de ces scénarios revendiquée dans ce lot.

Les vues `SchoolCatalogView` et `SchoolConfigurationView` évoluent sans changement de workspace, contrat, règles de validation ou droits. Les écrans de formation d’un élève et l’équipe restent hors de ce lot.

## Présentation

- Le catalogue utilise des lignes séparées, une hiérarchie catégorie / conditions / état, et une commande de création en tête de section. Les détails versionnés se déplient ; préparer une nouvelle version reste visible. Les anciennes révisions restent consultables.
- Le sélecteur des trois sections devient un menu avec les tailles de texte d’accessibilité. La colonne garde une largeur de lecture bornée sur iPad.
- Les coordonnées gardent des libellés visibles pendant la saisie. Une école active est présentée comme telle, sans lui redemander son activation.
- Les textes adoptés sont consultables ; leur modification s’ouvre explicitement. Aucun contenu ni consentement n’est proposé automatiquement.
- Les quatre capacités et leurs raisons viennent de `SchoolReadiness`. Elles se consultent séparément de l’activation ; les modules facultatifs ne créent pas une alerte globale.

## Confirmation et erreurs

La feuille de relecture reste ouverte pendant l’écriture. Le bouton d’adoption ou d’activation est visible en bas ; une erreur et la reprise de la demande restent dans la feuille. Fermeture après réception durable confirmée par le workspace, sans assimiler une demande en attente à un succès. Le renvoi utilise toujours la demande conservée, jamais une nouvelle opération.

Les mutations et la fermeture pendant leur envoi sont désactivées. `load()` conserve déjà les champs saisis après son chargement initial ; aucune modification de persistance n’a été ajoutée.

## Vérification

Relecture des gardes et `git diff --check` effectués. Compilation Apple groupée confiée à l’intégration ; aucun nouveau résultat de simulateur, VoiceOver ou appareil physique n’est revendiqué pour ce lot.

La compilation Release de `394d4cd` (0.7.0/build21) a ensuite réussi : elle inclut catalogue/configuration `c0f2283`. Le prolongement CatalogEditor `4cf35d8` est postérieur à ce build.

## Édition du catalogue

Le formulaire conserve ses validations et ses choix d’approbation initialement désactivés. La commande de relecture est accessible en bas. Une feuille présente les valeurs exactes, leurs références et l’effet choisi avant la confirmation manuelle : brouillon, approbation ou activation. Revenir à l’édition réinitialise cette confirmation.

Les coordonnées d’offre et références de compétence ont des libellés persistants ; les compétences sont numérotées dans leur ordre, les sources facultatives se déplient. Une nouvelle révision porte un titre distinct d’une première création. L’exigence de contenus approuvés est expliquée près du choix d’activation.

Une erreur de sauvegarde et la vérification/relance de la demande conservée restent dans la relecture. Les commandes utilisent toujours le workspace existant et sa réponse durable. Ce prolongement est relu et soumis à la même compilation Apple groupée, sans nouvelle campagne de tests.

Le bouton de relecture indisponible précise ensuite le premier champ ou contenu à corriger : référence, catégorie, durée, prix, contenu lié, compétence, motif ou période. Ces indications accompagnent les prédicats existants sans les remplacer.
