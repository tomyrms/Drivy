# Progression iOS — #206, #215, #216, #217, #218

29 octobre 2026. Branche `codex/ios-progression-206-218`, base `master` `c94ec2bb`.

Les cinq issues sont ouvertes ; leurs corps et commentaires ont été relus (aucun commentaire). La recherche de PR par numéro ne retourne aucun résultat ; les références Git disponibles ne montrent aucun autre correctif portant ces numéros. Le chemin courant est `SchoolHomeView.learnerTab(.progress)` → `SchoolTrainingScreen` → `SchoolTrainingProgressSection`, également réutilisée dans le dossier du moniteur. Les constats ci-dessous viennent du code de cette base, pas d’un écran ancien.

| Issue | Avant | Modification |
|---|---|---|
| #206 | L’attente de dossier/formation de Progression annonce « Tes leçons ». | La section paramètre le même composant d’attente. Progression nomme son contenu et l’ouverture attendue du dossier ou de la formation. Contact, actualisation, erreurs et école inactive restent dans leurs branches existantes. |
| #215 | Recherche absente ; groupes indépendants/non vus repliés. | Champ Drivy local, recherche insensible à casse/accents sur les libellés autorisés de la formation courante. Les trois groupes sont parcourus sans les déplier manuellement ; formation et compte des résultats sont affichés. Un référentiel incomplet est annoncé et ne produit aucun libellé inventé. |
| #216 | Un seul UUID de détail ouvert. | Ensemble d’UUID ; plusieurs évaluations ou définitions restent ouvertes. Retour aux groupes avec les détails choisis conservés, purge des identifiants retirés et remise à zéro lors du changement de formation ou retrait d’accès. |
| #217 | `observedAt` seulement dans le détail. | Date également sous le libellé de chaque évaluation, avec le formateur et le fuseau scolaire existants ; VoiceOver la lit. Date illisible : « Date indisponible ». Une compétence non vue n’obtient aucune date. |
| #218 | Compétences non vues non interactives. | La description existante du référentiel se déplie lorsqu’elle est non vide, avec sa source et le permis. Sans description, la ligne reste simple. Aucune observation ou écriture n’est déclenchée. |

## Sources et décisions

- Conception : `COMMENCER_ICI.md`, règles R17–R20, AP58 et schémas OpenAPI `Progress`, `ProgressItem`, `Competency`. `observedAt`, `sourceLessonId` et `description` sont déjà présents ; aucun contrat supplémentaire.
- Scénarios : T031/T032 et T072/T073 pour la date métier, la correction et le retrait d’une observation ; isolation des formations. La projection serveur et ses niveaux restent intacts. Les décisions du 28 septembre 2026 priment pour le partage automatique.
- `SchoolProgressReading` ne reçoit que la projection et le référentiel déjà chargés par le workspace autorisé. Les références hors des UUID de la projection sont exclues des résultats. En cas de référence absente, le libellé de l’évaluation sert de repli pour les seules évaluations connues ; les UUID non vus sans libellé restent absents et la couverture incomplète est explicite.
- La synthèse et la dernière leçon restent affichées pendant la recherche. Le champ garde sa place avant les groupes ; effacer restaure leurs choix de repli, sauf lorsqu’un groupe doit rester ouvert pour montrer un détail choisi dans les résultats. La saisie et les replis sont en mémoire de vue uniquement.
- Téléphone et iPad : détails empilés verticalement sous leur ligne, sans tableau ni comparaison entre formations. À grande taille de texte, la ligne adopte son empilement existant ; textes et définitions n’ont pas de limite de lignes. L’iPad conserve l’organisation existante du dossier, sans ajouter de colonne étroite de comparaison.
- Le changement de formation remplace déjà le sous-arbre par `.id(trainingID)`. La vue retire les contenus sans rôle pédagogique ou avec accès révoqué/invalidé ; la suppression de projection réinitialise la recherche et les détails. La décision d’accès et les requêtes restent au workspace/serveur.

## Vérification et limites

`git diff --check` exécuté sans erreur. Relecture des appels, du contrat, des états d’accès et des fixtures effectuée. Aucun test, build, push ou déploiement exécuté dans ce lot. Aucune qualification physique, VoiceOver ou de position de défilement revendiquée. La compilation et l’IPA seront celles du lot d’intégration final demandé par le porteur, puis les tests après son retour.

Préparés sans exécution : sept tests `SchoolProgressReadingTests` (trois groupes, accents/casse, libellé canonique, isolation des UUID, référentiel incomplet, retour à l’ordre initial, description vide et date/fuseau) et un test `SchoolProgressReadingUITests` sur les fixtures existantes (date avant ouverture, recherche puis deux détails persistants, définition et repli indépendant).

## Recette sur l’IPA finale

1. Élève sans dossier, puis sans formation : comparer Leçons et Progression, contact/actualisation ; ouvrir le dossier et la formation sur un autre appareil, puis actualiser. Contrôler aussi école inactive et erreur réseau, sans les confondre avec une formation sans évaluation.
2. Sur une progression autorisée, rechercher un libellé avec/sans accent, dans chacun des trois groupes ; vérifier formation, compte et absence de résultat. Le résumé global et les niveaux ne changent pas. Chercher un libellé d’un autre permis ne le rend pas accessible.
3. Ouvrir deux détails, rechercher une troisième compétence, effacer avec la croix puis en supprimant la saisie. Les détails choisis restent ouverts et le champ ne saute pas au début de page ; un repli volontaire ne ferme que sa ligne. Vérifier clavier et retour de leçon.
4. Vérifier la date avant ouverture et dans le détail, notamment près de minuit dans le fuseau scolaire ; actualiser ne la change pas. Contrôler une compétence non vue, une définition longue et une description vide, sans changement du niveau ni de la projection.
5. Simuler lecture du référentiel en panne et référentiel partiel : erreur de reprise/couverture visible, aucun résultat fictif ni définition de substitution. Retirer l’accès ou changer de formation : les détails hors contexte disparaissent.
6. iPhone/iPad, portrait/paysage, grandes tailles et VoiceOver : ordre de lecture libellé/niveau/date/état déplié, contrôle de repli, définition complète et accès à la leçon source. Les vérifications automatisées préparées restent à exécuter après validation utilisateur.
