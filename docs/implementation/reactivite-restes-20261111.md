# Restes de réactivité #106 / #131 / #105 — état au 11 novembre 2026

Branche `tomyrms/restes-reactivite-20261111`, partie de `origin/master` `ff79607a`. Rien n'est déployé, aucune issue n'est
fermée ni commentée, aucune PR n'est ouverte. Les mesures citées sont étiquetées par leur environnement ; aucune n'a été
prise sur appareil physique.

## 1. Ce qui a été livré

- `apps/web/client/pending-wait.ts` et son usage dans `portal/runtime/pending-requests.tsx` : seuils d'attente de 5 s et
  de 10 s côté web, indicatifs, sans jamais de formulation de refus (critère T7, côté web). Test `pending-wait.test.ts` (4).
- `apps/web/test/command-tabs-106.test.ts` (2) : un onglet dupliqué retrouve l'entrée en « orpheline » (corps jamais
  stocké), ne peut que la vérifier par lecture, ne renvoie rien ; une file vivante rejoue avec la même clé
  d'idempotence, la même méthode, le même corps et le même chemin (critère A4).
- Aucun fichier de `.github/`, de `scripts/ios/`, de `MessagingUI` ni de `SchoolBoxes*` n'est modifié.

## 2. Exécutions CI (workflow `refonte-ios.yml`, `workflow_dispatch`, SHA `23487c5b`)

| Run | Sélection | Résultat |
|---|---|---|
| [43066913872](https://github.com/tomyrms/Drivy/actions/runs/43066913872) | `unit_only`, portée `all` (avec relais Fastify/PostgreSQL) | vert : 632 tests, 0 échec |
| [43068112256](https://github.com/tomyrms/Drivy/actions/runs/43068112256) | UI iPhone : `MessagingLatencyUITests`, `SchoolPlanningCancellationUITests` | rouge : 6 tests, 1 échec |
| [43075946109](https://github.com/tomyrms/Drivy/actions/runs/43075946109) | UI iPhone : `MessagingLatencyUITests/testFifteenSecondResponseKeepsReactionAndComposerUsable` seul | vert : 1 test, passé en 60 s |

Détail du run 43066913872 : les cinq tests historiquement rouges passent
(`anInvitationAndAProfileRecordDoNotShareAVersion`, `aRefusedPermitReviewKeepsTheLessonAndFallsBackToTheWrittenReason`,
`laterGPSDepartureAlsoWaitsForSavedObjectives`, `lateConfirmationRefreshesTheNoGPSWorkspaceAfterItsSheetClosed`,
`receiptOfAnotherLessonNeverBroadcastsTheOpenLessonAsItsTarget`). `MatrixMessagingRelayIntegrationTests/
testRealRelayExchangeIdempotenceRecoveryAndContextRefusal` passe (64,9 s) : l'étape READINESS n'a pas expiré dans ce run.
C'est une observation sur un run, pas une cause établie : l'échec historique (-1001 après 25 s) n'a pas été expliqué.

Détail du run 43068112256 : passés `testFiveSecondResponseCannotReintroduceAQuicklyRemovedReaction`,
`testOneSecondRefusalRemovesOnlyTheRejectedProjection` et les trois tests de `SchoolPlanningCancellationUITests`. Échec :
`MessagingLatencyUITests.testFifteenSecondResponseKeepsReactionAndComposerUsable`, assertion de la ligne 30 du fichier de
test (`XCTAssertTrue` sans message propre, après l'attente de 7 s sur l'état « non confirmée »). Le fichier relève de la
messagerie, interdit à ce lot ; l'assertion n'a pas été modifiée.

## 3. #106 — socle de commandes optimistes

| Critère | Web | iOS | Preuve |
|---|---|---|---|
| Une file par commande, clé d'idempotence = operationId, If-Match | fait | fait | `command-core`, `command-store-code` ; `SchoolCommandOutboxTests` (run 43066913872) |
| Ordonnancement par conflits réels, pas de verrou d'école | fait | fait | `command-lane`, `command-conflicts`, `command-latency-106` ; `SchoolCommandScopes106Tests` (24) |
| Latence de 15 s sans blocage des commandes indépendantes | fait | fait | `command-latency-106` ; `SchoolCommandSendAdmissionTests`, `MessagingLatencyUITests` (3 sur 3 passés au moins une fois ; le test de 15 s a échoué une fois sur deux) |
| Reprise après perte de réponse, double appui, réponses inversées | fait | fait | `command-latency-106`, `command-recovery-106` ; `SchoolPendingRequestResolutionTests` |
| Seuils 5 s / 10 s indicatifs, jamais un refus | livré ici | fait | `pending-wait.test.ts` ; `SchoolWaitMonitorTests` |
| Onglet dupliqué (corps jamais persisté côté web) | livré ici | sans objet | `command-tabs-106.test.ts` |
| Annulation avant envoi (L2) | sans objet : aucune attente avant envoi (voir 3.1) | planification seulement, primitive commune `SchoolCommandSendAdmission` | `command-latency-106` (critères 2 et 3) ; `SchoolPlanningAdmission106Tests`, `SchoolPlanningCancellationUITests` |
| Réconciliation champ par champ (L3) | fait : fusion à trois voies `rebaseConfirmedDraft` | tests existants du profil et des brouillons | `draft-rebase-sequence-106.test.ts` (4) ; `SchoolProfileWorkspaceTests` |
| Expiration générale d'une commande en file (L1) | non | non | décision produit, non prise (voir 3.2) |
| Migration et retour arrière avec files remplies | fait (file pleine, entrées invalides, clé d'une version plus récente) | non démontré : aucun test unitaire isolable trouvé | `command-migration-106.test.ts` (5) |
| Plusieurs appareils réels | non démontré | non démontré | appareil physique requis |

### 3.1 L2 — annulation avant envoi

Le contrat (R2, L2) interdit d'ajouter un bouton Annuler universel tant que la capacité n'existe pas. Sur le web, il n'y a
aucune fenêtre avant envoi à annuler : l'admission refuse localement (`LOCAL_COMMAND_CONFLICT`, `LOCAL_COMMAND_LIMIT`), rien
n'est mis en file et la saisie est gardée (preuve : `command-latency-106`, critères 2 et 3 ; `member-commands-131`). Sur iOS,
la primitive commune `SchoolCommandSendAdmission` existe et est adoptée là où une attente avant envoi est exposée
(planification : création et déplacement de leçon). L'étendre à d'autres commandes suppose des changements d'interface Swift
qui ne peuvent pas être compilés ici et un choix de produit sur quelles écritures deviennent annulables ; ce n'est donc pas
fait, et le critère est considéré satisfait pour ce qui existe.

### 3.2 L1 — expiration générale : décision à prendre (non prise)

- Décision : fixer ou non une durée de conservation d'une commande en file ou d'un brouillon chiffré abandonné, et ce qui arrive à l'échéance.
- Options : (a) aucune expiration, la commande reste protégée et vérifiable sans renvoi automatique jusqu'à une action humaine ; (b) durée par famille de commandes (par exemple plus courte pour un paiement que pour une note) ; (c) revue humaine explicite à la reprise, sans suppression silencieuse.
- Le contrat dit de ne pas inventer un TTL universel ; rien n'est donc implémenté tant que le porteur n'a pas choisi.

Local : `pending-recovery-106` échoue en local (2 échecs) faute de `playwright-core` ; absence de dépendance déjà
documentée, pas une régression, non corrigée ici.

## 4. #131 — qualification de la réactivité

- « READINESS non résolu » désigne le scénario de relais réel de `MatrixMessagingRelayIntegrationTests`, dont l'étape
  READINESS expirait (-1001 après environ 25 s, cause inconnue ; instrumentation `RelayReadinessDiagnosticTests`, #78).
  Ce n'est pas un défaut de code du lot : le fichier relève de la messagerie. Résultat sur ce SHA : passé une fois
  (run 43066913872). Une seule exécution ne prouve pas la stabilité ; l'issue de cause reste ouverte.
- Les cinq régressions natives de `native-regressions-131-20261104.md` sont vertes sur ce SHA (run 43066913872).
- La matrice `matrice-couverture-131.md` est mise à jour : les huit écritures sans test dédié ont maintenant un test de
  contrat (`entry-client-131.test.ts` 15 : W01, W03 à W06 ; `member-commands-131.test.ts` 7 : W47, W48 ;
  `SchoolCourseFollow131Tests.swift` 5 : I39, à qualifier par la CI Apple). Ce sont des tests d'échange et de
  classification d'échec, sans rendu : le comportement des formulaires et des panneaux reste à couvrir par la campagne
  navigateur. `W46`, `W66`, `W67`, `I12` restent sans preuve.
- Mesures web synthétiques : `web-reactivity-measures-131-20261105.md` (Windows/Chromium, petit échantillon). Aucune
  mesure sur appareil, VoiceOver, batterie ou GPS physique.

## 5. #105 — épopée

Sous-issues #104 et #107 à #130 : fermées. #106 et #131 : ouvertes. Les critères propres à l'épopée dépendent de #106, de
#131 et de mesures sur appareil ; ils ne sont pas satisfaits par ce lot.

## 6. Restant

- Physique : mesures sur appareil, VoiceOver, plusieurs appareils.
- Décision : expiration générale (L1, voir 3.2). Le périmètre d'annulation avant envoi (L2) n'appelle pas de décision tant qu'aucun bouton universel n'est voulu.
- Technique : cause du délai READINESS ; instabilité de `testFifteenSecondResponseKeepsReactionAndComposerUsable` (rouge dans la sélection de 6 tests, vert seul : deux exécutions, cause non établie) ;
  parcours rendus des formulaires et panneaux web (campagne navigateur, la CI Chromium étant hors service) ; `pending-recovery-106` local (`playwright-core`).
