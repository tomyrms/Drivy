# Cinq échecs métier Apple (#106/#131) — correction native, lot R6

Correction de logique et de tests, **sans exécution Swift** : ce poste est Windows, sans Swift ni Xcode. Aucun
GREEN natif n'est revendiqué ici. Le RED est celui du run `41861281984` au SHA de base ; la qualification Apple
est une étape séparée, sur le vrai candidat.

## 0. Cadre

| Élément | Valeur |
|---|---|
| Modèle | `opencode-go/deepseek-v4.1-flash` (aucun variant/effort choisi) ; révision 1017 et effort **non exposés** par le runtime, non inventés |
| Skills Superpowers chargés | `systematic-debugging`, `test-driven-development`, `verification-before-completion`, `requesting-code-review` — chargés via l'outil `skill` dans cette session ; critères de revue appliqués **sans sous-agent**, conformément à la consigne |
| MCP Codebase Memory | projet unique `drivy-r6-rouges-131-20261104`, racine absolue `C:/Users/jtoma/orca/workspaces/Drivy/issues-rouges-metier-131`, mode `moderate`, `status: ready`, 38 992 nœuds / 166 828 arêtes, `indexed_at 2026-11-04T17:31:28Z` (indexé sur la base `883581ad`, avant les modifications locales ; les recherches sont structurelles, le source a été relu sur disque après édition) |
| Couverture MCP | les 8 fichiers du lot : `no_recorded_issue`, `metadata_match` ; `parse_partial` sur 5 fichiers **hors périmètre** ; `openapi.yaml` non analysable ; `.claude`, assets, migrations, scripts et fixtures exclus par ignore |
| SHA de base | `883581ad321b67ae3b7efe15ef2c6b89970b1e20` (HEAD initial du worktree, identique au `headSha` du run) |
| Branche | `tomyrms/issues-rouges-metier-131` (branche de travail du worktree) |
| Commit de code et tests | `8271c20624df3fde35569b74a3a86331b6b1809a` |
| Run de référence | job 126683437419 « Tests métier iPhone · all » : 1415 cas, 1409 passés, 6 échoués (dont les 5 du lot ; le relais est un autre lot, non touché) |
| Limite locale | aucune compilation, aucun test Swift, aucune preuve visuelle. Le seul code exécuté ici est un **port Python jetable** de la table de décision de `blocksQueueEntry` (§7), qui ne prouve rien du client Swift |

## 1. Synthèse

| Cas | Rouge observé | Cause établie sur le source | Correction |
|---|---|---|---|
| A | `SchoolCommandScopes106Tests/anInvitationAndAProfileRecordDoNotShareAVersion` | `blocksQueueEntry` sérialise `updateProfile` et `saveOnboarding` (tous deux `.school`), alors que l'API vérifie deux lignes distinctes | exception limitée à cette paire, dans les deux ordres, après les gardes de portée |
| B1 | `SchoolLessonHubTests/aRefusedPermitReviewKeepsTheLessonAndFallsBackToTheWrittenReason` | le refus définitif retire la commande mais ne recalcule pas `blockingCommand` ; `canMutate` exige `blockingCommand == nil` depuis `f1833925` | relecture de la barrière après retrait réussi, derrière la garde de génération |
| B2 | `SchoolLessonLifecycleTests/laterGPSDepartureAlsoWaitsForSavedObjectives` | même verrou, même chemin (`422 INVALID_REQUEST` → `.rejected` → refus définitif) | le même correctif, aucun second correctif |
| C | `SchoolLiveObservationRecorderTests/lateConfirmationRefreshesTheNoGPSWorkspaceAfterItsSheetClosed` | `canMutate` a perdu `pending == nil` dans `ae9fff26` ; `canAdd` n'a plus de porte stricte pendant l'envoi d'un signalement posé ici | `canAdd` exige `pending == nil` ; `acceptsAdd` et `liveSendInFlight` inchangés |
| D | `SchoolTrainingRefreshTests/receiptOfAnotherLessonNeverBroadcastsTheOpenLessonAsItsTarget` | `f1833925` a restreint `pending` aux commandes de l'écran : plus aucune notification n'est émise | attente du test mise au contrat actuel (zéro notification), renforcée par la conservation exacte de la commande étrangère |

## 2. Cas A — dossier administratif et enregistrement d'accueil

**Cause, relue au source.** `save` refuse toute commande dont une entrée conservée satisfait `blocksQueueEntry`
(`SchoolCommandOutbox.swift:404`). `conflicts(with:)` renvoie vrai pour deux commandes `.school`
(`SchoolCommandScheduling.swift:9`), et l'exception invitation ↔ dossier (`SchoolCommandOutbox.swift:346-347`,
introduite par `ae9fff26`) ne couvre pas la paire `updateProfile`/`saveOnboarding`. La troisième écriture du test
rouge est donc refusée par la file.

**Contrat réel de l'API** (`apps/api/src/profiles.ts`, lu sur disque) :

- `UPDATE_ADMINISTRATIVE_PROFILE` : `checkVersion(row.version)` sur `drivy.learner_profile` (`:127`), puis écrit
  `drivy.person` (`:148`) et `drivy.learner_profile` (`:152`).
- `SAVE_ONBOARDING` : `checkVersion(row.version)` sur `drivy.onboarding_progress` de `(school, membership, kind)`
  (`:266`), puis écrit cette même ligne (`:277-278`). Aucune lecture de `learner_profile`.
- `COMPLETE_ONBOARDING` : avant d'écrire, appelle `progressDTO` (`:268`), qui pour un accueil `STUDENT` relit
  `drivy.learner_profile` et calcule les champs manquants (`:167-173`). **La finalisation dépend donc du dossier.**

**Correction** (`SchoolCommandOutbox.swift`, après l'exception invitation) : retour `false` uniquement pour
`(updateProfile, saveOnboarding)` et `(saveOnboarding, updateProfile)`, commentaire citant les lignes ci-dessus et
l'exclusion de `completeOnboarding`.

**Conservé tel quel** : deux dossiers (même deux élèves), deux enregistrements d'accueil, deux finalisations,
politique de champ, invitations, même intention (`id`), autre portée/époque/adhésion, empreinte d'enseignement
inconnue. Aucune granularité nouvelle entre deux apprenants.

**Tests.**
- `anInvitationAndAProfileRecordDoNotShareAVersion` : **inchangé** (toujours 3 entrées) ; c'est le rouge A.
- Nouveau `aProfileRecordAndAnOnboardingSaveCoexistInEitherOrder` : ordre inverse, et relecture du coffre chiffré
  (la règle desserrée doit aussi passer la validation d'archive en version 3).
- Nouveau `theProfileAndOnboardingExceptionStopsAtCompletionAndAtTheSameRecord` : `updateProfile`→`completeOnboarding`
  et l'inverse, deux `saveOnboarding`, `saveOnboarding`→`completeOnboarding`, deux `updateProfile`, politique de
  champ→`saveOnboarding`.
- Nouveau `theProfileAndOnboardingExceptionKeepsTheAccessBarrier` : autre époque, autre adhésion.

## 3. Cas B — refus définitif et verrou de la fiche

**Cause, relue au source.** `prepare` pose `pending` **et** `blockingCommand` (`SchoolLessonReportWorkspace.swift:1158-1160`).
Sur un refus définitif, `transmit` retire la commande (`:1213`), puis écrit `pending = nil; absentPendingID = nil;
needsReload = …` (`:1225`) sans relire `blockingCommand`. Or `canMutate` exige `blockingCommand == nil` (`:129`).
`git show f1833925` confirme le remplacement de `pending == nil` par `blockingCommand == nil` dans `canMutate`,
sans ajout de relecture sur ce chemin : c'est la régression.

**Correction** : `rereadBlockingCommand()` après le retrait réussi et la garde de génération (`:1224`), avant la
branche `notFound`. `rereadQueue` (`:660-671`) relit la file réelle et recalcule `pending` **et** `blockingCommand` :
une autre commande réellement bloquante garde la fiche fermée, le verrou n'est jamais effacé à l'aveugle.

**Préservé** : `leftWhileClosureIsSent` (retour avant la relecture), l'échec de stockage au retrait (retour immédiat,
`storageAccessible = false`), refus d'accès/contexte (les guards `canMutate`/`isAuthor` sont intacts), résultat
inconnu (`operationUnknown` reste un chemin de vérification, pas un refus), idempotence (`retryPending` inchangé),
texte saisi et objectifs avant départ GPS (aucune écriture de saisie touchée), `needsReload` pour `conflict`/`notFound`.

**Tests.**
- `aRefusedPermitReviewKeepsTheLessonAndFallsBackToTheWrittenReason` et
  `laterGPSDepartureAlsoWaitsForSavedObjectives` : **inchangés**, ce sont les rouges B.
- Nouveau fichier `SchoolNativeRegression131Tests.swift` (justifié : ces cas exigent une file à plusieurs entrées et
  un retrait qui échoue, que `ConfigurationOutboxStub` ne sait pas représenter) :
  - `aRefusedPermitReviewKeepsTheRemainingBlockingCommand` : une commande `completeLesson` de la même leçon entre
    dans la file au moment du retrait ; la fiche reste fermée (`blockingCommand` non nul, `!canMutate`), la commande
    étrangère est conservée.
  - `aRefusedPermitReviewWhoseRemovalFailsKeepsTheLockAndTheCommand` : le coffre refuse le retrait ; la commande
    reste, `pending` et `blockingCommand` la désignent encore, `!canMutate`, message de stockage.

  Le premier cas injecte la commande restante dans le double au moment du retrait (simulation d'un autre écran) ;
  c'est un double de test, pas un écrivain concurrent réel. Le second couvre le chemin « stockage refusé » qui
  n'était couvert par aucun test existant : aucun test ne lit `blockingCommand` et aucun ne provoque un échec de
  `remove` sur la file de cette fiche.

## 4. Cas C — `canAdd` pendant l'envoi d'un signalement

**Cause, relue au source et à l'historique.** `4cb4cee3` a introduit `acceptsChanges`/`acceptsAdd`,
`pendingAwaitsReview` et `liveSendInFlight`, en **laissant** `canMutate` avec `pending == nil`. C'est `ae9fff26`
qui a remplacé cette clause par `blockingCommand == nil` (`git show ae9fff26`), et `blockingCommand` reste nul pour
deux créations de signalement de la même leçon (`queuesWithObservation`, `SchoolCommandScheduling.swift:190-193`) :
`canAdd` est donc redevenu vrai alors qu'une commande de cette leçon est encore en vol.

**Écart assumé avec le pseudocode du diagnostic.** `!pendingAwaitsReview` **ne suffit pas** pour ce rouge : dans le
test, le POST est suspendu par `DelayedLiveObservationTransport`, et l'enregistreur garde
`isSettlingGesture = true` pendant tout l'envoi (`startSending(afterGesture: true)`, puis `drain` ne remet les
drapeaux à faux qu'après la réponse, `SchoolCaptureLiveObservations.swift:348-375`). `liveSendInFlight` est donc
vrai, `pendingAwaitsReview` est faux, et la porte proposée par le diagnostic laisserait `canAdd` vrai. La porte
stricte retenue est `pending == nil`, ce qui restaure exactement la sémantique d'écriture d'avant `ae9fff26` sans
toucher à la présentation.

**Correction** (`SchoolObservationWorkspace.swift:81-87`) : `guard canMutate, pending == nil, let lesson,
observations.count < 100`. `acceptsChanges`/`acceptsAdd` et `liveSendInFlight` sont inchangés ; les conditions de
statut de leçon, de publication, de capacité 100 et d'accès/stockage sont conservées.

**Autres usages de `canAdd` confirmés** : contrairement à l'affirmation du diagnostic, `canAdd` **a** un appelant de
production, `save(_:text:marker:competencyID:themeKey:status:)` (`:252`), en plus des tests (`SchoolLessonHubTests`
489/494/497/509, `SchoolLiveObservationRecorderTests` 145/151/172, `SchoolObservationRefusalTests` 68). Le
graphique MCP ne résout pas cet accès de propriété (0 appelant entrant) : la lecture du source fait foi.
Conséquence assumée : une feuille ouverte pendant l'envoi bref d'un signalement de la même leçon sera refusée à
l'enregistrement — même motif déjà accepté pendant une relecture (`begin` suit `acceptsAdd`, `save` suit `canMutate`).
La palette « Signaler » (`liveRecorder`, `acceptsAdd`) reste, elle, ouverte pendant l'envoi, par conception.

**Tests** : le rouge C (`lateConfirmationRefreshesTheNoGPSWorkspaceAfterItsSheetClosed`) est **inchangé**. Aucun
changement de vue, aucun test UI : un vert simulé ne serait pas une correction visuelle observée.

## 5. Cas D — reçu d'une autre leçon

**Cause.** `f1833925` a introduit `belongsToThisScreen` (`:675-688`) et `pending = queued.first { … }` : un
`.saveReportDraft` d'un autre brouillon n'est plus la demande de l'écran. `verifyPending` sort au `guard let pending`
(`:1115`) et n'appelle plus `announceConfirmedChange`. Le produit est plus strict ; seul le test datait de `9c77dd64`.

**Correction** (`SchoolTrainingRefreshTests.swift`, cas inchangé dans son nom) : l'attente devient
`changes.count == 0 && changes.values.isEmpty`, plus `!reportSaveConfirmed && pending == nil`, plus
`outbox.removals.isEmpty && outbox.value == foreign` où `foreign` est la commande exacte enregistrée (même
identifiant, même corps, même portée, même ressource). Aucune notification globale vide n'est recréée. Les tests
positifs de confirmation de la bonne leçon (`lessonChangeIsBroadcastOnlyAfterDurableConfirmation`) gardent leurs
assertions : une notification, la bonne cible.

## 6. Tests à exécuter sur runner Apple (étape séparée, non lancée ici)

| Suite | Cas |
|---|---|
| `SchoolCommandScopes106Tests` | `anInvitationAndAProfileRecordDoNotShareAVersion` (rouge A), `aProfileRecordAndAnOnboardingSaveCoexistInEitherOrder`, `theProfileAndOnboardingExceptionStopsAtCompletionAndAtTheSameRecord`, `theProfileAndOnboardingExceptionKeepsTheAccessBarrier`, `aProfilePolicyStillBlocksAnInvitation`, `twoDistinctInvitationsCoexistAndTheSameInvitationStaysSequential`, `theDossierIsEditableExactlyWhenTheQueueAcceptsItsProfile`, `observationsAreOfferedExactlyWhenTheQueueAcceptsThem` |
| `SchoolLessonHubTests` | `aRefusedPermitReviewKeepsTheLessonAndFallsBackToTheWrittenReason` (rouge B1), `seeingThePermitRecordsItThenReloadsWithoutLosingTypedText`, `aRereadKeepsTheObservationListAndItsActionsInPlace`, `onlyARequestLeftWaitingIsShownAndLocksTheObservations`, `changedServerPreparationDoesNotEraseOrSilentlyRebaseLocalEdits`, `failedObjectivesSavePreventsStartingAndKeepsTheDraft`, `anUnstartedLessonCannotSendCompletion` |
| `SchoolLessonLifecycleTests` | `laterGPSDepartureAlsoWaitsForSavedObjectives` (rouge B2), `startingPersistsTheCommandThenRereadsTheSameLessonAndCanFinish`, `startingSavesObjectivesBeforeStartingTheLesson`, `invalidObjectivesCannotBeDiscardedByStarting` |
| `SchoolLiveObservationRecorderTests` | `lateConfirmationRefreshesTheNoGPSWorkspaceAfterItsSheetClosed` (rouge C), `lateConfirmationCannotReopenAnInvalidatedObservationWorkspace`, `theSendThatFollowsAGestureNeverDelaysTheNextGesture` |
| `SchoolTrainingRefreshTests` | `receiptOfAnotherLessonNeverBroadcastsTheOpenLessonAsItsTarget` (rouge D, attente corrigée), `lessonChangeIsBroadcastOnlyAfterDurableConfirmation` |
| `SchoolNativeRegression131Tests` (nouveau) | `aRefusedPermitReviewKeepsTheRemainingBlockingCommand`, `aRefusedPermitReviewWhoseRemovalFailsKeepsTheLockAndTheCommand` |
| Suites à ne pas casser | `SchoolPendingRequestResolutionTests`, `SchoolObservationRefusalTests`, `SchoolLessonClosureReactivityTests`, `SchoolProfileWorkspaceTests`, `SchoolOnboardingDraftTests`, `SchoolObservationCorrectionTests`, `SchoolCommandScopes106Tests` (tâche 4), l'ensemble des 1415 cas du run |

Le fichier `SchoolNativeRegression131Tests.swift` est pris par la cible `DrivyTests` sans modification du projet
(`apps/ios/project.yml:74-77`, `sources: [DrivyTests]`).

## 7. Vérifications réellement exécutées (Windows) et codes

| Commande | Résultat | Exit |
|---|---|---|
| `git rev-parse HEAD` (avant travaux) | `883581ad321b67ae3b7efe15ef2c6b89970b1e20` | 0 |
| `git show f1833925 -- …SchoolLessonReportWorkspace.swift` | `canMutate` : `pending == nil` → `blockingCommand == nil` ; ajout de `belongsToThisScreen` | 0 |
| `git show 4cb4cee3^:…SchoolObservationWorkspace.swift` | `canMutate` contenait encore `pending == nil` avant `4cb4cee3` | 0 |
| `git show ae9fff26 -- …SchoolObservationWorkspace.swift` | `canMutate` : `pending == nil` → `blockingCommand == nil` (origine du rouge C) | 0 |
| `git log -S "belongsToThisScreen"` / `-S "isProfileRecord"` | `f1833925` / `ae9fff26` | 0 |
| MCP `index_repository` (async) puis `status` | `succeeded`, 38 992 nœuds / 166 828 arêtes | 0 |
| MCP `index_status`, `check_index_coverage` (8 fichiers) | `ready`, `metadata_match`, `no_recorded_issue` | 0 |
| MCP `search_graph` : `blocksQueueEntry`, `canAdd`, `rereadQueue`, `belongsToThisScreen`, `announceConfirmedChange`, `recordPermitSeen`, `transmit` | nœuds et fichiers attendus ; `canAdd` : 0 appelant entrant (limite du graphe sur les accès de propriété) | 0 |
| MCP `trace_path` entrants : `canAdd`, `rereadQueue`, `blocksQueueEntry` | `rereadQueue` ← `load`, `transmit`, `verifyPending`, `abandonPending`, `rereadBlockingCommand` ; `blocksQueueEntry` ← `refusing`, `save`, `read`, `remove` | 0 |
| `python artifacts/native-131/check-admission-131.py` | port jetable de la seule table de décision : 12/12 cas conformes aux attentes écrites (**pas** un test Swift, ne prouve aucun comportement du client) | 0 |
| `git diff --check` | aucun défaut d'espace | 0 |
| `git commit` | `8271c20624df3fde35569b74a3a86331b6b1809a` | 0 |

Aucune commande `swift`, `xcodebuild`, `xcodegen` ou `npm test` n'a été lancée : elle n'existe pas sur ce poste.

## 8. Risques, limites, écarts

1. **Aucune compilation ni exécution Swift** : le code et les tests sont relus statiquement. Les cinq rouges ne sont
   pas déclarés verts. Une qualification Apple sur le vrai candidat reste nécessaire.
2. **Écart assumé sur C** : `pending == nil` au lieu de `!pendingAwaitsReview`, parce que `liveSendInFlight` est vrai
   dans l'état exact du rouge (§4). Le pseudocode du diagnostic n'aurait pas rendu ce cas vert.
3. **Origine du rouge C corrigée par rapport au diagnostic** : `ae9fff26`, pas `4cb4cee3` (qui a seulement introduit
   la séparation de présentation).
4. **`canAdd` a un appelant de production** (`save`, `:252`), contrairement à ce qu'affirmait le diagnostic. Le
   resserrement y est volontaire ; une saisie ouverte pendant l'envoi bref d'un signalement de la même leçon sera
   refusée à l'enregistrement, comme elle l'est déjà pendant une relecture. Aucun test ne couvre ce chemin de
   feuille ; il n'est pas qualifié visuellement.
5. **Cas B non-régression** : la commande restante est injectée par le double au moment du retrait. Le scénario réel
   (un autre écran écrit entre la lecture et le retrait) n'est pas rejoué en concurrence.
6. **Dérive documentaire** : `docs/implementation/registre-commandes-106.md` (§ « Paires desserrées ») ne liste pas
   encore la paire `updateProfile`/`saveOnboarding`. Ce fichier n'est pas dans le périmètre autorisé de ce lot ; il
   reste à mettre à jour par le lot qui tient le registre.
7. **Aucune nouvelle granularité entre deux apprenants** : deux dossiers restent séquentiels, comme demandé.
8. **Relais rouge (cas 1) non touché** : autre lot, aucun fichier, script ou workflow de relais modifié.
9. **Portée respectée** : seuls les trois fichiers produit autorisés, les quatre fichiers de tests autorisés et le
   nouveau `SchoolNativeRegression131Tests.swift` sont modifiés. Aucune vue, aucun contrat API/SQL, aucun DTO, aucune
   dépendance, aucun projet Xcode, aucun workflow, aucun `STATUS.md`, aucune issue, aucun push/PR/CI/déploiement.
10. **Corrections** : une passe de correction, aucune reprise corrective consommée (plafond de 2 non entamé).
