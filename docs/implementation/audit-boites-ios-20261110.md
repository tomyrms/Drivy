# Boîtes de l'onglet Élèves — #447 et #449 (lot H)

Base : fusion de `ee04722f` (ca98a782). Aucune API modifiée. Impeccable et Uncodixfy lus : aucun composant ni texte décoratif ajouté,
un seul bouton texte (`.drivyText`) et les notices d'erreur existantes (`SchoolErrorNotice`).

## #447 — tous les éléments reçus sont accessibles

`SchoolPendingRequestRows` et `SchoolPendingExamRows` n'affichaient que `prefix(8)` suivi d'un texte inactif. Au-delà de huit lignes,
un bouton `SchoolBoxExpansionButton` (« Afficher les N autres » / « Réduire ») déplie la liste complète. Il est annoncé avec un libellé
et une valeur (« Liste réduite » / « Liste complète »). De zéro à huit lignes, aucun contrôle n'est présenté. Chaque ligne ouvre toujours
le dossier de l'élève par `workspace.selectLearner`, donc l'élève dont l'identifiant figure dans la ligne ; l'état déplié vit dans la vue
des lignes, qui n'est pas recréée au retour du dossier.

### Cible exacte (retours 1/2 et 2/2)

Une ligne ouvre la cible qu'elle porte, plus seulement l'élève : `SchoolBoxTarget` (élève, puis leçon d'une demande, ou formation et
examen d'un examen) passe par `SchoolWorkspace.open(_:)`, qui sélectionne l'élève puis retient la cible. Le dossier la consomme, puis le
retour garde la liste dépliée et le contexte.

- Demande : le dossier passe sur la section Leçons, `SchoolTrainingScreen` ouvre la fiche de `lesson.id` (feuille `OpenedLesson`) quand
  l'écran est courant et que l'élève correspond, puis acquitte la cible. Parcours conservé tel quel.
- Examen (2/2) : le dossier choisit seulement la formation (`exam.trainingId`) et la section Progression. C'est
  `SchoolTrainingExamsSection` qui utilise `exam.id` : une fois ses examens lus (et relus si la section existait déjà), elle défile
  jusqu'à la ligne `.id(exam.id)` de cet examen puis acquitte la cible. **Plus aucun délai** : la résolution part des changements
  d'état (lecture terminée, liste des examens, erreur), pas d'une minuterie. Une lecture lente garde donc la cible.
- Acquittement : `SchoolWorkspace.resolveBoxTarget(_:message:)` n'agit que si la cible reçue est celle qui est en cours pour l'élève
  sélectionné. Une action tardive d'un autre contexte n'a aucun effet. `boxTarget` est purgé par `clearLearner`, `reset()` et le
  renouvellement de portée de l'école (`selectSchool` sur la même école), en plus du changement d'élève.
- Cas explicites, dits dans le dossier par une note d'erreur (`box-target-missing`), effacée à l'ouverture suivante :
  examen absent de la liste de sa formation ; formation absente du dossier (après avoir lu les pages suivantes) ; lecture des examens
  refusée ou inconnue de l'école, ou rôle sans accès pédagogique. Une panne avec Réessayer garde la cible : la reprise réussie la résout.

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
- `DrivyTests/SchoolBoxesRefreshTests`, cible (2/2) : la cible reste tant qu'elle n'est pas résolue ; une autre cible ou un autre élève
  ne l'acquitte pas ; le message est posé puis effacé à l'ouverture suivante ; changement d'élève, `selectLearner(nil)` et `reset()` la
  purgent ; une résolution tardive après `reset()` n'a aucun effet.
- `DrivyUITests/SchoolBoxesUITests` :
  - écrans `learners-boxes-9` et `-20` : demandes ET examens ; la neuvième ligne n'existe qu'après dépliage ; la dernière demande ouvre
    la fiche de la leçon (carte de demande rendue, la fixture lui sert maintenant la demande) ; pour les examens, les deux dernières
    lignes ouvrent deux examens de la même formation (153 puis 155, qui n'est pas le premier de la liste) : l'examen visé doit exister,
    être atteignable et dans le cadre du dossier **sans aucun défilement manuel** ; le retour retrouve la liste dépliée ;
  - le serveur fictif rend la première lecture des examens d'une formation avec 2 s de retard (`slowExamStateSeconds`, côté harnais) ;
  - un examen absent de sa formation (ligne `count - 2`) est dit par `box-target-missing`, sans en ouvrir un autre ;
  - écran `learners-boxes-refresh` (`SchoolBoxesScriptTransport`, DEBUG simulateur) : le tirage retire une demande et en ajoute une
    dixième, la boîte des examens échoue à cette lecture (lecture précédente gardée, `pending-exams-retry`, boîte des demandes sans
    erreur), Réessayer relit et l'erreur disparaît ;
  - refus confirmé dans la fiche de la leçon : la demande a disparu de la boîte au retour, sans tirage.
- Fixtures (2/2) : `lessonState` rend désormais la demande `pendingForStaff` pour les écrans `learners-boxes-*` (la boîte et la fiche
  disent la même chose) ; la formation des écrans de boîtes liste [théorie, échec, examen 153, examen 155] ; les lignes `count` et
  `count - 1` des examens ouvrent 155 et 153, `count - 2` un examen absent, les autres des élèves et formations sans dossier.
- Sélecteur : `SchoolBoxesRefreshTests` est déjà dans `reactivity` (`test-selection.sh` et `test_test_selection.py`) ; les suites UI se
  choisissent par `DRIVY_IOS_UI_TEST_SUITE=SchoolBoxesUITests`.

## Contrôles réellement exécutés

- `python -m unittest scripts/ios/test_test_selection.py` : 25 exécutés, RÉUSSI.
- `git diff --check` : code 0.
- Swift : NON COMPILÉ, NON EXÉCUTÉ (poste Windows sans toolchain). Aucun résultat VoiceOver, aucune recette physique.

## Limites

- Swift n'a été ni compilé ni exécuté : tout ce qui précède est écrit mais non qualifié (compilation et exécution à faire sur CI Apple).
- Le défilement vers l'examen n'a plus de délai, mais reste non vu tourner : `proxy.scrollTo` est appelé quand la lecture est terminée et
  que la ligne `.id(exam.id)` est composée ; si la composition arrivait après le changement d'état, le défilement serait manqué. Le test
  UI vérifie que l'examen est atteignable et dans le cadre du dossier, pas sa position exacte (la page peut ne pas pouvoir remonter
  l'examen plus haut, faute de contenu).
- La lecture « retenue » du test UI est un retard de 2 s du serveur fictif (processus distinct : l'app ne peut pas être pilotée pour
  libérer une lecture) ; le produit n'attend rien de fixe.
- La demande n'a qu'une cible ouvrable (la leçon planifiée) ; les examens en ont deux dans la même formation.
- Le signal de traitement est prouvé au niveau de l'interface (refus confirmé puis boîte relue sans tirage), pas par un test unitaire de la
  vue : seul le compteur est testé unitairement.
- `SchoolBoxesScriptTransport` suppose une lecture initiale par boîte et un seul déclenchement du tirage ; un second déclenchement décalerait
  les lectures scriptées. Ses compteurs passent par `NSLock.withLock` dans des fonctions synchrones (Swift 6) ; aucun verrou n'est tenu
  pendant un `await`.
- Les tests de vrais clients simulent 401 sans renouvellement de jeton (`invalidateAccessToken` rend faux) ; le renouvellement n'est pas couvert ici.
- Aucun résultat VoiceOver ni recette physique.
