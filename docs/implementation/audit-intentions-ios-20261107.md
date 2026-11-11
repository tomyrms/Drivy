# Audit des intentions natives iOS — lot E (#427, #431, #438)

Date : 2026-11-07. Base : f1eb696a (lot B livré, preuves B acquises sur 3d213e7c, non retouchées).
**Statut d'exécution : NON COMPILÉ, NON EXÉCUTÉ.** Cette machine est Windows, sans chaîne Swift ni simulateur. Rien ci-dessous
n'est une preuve d'exécution : ce sont des critères, le code qui les porte et les tests écrits pour les qualifier sur un runner Apple.
Les seuls contrôles exécutés ici sont ceux de la sélection de tests (voir « Contrôles exécutés »).

## #427 — barrière libérée après le retrait durable d'un refus corrigeable

Constat : la relecture de la barrière après un refus existait déjà (commit 8271c206, `SchoolLessonReportWorkspace`). Le lot la durcit
sur les deux sorties qui ne la relisaient pas :

- `abandonPending()` relit `blockingCommand` après avoir retiré la demande et avant `load()` ;
- `transmit`, branche « départ pendant l'envoi de la clôture » : après `rememberRefusedClosure`, la barrière est relue tant que l'accès
  n'est pas invalidé.

Critères : (1) la barrière tombe quand le retrait durable du refus réussit ; (2) une autre barrière réelle reste en place (la relecture
lit le coffre, elle ne le vide pas) ; (3) un retrait qui échoue garde le verrou et la commande, sans annoncer de suppression ;
(4) une panne réseau n'est pas un refus définitif ; (5) l'accès restauré ne change pas l'identité de la commande.

Tests existants qui les couvrent : `SchoolNativeRegression131Tests` (`aRefusedPermitReviewKeepsTheRemainingBlockingCommand`,
`aRefusedPermitReviewWhoseRemovalFailsKeepsTheLockAndTheCommand`), `SchoolLessonHubTests.aRefusedPermitReviewKeepsTheLessonAndFallsBackToTheWrittenReason`,
`SchoolLessonLifecycleTests.laterGPSDepartureAlsoWaitsForSavedObjectives`. Aucun test neuf : le durcissement n'a pas de scénario
distinct observable avec les doublures actuelles. Limite : deux de ces suites n'étaient pas dans le périmètre `reports` ; elles y sont ajoutées.

## #438 — remplacement et migration d'époque en une seule écriture atomique

Cause : `replace` et la migration d'époque faisaient retrait puis ajout, soit deux écritures du coffre ; une panne entre les deux
laissait ni l'ancien ni le nouveau.

Correctif : `EncryptedSchoolCommandOutbox.replace(_:with:refusing:)` lit, retire l'ancien (égalité exacte exigée), évalue l'admission
sur les commandes du même espace, ajoute le nouveau, puis fait **une seule** écriture (`.atomic`, `.completeFileProtection`). Les
autres commandes sont réécrites telles quelles. `EncryptedSchoolCourseIntentStore.replace` et la migration d'époque de `commands(scope:)`
passent par cette fonction ; la migration traite une commande par écriture, donc chaque commande est entière à l'ancienne ou à la
nouvelle époque à chaque frontière. Deux pannes injectables (`faultBeforeFileWrite`, `faultAfterFileWrite`) servent aux tests ;
elles n'ont aucun effet quand elles sont nulles.

Tests (`SchoolIntentExactnessTests`, coffre chiffré réel, dossier temporaire, relecture par une nouvelle instance) :
panne avant écriture → ancien et autres intacts ; panne après écriture → nouveau présent, ancien parti, jamais aucun ; une écriture
par remplacement ; migration d'époque en panne (première puis seconde écriture) → aucune intention perdue ni dupliquée, identités
d'opération conservées ; remplacement d'une intention absente → refus, rien ne change.

Limite : l'atomicité du système de fichiers (`write(.atomic)`) est supposée, pas testée ; une coupure de courant réelle n'est pas simulée.

## #431 — rejeu exact d'une édition de cours incertaine

Cause : la clé d'opération incluait la version courante de la série. Après relance, la série relue (version supérieure) donnait une
autre clé, donc une nouvelle opération avec le nouveau `If-Match` : l'édition déjà appliquée n'était pas rapprochée et la version
courante était adoptée en silence.

Correctif :

- `SchoolCourseEditorRecord` conserve `baseVersion` (version envoyée dans `If-Match`) et `seriesBody` (corps canonique parti) ;
  `canReplayExactly` dit si l'enveloppe est complète. `SchoolCourseSeriesBody` devient `Codable` (encodage inchangé).
- L'éditeur garde l'enveloppe envoyée (`sent`), en mémoire et dans le coffre. Tant que la saisie est inchangée, `writeDraft` et `publish`
  rejouent exactement corps, version et opération, même si la série relue est plus récente. L'école rejoue la réponse d'une opération
  déjà appliquée avant tout contrôle de version : le reçu est rapproché sans seconde mutation.
- Un 412 VERSION_CONFLICT sur rejeu exact, ou une archive incomplète (d'avant ce lot), **bloque** (`replayHold`) : saisie et entrée de
  coffre conservées, `canSave`, `canPublish` et « Réessayer » inactifs, message explicite. Rien ne repart sur la version courante.
  « Abandonner » relit le cours à jour et jette la saisie explicitement.
- Saisie modifiée par la personne : nouvelle opération, comportement inchangé. Les créations ne sont pas concernées (pas de version).

Tests (`SchoolIntentExactnessTests`) : rejeu après relance avec série v4 (même clé, même `If-Match` "3", même corps, une seule mutation,
coffre vidé) ; rejeu refusé 412 (saisie préservée, aucun renvoi par Réessayer/Enregistrer/Publier, abandon relit v4) ; archive ancienne
incomplète (blocage, aucune écriture) ; publication perdue rejouée avec sa version d'origine ; `canReplayExactly` et aller-retour du record.

Limites : le serveur simulé reproduit le rejeu-avant-version décrit dans l'API, il ne le prouve pas ; l'affichage du blocage dans
`SchoolCourseEditorView` (bouton Réessayer désactivé) n'a pas été vu à l'écran.

## Sélection exacte de tests (runner Apple)

- `unit_test_scope=agenda` : ajout de `SchoolIntentExactnessTests` (#431, #438) en plus de `SchoolCourseIntentPersistenceTests`.
- `unit_test_scope=reports` : ajout de `SchoolLessonLifecycleTests` et `SchoolNativeRegression131Tests` (#427).
- À lancer aussi pour la non-régression de l'outbox : `unit_test_scope=reactivity` (contient `SchoolCommandOutboxTests`).

## Contrôles exécutés

- `python -m unittest scripts/ios/test_test_selection.py` : 25 tests, OK (sélection seulement, pas de Swift).
- Aucune compilation Swift, aucun test métier, aucun test UI, aucun contrôle VoiceOver ou appareil.

## Reste à qualifier

Compilation et exécution des trois suites ci-dessus sur le runner Apple ; vérification visuelle du blocage de reprise dans l'éditeur de
cours ; confirmation côté `apps/api` du rejeu avant contrôle de version pour `PUT course-series` et `POST publish`.

## Raccord Swift du lot A (#423, #439, #444) — API 2878e141

NON COMPILÉ, NON EXÉCUTÉ (poste Windows). Lecture de `git show 2878e141` et du code natif existant :

| Issue | Constat côté iOS | Décision |
|---|---|---|
| #423 cours | `COURSE_INSTRUCTOR_CLOSED` (409) à la publication : absent de `SchoolCourseClient.failure`, il retombait sur le message générique. | Message français ajouté ; refus définitif, brouillon et saisie conservés (`fail` ne vide que l'opération). |
| #423 examen | `EXAM_ESCORT_CONFLICT` pouvait être un congé, le message disait « rendez-vous » seulement. | Message : « Le moniteur est absent ou a déjà un rendez-vous pendant l'accompagnement. Choisis un autre créneau ou un autre moniteur. » |
| #439 | `COURSE_POSITIONS_MISMATCH` : la replanification de cours n'existe pas dans l'app (aucun appel client, aucune vue). | Aucun mapping ajouté (code inatteignable) ; traité par le bureau web. |
| #444 | `canManage` vient de `exam_manage` (droit pédagogique, indépendant de l'état de la formation). La section reste visible et le menu Actions (modifier, reporter) ne dépend que du statut de l'examen. | Aucun changement de gate : un examen futur reste corrigeable après pause, fin, annulation ou archivage. |

Mise à jour (§ 5) : « Prévoir » n'est plus proposé que pour une formation connue active (`SchoolExamModel.allowsCreation`) ; le serveur reste l'arbitre (`TRAINING_NOT_ACTIVE`, message traduit). Cette ligne remplace l'ancienne limite « Prévoir non masqué ».

Tests ajoutés : `SchoolExamTests` (`anEscortRefusedForALeaveIsNotCalledAnAppointment`, `aFutureExamStaysManageableWhateverTheTrainingBecame`), `SchoolCourseClientTests` (mapping `COURSE_INSTRUCTOR_CLOSED`). Sélection : `SchoolExamTests` et `SchoolIntentExactnessTests` ne figurent que dans `unit_test_scope=agenda` (`scripts/ios/test-selection.sh`) ; `reports` et `reactivity` ne les exécutent pas.

## Retour correctif groupé 1/2 (sur 7a4d70b4, budget E1/2 pour #431 et #438)

**NON COMPILÉ, NON EXÉCUTÉ** (poste Windows, aucune CI lancée). Les 25 tests de la sélection restent applicables : la sélection
(`agenda`, `reports`, `reactivity`) est inchangée, `SchoolIntentExactnessTests` y figure déjà.

### 1. #438 — substitution périmée refusée, idempotence conservée

`replace(old, with: new)` n'ajoutait plus rien d'utile quand `old` était absent : le retrait était sauté puis `new` ajouté, contrairement
à `replacingAnIntentNotInTheVaultFailsAndChangesNothing`. Règle, identique dans le coffre chiffré
(`EncryptedSchoolCommandOutbox.replace`) et le coffre mémoire (`SchoolCourseIntentMemoryStore.replace`) :

- `old` présent : égalité exacte exigée, retrait et ajout en une seule écriture atomique (inchangé) ;
- `old` absent **et** `new` absent : refus (`SchoolConfigurationFailure.storage`), rien n'est écrit ;
- `old` absent mais `new` déjà là **à l'identique** (faute après écriture, rejeu) : réussite sans changement ;
- `new` de même identité mais de contenu différent : refus.

L'admission (`refusing:`) reste évaluée avant l'écriture. Test : `aStaleReplacementIsRefusedByBothStoresButAnExactNewIntentStaysIdempotent`
(les deux coffres, autres intentions préservées). `replacingAnIntentNotInTheVaultFailsAndChangesNothing` n'est pas modifié.

### 2. #431 — reprise d'une demande bloquée : comparer, puis décider

Avant : message « saisie conservée », champs et actions figés, seule sortie « Abandonner » (jette la saisie). Maintenant, dans
`SchoolCourseEditorWorkspace` et `SchoolCourseEditorView` :

- **Comparer avec la version à jour** (`compareHeldInput`) : relit le cours, ne change ni `series`, ni la saisie, ni le coffre, ne
  renvoie rien. Produit une `SchoolCourseReconciliation` : champs qui diffèrent entre la saisie conservée et la version relue
  (`SchoolCourseForm.differences`). Pour une ancienne archive sans base, **aucune modification n'est supposée** : on compare deux états,
  on ne dit pas qui a changé quoi.
- **Enregistrer ma saisie sur la version à jour** (`keepMyInputOnCurrentVersion`, seulement après la comparaison, cours encore brouillon,
  droit de gestion) : nouvelle opération (nouvel identifiant) sur la version relue ; la demande bloquée est **remplacée en une seule
  écriture du coffre** (`replace(kept, with:)`), jamais rejouée, `If-Match` = version relue affichée. Un nouveau conflit suit la voie
  normale (refus, aucune avance silencieuse). La publication reste un geste séparé.
- **Abandonner ma saisie** (ancien « Abandonner la demande ») reste la sortie destructive, distincte, avec son annonce.
- `load()` ne remplace plus saisie et série tant qu'une demande est en attente (`pending == nil`).
- Messages de blocage : renvoient à la comparaison, plus à « abandonne ».

Tests unitaires (`SchoolIntentExactnessTests`) : `aBlockedEditIsComparedThenKeptOnTheReadVersionAsANewOperation` (comparaison sans écriture,
puis une écriture `If-Match "4"`, autre clé, une mutation de plus, coffre vidé), `keepingMineIsRefusedWithoutAComparisonAndNeverAdvancesTheVersionOnItsOwn`,
`anOldArchiveWithoutBaseIsComparedWithoutInventingItsEditsThenKeptOnPurpose`, `abandoningABlockedEditStaysDistinctAndDiscardsOnlyAfterTheComparison`,
`theFormComparisonNamesOnlyTheFieldsThatDiffer`.

Scénario UI ciblé, harnais actuel (`SchoolCourseVisualReview`, écran `course-editor-held`, coffre mémoire, transport synthétique) :
`SchoolCourseJourneyUITests/testBlockedCourseEditIsComparedThenKeptOnPurpose` — archive ancienne bloquée à l'ouverture, « Réessayer »
inactif, témoin à 0 mutation ; Comparer → ligne `course-reconcile-Titre` ; toujours 0 mutation ; Enregistrer ma saisie → une seule
mutation (`PUT`, `If-Match "2"`, titre saisi) ; plus de demande en attente. Sélection : `ui_test_suite="SchoolCourseJourneyUITests/testBlockedCourseEditIsComparedThenKeptOnPurpose"`.

**Oracle du double (qualification)** : `SchoolCourseClient` réencode avec `JSONEncoder` à chaque appel ; l'ancien `CourseReplayServer`
décidait son reçu par égalité d'octets, sans `If-Match`. Il décide maintenant sur `canonical({body, expectedVersion})` (clés triées,
version tirée de `If-Match`) comme `commands.ts`, et refuse 409 `IDEMPOTENCY_CONFLICT` une même clé avec une autre identité. Les
tests comparent `identity` (version, opération, champs) et vérifient `operationId`, `title`, `If-Match`, donc une modification
effective n'est pas masquée. **Confirmation de source (lecture, pas une exécution API)** : `schoolCommand` vérifie les droits puis le
reçu/hash avant `work` et `checkVersion` ; `PUT course-series` et `publish` passent par ce chemin ; `courses.integration` couvre le
rejeu de `publish`. Aucun test API relancé ici.

### 3. Abandon bloqué par le coffre

`clearPending()` vidait `pending/sent/kept` puis ignorait l'erreur de `remove` (`try?`) ; `abandonUnconfirmed` annonçait alors
« Demande abandonnée » et remplaçait la saisie. Maintenant `clearPending()` rend un booléen et ne touche **rien** si le retrait
durable échoue (référence `kept`, saisie, blocage conservés). Conséquences :

- `abandonUnconfirmed` : relecture du cours, puis retrait ; en cas d'échec, message `removalFailedMessage`, aucune annonce de retrait,
  aucun remplacement de saisie, aucun envoi. Les autres intentions du coffre ne sont pas touchées (`remove` ne retire que la sienne).
- Un reçu de l'école n'est pas une suppression locale : brouillon, publication et création de type mémorisent la réponse acquise
  (`series`, catalogue) mais, si le coffre refuse le retrait, la feuille ne se ferme pas, la demande reste « à reprendre » ; « Réessayer »
  rejoue la même enveloppe, l'école rend son reçu, puis le retrait est retenté. Un refus définitif de l'école suit la même règle.

Tests (coffre chiffré réel, panne via `faultBeforeFileWrite`) : `anAbandonThatTheVaultCannotRecordKeepsTheReferenceTheInputAndEveryOtherIntent`,
`anUnblockedAbandonThatTheVaultCannotRecordIsNotAnnouncedEither`, `aServerReceiptIsNotALocalRemoval`.

### 4. Raccord Swift du lot A (#423, #439, #444) — constat

Livré dans 823f4410, redit ici : `COURSE_INSTRUCTOR_CLOSED` traduit (`SchoolCourseClient.failure`, test `SchoolCourseClientTests`) ;
`EXAM_ESCORT_CONFLICT` n'est plus décrit comme un simple rendez-vous (absence **ou** rendez-vous, `SchoolExamClient`, test
`anEscortRefusedForALeaveIsNotCalledAnAppointment`) ; `COURSE_POSITIONS_MISMATCH` : aucun appel de replanification n'existe dans
`SchoolCourseClient` ni dans les vues (recherche `reschedule` vide), donc **pas de delta nécessaire**, code traité par le bureau web.
Examens existants après clôture de formation : le menu Actions de `SchoolExamsUI` ne dépend que de `canManage` (droit pédagogique) et du
statut de l'examen ; l'API accepte `UPDATE_EXAM`/`POSTPONE_EXAM` (`existingTraining`). La création reste limitée : « Prévoir » exige
`canManage` et une épreuve planifiable, le serveur refuse hors formation active (`TRAINING_NOT_ACTIVE`, message traduit). Aucune
administration ajoutée à l'app. (Le masquage préventif de « Prévoir » est livré depuis : voir § 5.)

### Contrôles exécutés

Aucun Swift compilé ni exécuté, aucune CI, aucun test API. Relecture de code et de la source `commands.ts` seulement.

### 5. Raccord #444 — création d'examen conditionnée à la formation active

**NON COMPILÉ, NON EXÉCUTÉ.** `SchoolTrainingExamsSection` lit `SchoolTrainingWorkspace.training?.status` via
`SchoolExamModel.allowsCreation(trainingStatus:)` (vrai seulement pour `"ACTIVE"` ; statut inconnu ou autre = fermé).

- « Prévoir » et l'invite de prochaine étape ne sont proposés que si la formation est connue active.
- Une feuille de création déjà ouverte reçoit `creationOpen` : si le statut devient inactif, le bouton d'envoi est désactivé et
  une note d'erreur l'explique. Les feuilles de modification, report et résultat ne sont pas touchées.
- La gestion des examens existants (modifier, reporter, résultat) est inchangée. Aucune nouvelle API ; le serveur reste l'arbitre
  (`TRAINING_NOT_ACTIVE`).
- Test ajouté : `SchoolExamTests/schedulingIsOnlyOfferedForAKnownActiveTraining`, exécuté par `unit_test_scope=agenda` seulement
  (`reports` et `reactivity` ne contiennent pas `SchoolExamTests`).
- **Scénario UI : non écrit.** Aucun harnais visuel d'examens n'existe (aucune référence à `exams-schedule` dans les UITests) ; en créer
  un dépasse « minimal ». À décider par le coordinateur.
- **Impeccable et Uncodixfy** : cherchés d'abord au mauvais endroit, ils existent bien (`~/.codex/skills/impeccable`, `uncodixfy`) ;
  lus au retour 2/2 (§ 6). Le changement n'ajoute aucun composant, seulement une condition et une note d'erreur existante
  (`DrivyActionNote`). Rendu jamais vu tourner.

## Retour correctif groupé 2/2 (sur d4cfc1f5)

**NON COMPILÉ, NON EXÉCUTÉ** : aucun Swift n'a été compilé ni lancé ici, aucune CI. Les tests ci-dessous sont écrits, pas passés.
Sélection inchangée : `unit_test_scope=agenda` (seule à contenir `SchoolIntentExactnessTests` et `SchoolExamTests`) ; `reports` et
`reactivity` restent à lancer pour le reste du lot mais n'exécutent pas ces suites. Scénario UI de reprise
(`SchoolCourseJourneyUITests/testBlockedCourseEditIsComparedThenKeptOnPurpose`) conservé tel quel ; aucun scénario UI d'examen
(limite d'exécution conservée).

### 1. #431 — l'abandon verrouille l'éditeur de bout en bout

`abandonUnconfirmed` ne mettait jamais `isBusy`. Pendant sa relecture suspendue, « Enregistrer ma saisie » pouvait remplacer `kept`, puis la
réponse tardive de l'abandon retirait la NOUVELLE intention. Maintenant : `isBusy` est levé avant la lecture et tenu jusqu'au retrait
(comparer, garder, réessayer, publier, enregistrer et un second abandon sont refusés par leurs gardes). Le travail est dans
`abandonLocked`, qui capture `kept` et l'opération au départ et ne retire que si les deux sont inchangés. Annulation ou erreur de
lecture : retour sans rien changer (message de relecture pour l'erreur), `isBusy` relâché dans tous les cas. La relecture de l'agenda
(`load`) part après le déverrouillage.
Tests : `aSuspendedAbandonLocksEveryOtherGestureAndRemovesOnlyItsOwnIntent` (lecture suspendue du serveur simulé dans le vrai
workspace et le coffre chiffré : aucun envoi, aucun retrait pendant l'attente, l'autre intention intacte, puis seule la sienne retirée),
`anAbandonThatFailsToReadUnlocksTheEditorAndChangesNothing`.

### 2. #431 — la comparaison se décide sur les identités

`SchoolCourseForm.differences` comparait des chaînes formatées. Elle compare désormais les valeurs métier : identifiants de type, de
responsable et de moniteur de séance, dates réelles (à la seconde), présence, puis formate en français. Deux identités de même libellé
restent une différence, marquée « (autre type) » ou « (autre compte) » du côté de la saisie ; un identifiant absent du catalogue se
lit « Type introuvable » / « Moniteur introuvable », jamais un UUID. Les valeurs envoyées et l'oracle du serveur simulé ne changent pas.
Test : `twoDistinctIdentitiesWithTheSameLabelAreStillADifferenceWithoutRawIdentifiers` (responsable, type, moniteur de séance, deux comptes
introuvables, aucune différence quand rien ne change). Limite : deux séances à la même minute mais à des secondes différentes sont
une différence réelle dont les deux lignes affichées sont identiques.
Impeccable et Uncodixfy lus : aucune surface nouvelle, mêmes lignes `course-reconcile-*` ; seul le texte de comparaison change, sans
badge ni note ajoutés.

### 3. #438 — l'idempotence vaut pour toute intention

`EncryptedSchoolCommandOutbox.replace` et le coffre mémoire passaient `new` elle-même à l'admission : une intention de l'élève
(`courseLearnerIntent`) déjà écrite se bloquait sur la même série. Désormais seule la commande EXACTEMENT identique à `new` est
exclue de l'admission ; une commande de même identifiant et de contenu différent, ou toute autre intention, garde son refus.
Le coffre mémoire est réécrit sur une copie : il exige l'égalité exacte de `old` quand son identifiant existe (avant, il l'écrasait),
refuse la substitution périmée, et n'écrit qu'à la fin.
Tests (les deux coffres, intention de l'élève, faute après écriture sur le coffre chiffré réel, autre intention intacte) :
`aLearnerReplacementReplayedAfterAPostWriteFaultIsIdempotentInBothStoresButOtherIntentsStillBlock`,
`theMemoryStoreChecksTheContentOfTheOldIntentLikeTheDurableOne`.

### Contrôles exécutés

Aucun Swift compilé ni exécuté. Relecture de code seulement.

### Extension E : deux assertions qui ne compilaient pas

Run Apple 42778603013 (SHA d19e978f, job 129702904628) : l'app compile, puis la cible `DrivyTests` échoue sur
`SchoolIntentExactnessTests.swift` lignes 485 et 494 (`await` à droite de `&&` dans `#expect`). ÉCHEC de compilation ; aucun test
n'a été exécuté.

Le porteur a autorisé une extension unique après les deux retours E, limitée à ces deux assertions, suivie d'une seule relance Apple
agenda par le coordinateur. Correction de syntaxe seulement : les acteurs sont lus dans des `let` (`writesDuringHold`/`heldDuringHold`,
`writesAfter`/`mutationsAfter`) avant les mêmes `#expect`, conditions et appels métier inchangés.

Contrôle local : `git diff --check` seulement. Swift reste NON EXÉCUTÉ sur ce poste Windows ; la compilation n'est pas qualifiée.
