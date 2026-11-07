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
