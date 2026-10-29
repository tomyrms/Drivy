# Fraîcheur de progression — #117

29 octobre 2026, base `2d9a5f64`. La lecture parallèle existait (`d4da07b3`, PR #189), mais sa date était confondue avec celle des leçons et n’était pas visible.

`SchoolTrainingWorkspace` date maintenant la lecture réussie de la progression et de son référentiel ensemble. Une réponse ancienne/annulée ne rafraîchit pas cette date ; une panne garde la projection et sa date, un refus retire les deux. Le rendu indique l’actualisation en cours ou la date de lecture dans le fuseau scolaire. Aucun niveau ni compteur optimiste ajouté. Une erreur de référentiel ne remplace plus une projection complète par une lecture incomplète.

Matrice native au SHA de base :

| Capacité | État réel |
| --- | --- |
| Niveaux, compétence, source/date, dernier bilan évalué, multi-permis | Présents, projection serveur `trainings/{id}/progress`, lecture uniquement. |
| Contrôle du permis d’élève | Présent : `recordPermitCheck`, AP30, attendu après reçu ; aucune permission déduite d’un indicateur local. |
| Détail du permis/formation, pièces et vérification | Présents dans `SchoolLearnerPermitDetail` et dossier ; aucune nouvelle validation ajoutée. |
| Planification administrative d’une prestation d’examen | Parcours de planning existant ; un tarif `EXAM_SUPPORT` ne produit ni résultat ni certificat. |
| Module natif de résultats/examen officiel/certificat | Non livré comme module autonome ; hors périmètre de cette issue. |

Références relues : R20 (projection), R07 (contrôle humain), API du parcours bilan/progression, scénario T073 et règles de partage automatique du 28 septembre. Pas de modification du canon.

Contrôles : `git diff --check` exécuté. Scénario `failedProgressRefreshKeepsTheLastReadUntilAccessIsRefused` enrichi pour date conservée, purge, fin de chargement et reprise. Tests et compilation Apple **NOT_EXECUTED** ici, réservés au coordinateur. Recette IPA : ouvrir deux permis, retarder puis interrompre une actualisation, vérifier date conservée et erreur, révoquer l’accès puis réautoriser ; aucun bilan non confirmé ne doit apparaître dans les niveaux. Aucune qualification physique revendiquée.

Ni web/EPIC #311, ni service, ni déploiement, ni fusion.
