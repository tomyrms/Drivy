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

Deuxième passe, SHA `33640951` (dernier commit de code ; les commits suivants ne touchent que de la documentation) :

| Run | Sélection | Résultat |
|---|---|---|
| [43081282148](https://github.com/tomyrms/Drivy/actions/runs/43081282148) | `unit_only`, portée `all`, SHA `deb4995b` | rouge : la compilation de `SchoolCourseFollow131Tests.swift` échoue (ligne 79, « failed to produce diagnostic for expression », expression ternaire à valeurs hétérogènes) ; aucun test exécuté |
| [43082421565](https://github.com/tomyrms/Drivy/actions/runs/43082421565) | `unit_only`, portée `all`, SHA `33640951` | vert : 632 tests XCTest, 0 échec ; 1 306 tests Swift Testing en 124 suites, tous passés ; les cinq tests de `SchoolCourseFollow131Tests` passent ; `MatrixMessagingRelayIntegrationTests` passe (5,7 s) |

Budget CI : 5 runs sur 6 utilisés (la première passe en a pris 3, la seconde 2).

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

### 3.2 L1 — garder et demander (décision du porteur, 12 novembre 2026)

Décision consignée dans `decisions-2026-11-12.md` : une commande restée en file ou un brouillon abandonné n'est jamais supprimé ni renvoyé en silence ; à la reprise, la personne voit l'entrée et choisit de l'envoyer ou de l'abandonner ; aucune durée d'expiration.

Conformité relevée dans le code :

| Point | Web | iOS |
|---|---|---|
| Aucune suppression par délai | conforme : `command-retention-106.test.ts` fait avancer l'horloge de dix ans, l'entrée reste | écart : voir ci-dessous |
| Aucun renvoi automatique | conforme : `resend` n'est appelé que par le bouton de `pending-requests.tsx`, et ne fait rien pour une entrée orpheline (aucun paquet, testé) | conforme sur les commandes d'école (« rien ne doit la rejouer à l'insu de la personne », `SchoolPendingCommandText.swift:79`) |
| Écran où la personne choisit | `pending-requests.tsx:87-89` : « Renvoyer la même demande » et « Arrêter le suivi » (avec confirmation) | « Abandonner » dans `SchoolCourseEnrollmentViews.swift:145`, `SchoolCourseEditorView.swift:255`, `SchoolCapturePreparationView.swift:482` et les vues d'invitation et de planification |

Écarts, non corrigés ici :

1. Web, entrée reprise après rechargement : son contenu n'est volontairement jamais stocké (politique de persistance du navigateur), donc elle ne peut être que vérifiée ou abandonnée, pas envoyée. Offrir l'envoi après rechargement suppose de stocker le contenu : décision de confidentialité à prendre, pas un correctif.
2. Web, `sessionStorage` : fermer l'onglet fait perdre le suivi sans geste de la personne. Ce n'est pas un délai, mais ce n'est pas « garder » non plus ; même cause, même décision que le point 1.
3. Web, « Arrêter le suivi » n'est offert que lorsque le contenu est perdu, qu'aucune trace n'existe à l'école ou que la vérification ne conclut pas (`pendingActions`, `command-store.ts:42`) ; une demande encore envoyable se renvoie ou se vérifie d'abord. Conforme à « envoyer ou abandonner » une fois la vérification faite.
4. Web et iOS, leçon dont le créneau est passé : le renvoi est retiré (`command-recovery.ts`, `SchoolPendingCommandText.swift:79`). La personne garde vérifier et abandonner.
5. iOS, départ de trajet (GPS), suppression automatique par délai : `SchoolCapturePreparationWorkspace.swift:661-663` retire sans geste une demande de départ que l'école déclare inconnue au-delà de 120 s (`settledRequestAge`, ligne 680), et `:688-695` classe de même une demande jamais émise. Ces deux chemins contredisent la décision pour les demandes de départ. Le correctif touche la préparation de capture (montrer l'entrée et demander au lieu de classer) : à découper en un lot propre avec un run, non fait dans cette passe.
6. iOS, brouillon chiffré de messagerie : aucun délai de purge trouvé dans `MessagingCore` ; le dossier de messagerie est interdit à ce lot et son écran de reprise n'a pas été relu.

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
- Décision L1 prise le 12 novembre (garder et demander) ; reste l'écart iOS du départ de trajet (3.2, point 5). Le périmètre d'annulation avant envoi (L2) n'appelle pas de décision tant qu'aucun bouton universel n'est voulu.
- Technique : cause du délai READINESS ; instabilité de `testFifteenSecondResponseKeepsReactionAndComposerUsable` (rouge dans la sélection de 6 tests, vert seul : deux exécutions, cause non établie) ;
  parcours rendus des formulaires et panneaux web (campagne navigateur, la CI Chromium étant hors service) ; `pending-recovery-106` local (`playwright-core`).
