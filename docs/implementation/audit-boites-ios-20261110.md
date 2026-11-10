# Boîtes de l'onglet Élèves — #447 et #449 (lot H)

Base : fusion de `ee04722f` (ca98a782). Aucune API modifiée. Impeccable et Uncodixfy lus : aucun composant ni texte décoratif ajouté,
un seul bouton texte (`.drivyText`) et les notices d'erreur existantes (`SchoolErrorNotice`).

## #447 — tous les éléments reçus sont accessibles

`SchoolPendingRequestRows` et `SchoolPendingExamRows` n'affichaient que `prefix(8)` suivi d'un texte inactif. Au-delà de huit lignes,
un bouton `SchoolBoxExpansionButton` (« Afficher les N autres » / « Réduire ») déplie la liste complète. Il est annoncé avec un libellé
et une valeur (« Liste réduite » / « Liste complète »). De zéro à huit lignes, aucun contrôle n'est présenté. Chaque ligne ouvre toujours
le dossier de l'élève par `workspace.selectLearner`, donc l'élève dont l'identifiant figure dans la ligne ; l'état déplié vit dans la vue
des lignes, qui n'est pas recréée au retour du dossier.

Limite : l'ouverture mène au dossier de l'élève, où la leçon ou la formation porte la demande ou l'examen. Aucun lien direct vers la leçon
n'a été ajouté.

## #449 — l'actualisation relit les trois lectures

- `SchoolBoxReading<Item>` (un modèle générique, `SchoolLessonRequestInboxModel` et `SchoolPendingExamsModel` en sont des alias) :
  - le contexte nomme compte, école, adhésion, époque d'accès, rôles et droits (`examKey` de la vue) ; un changement de contexte vide la
    lecture avant toute réponse ;
  - chaque lecture porte un numéro ; une réponse plus ancienne, ou d'un autre contexte, est ignorée, succès comme échec ;
  - une panne garde la dernière lecture et pose `errorMessage` ; un `forbidden`, `notFound` ou `unauthorized` purge la lecture ;
  - une lecture sans client (droits perdus) vide la boîte.
- `SchoolBrowserView.refreshable` lance en parallèle annuaire, demandes et examens ; une section en panne n'arrête pas les autres.
- Chaque boîte en panne affiche `SchoolErrorNotice` avec Réessayer (`pending-requests-retry`, `pending-exams-retry`) qui ne relit que
  cette boîte.
- `SchoolBoxesSignal` : un compteur incrémenté à la confirmation d'un traitement (`SchoolLessonChangeModel.send`, `SchoolExamModel.transmit`),
  observé par la vue qui relit les deux boîtes. Aucune minuterie.

## Tests ajoutés (NON COMPILÉS, NON EXÉCUTÉS)

- `DrivyTests/SchoolBoxesRefreshTests` (sélection `reactivity`) : zéro à huit sans expansion ; 9 et 20 entièrement accessibles dans l'ordre ;
  ajouts et retraits visibles à la relecture ; panne partielle (lecture précédente conservée, erreur, autre section actualisée) ; accès
  perdu purgé ; nouveau contexte vidé ; réponse tardive d'un autre contexte ignorée (succès et échec) avec lecture retenue ; réponse
  ancienne du même contexte ignorée ; signal de traitement.
- `DrivyUITests/SchoolBoxesUITests` (écrans de fixture `learners-boxes-9` et `learners-boxes-20`, données fictives en lecture seule) :
  9 et 20 demandes atteignables, ouverture du dossier, retour sur la liste dépliée ; actualisation par tirage sans erreur.
- Sélecteur : `SchoolBoxesRefreshTests` ajouté à `reactivity` dans `test-selection.sh` et `test_test_selection.py`. Les suites UI se
  choisissent par `DRIVY_IOS_UI_TEST_SUITE=SchoolBoxesUITests`.

## Contrôles réellement exécutés

- `python -m unittest scripts/ios/test_test_selection.py` : 25 exécutés, RÉUSSI.
- `git diff --check` : code 0.
- Swift : NON COMPILÉ, NON EXÉCUTÉ (poste Windows sans toolchain). Aucun résultat VoiceOver, aucune recette physique.

## Limites

- Le transport « retenu » des tests est une porte sur la lecture (fermeture), pas un `SchoolHTTPTransport` : les clients réels ne sont pas
  exercés par ces tests.
- Le harnais visuel est en lecture seule : ajout et retrait d'éléments sur un autre appareil ne sont vérifiés qu'au niveau du modèle.
- Tous les éléments de la fixture 9/20 pointent vers le même élève du dossier fictif ; la correspondance ligne → élève est portée par
  `selectLearner(item.learnerId)`, non distinguée à l'écran dans ce scénario.
