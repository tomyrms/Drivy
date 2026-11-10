# Boîtes de l'onglet Élèves — #447 et #449 (lot H)

Base : fusion de `ee04722f` (ca98a782). Aucune API modifiée. Impeccable et Uncodixfy lus : aucun composant ni texte décoratif ajouté,
un seul bouton texte (`.drivyText`) et les notices d'erreur existantes (`SchoolErrorNotice`).

## #447 — tous les éléments reçus sont accessibles

`SchoolPendingRequestRows` et `SchoolPendingExamRows` n'affichaient que `prefix(8)` suivi d'un texte inactif. Au-delà de huit lignes,
un bouton `SchoolBoxExpansionButton` (« Afficher les N autres » / « Réduire ») déplie la liste complète. Il est annoncé avec un libellé
et une valeur (« Liste réduite » / « Liste complète »). De zéro à huit lignes, aucun contrôle n'est présenté. Chaque ligne ouvre toujours
le dossier de l'élève par `workspace.selectLearner`, donc l'élève dont l'identifiant figure dans la ligne ; l'état déplié vit dans la vue
des lignes, qui n'est pas recréée au retour du dossier.

### Cible exacte (retour 1/2)

Une ligne ouvre la cible qu'elle porte, plus seulement l'élève : `SchoolBoxTarget` (élève, puis leçon d'une demande, ou formation et
examen d'un examen) passe par `SchoolWorkspace.open(_:)`, qui sélectionne l'élève puis retient la cible. `selectLearner` l'efface si l'on
change d'élève ; le dossier la consomme une seule fois, donc le retour garde la liste dépliée et le contexte.

- Demande : `SchoolLearnerDossierView` passe sur la section Leçons, `SchoolTrainingScreen` ouvre la fiche de `lesson.id` (feuille
  existante `OpenedLesson`) quand l'écran est courant et que l'élève correspond.
- Examen : le dossier choisit la formation `exam.trainingId`, la section Progression, et défile jusqu'à l'ancre `exams-<trainingID>`.

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

- `DrivyTests/SchoolBoxesRefreshTests` (sélection `reactivity`) :
  - fermetures génériques conservées : zéro à huit sans expansion, 9 et 20 accessibles dans l'ordre, ajouts et retraits, panne
    partielle, accès perdu purgé, nouveau contexte vidé, réponses tardives ignorées, signal de traitement ;
  - vrais clients derrière un `SchoolHTTPTransport` synthétique (`BoxServer`, acteur qui retient une requête puis la libère) :
    `SchoolLessonChangeClient.inbox` purge la boîte sur 401, 403 et 404 et la garde sur 503 ; `SchoolExamClient.list` purge sur 403 ;
    une réponse d'inbox retenue qui arrive après un changement d'école ne remplace pas l'école courante ; une réponse d'examens retenue
    qui arrive après la perte des droits (client absent) laisse la boîte vide. Pas de permutation équivalente multipliée.
- `DrivyUITests/SchoolBoxesUITests` :
  - écrans `learners-boxes-9` et `-20` : demandes ET examens ; la neuvième ligne n'existe qu'après dépliage ; la dernière ligne ouvre sa
    cible (fiche de la leçon portant la demande ; examen `...0153` de sa formation) ; le retour retrouve la liste dépliée ;
  - écran `learners-boxes-refresh` (`SchoolBoxesScriptTransport`, DEBUG simulateur) : le tirage retire une demande et en ajoute une
    dixième, la boîte des examens échoue à cette lecture (lecture précédente gardée, `pending-exams-retry`, boîte des demandes sans
    erreur), Réessayer relit et l'erreur disparaît ;
  - refus confirmé dans la fiche de la leçon : la demande a disparu de la boîte au retour, sans tirage.
- Fixtures : la dernière ligne de chaque boîte pointe la vraie cible du dossier fictif ; les autres lignes portent des élèves, leçons et
  formations distincts (ids `1000+n`, `2000+n`, `3000+n`, `4000+n`).
- Sélecteur : `SchoolBoxesRefreshTests` est déjà dans `reactivity` (`test-selection.sh` et `test_test_selection.py`) ; les suites UI se
  choisissent par `DRIVY_IOS_UI_TEST_SUITE=SchoolBoxesUITests`.

## Contrôles réellement exécutés

- `python -m unittest scripts/ios/test_test_selection.py` : 25 exécutés, RÉUSSI.
- `git diff --check` : code 0.
- Swift : NON COMPILÉ, NON EXÉCUTÉ (poste Windows sans toolchain). Aucun résultat VoiceOver, aucune recette physique.

## Limites

- Swift n'a été ni compilé ni exécuté : tout ce qui précède est écrit mais non qualifié (compilation et exécution à faire sur CI Apple).
- Le signal de traitement est prouvé au niveau de l'interface (refus confirmé puis boîte relue sans tirage), pas par un test unitaire de la
  vue : seul le compteur est testé unitairement.
- Le défilement vers l'examen utilise deux attentes (0,3 s et 1,2 s) faute de signal de fin de composition de la section ; à confirmer
  à l'œil et sur CI.
- Un seul élève du dossier fictif a un dossier ; les lignes autres que la dernière désignent des élèves sans dossier, donc la preuve de la
  cible après la huitième ligne repose sur la dernière ligne de chaque boîte.
- `SchoolBoxesScriptTransport` suppose une lecture initiale par boîte et un seul déclenchement du tirage ; un second déclenchement décalerait
  les lectures scriptées.
- Les tests de vrais clients simulent 401 sans renouvellement de jeton (`invalidateAccessToken` rend faux) ; le renouvellement n'est pas couvert ici.
- Aucun résultat VoiceOver ni recette physique.
