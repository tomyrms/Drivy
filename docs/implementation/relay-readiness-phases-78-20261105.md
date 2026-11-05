# Phases de readiness du relais — instrumentation opt-in (#78)

Date : 5 novembre 2026. Branche `tomyrms/integration-issues-20261105`.
Première passe : `0e1aa871` → `f0ade133` (revue indépendante `ctx_7ea7b6ce5478`).
Seconde passe corrective : voir §10.

Objet : **mesurer** les phases d'une seule requête de readiness, sans corriger le timeout, sans
changer le transport, les bornes, le TLS, le verdict, et sans réessai ni préchauffage.

## 1. Contrat

Activé uniquement sous `#if DEBUG && targetEnvironment(simulator)`, et seulement pour la session
créée par la sonde :

- `SchoolURLSessionTransport(readinessPhaseProbe:)` est un second initialiseur ; `SchoolURLSessionTransport()`
  reste identique et n'observe rien. Aucune métrique globale, aucun observer sur les sessions métier.
- La configuration de session est factorisée mais **inchangée** : `ephemeral`, cache et cookies nuls,
  `reloadIgnoringLocalCacheData`, `timeoutIntervalForRequest = 20`, `timeoutIntervalForResource = 30`,
  délégué qui refuse toute redirection.
- Aucun observer en Release ni sur appareil physique.

## 2. Corrélation à une seule sonde

Trois verrous indépendants :

1. **Session dédiée** : une instance de transport par sonde ; son délégué ne connaît que cette sonde.
2. **Filtre de requête** (`RelayReadinessPhaseGuard.accepts`) : méthode absente ou `GET`, schéma
   `https`, hôte `localhost` ou `127.0.0.1`, port 1024–65535, chemin exact `/qualification/ready`,
   sans user/password/query/fragment, sans en-tête `Authorization`. Toute autre requête est ignorée.
3. **Première observation seulement** : `record` ignore toute observation ultérieure ; un callback
   répété ne réémet rien et n'écrase pas la mesure.

## 3. Vocabulaire fermé et états distincts

Seuls des marqueurs `R-…` passant `MessagingDiagnostics.isSafe` (`A-Z`, `0-9`, `-`, ≤ 40) sortent.
Le singleton `MessagingDiagnostics.shared` n'est jamais modifié.

| Marqueur | Sens |
|---|---|
| `R-CONNECT-MS-<n>` / `R-TLS-MS-<n>` | durée de la phase, millisecondes entières bornées 0–600 000 |
| `R-REQUEST-MS-<n>` / `R-RESPONSE-MS-<n>` | idem pour l'envoi et la réception |
| `R-TOTAL-MS-<n>` | `fetchStartDate` → `responseEndDate` |
| `R-<PHASE>-ABSENT` | **aucune** des deux extrémités publiée |
| `R-<PHASE>-INCOMPLETE` | début fini publié seul |
| `R-<PHASE>-INVALID` | fin seule, dates inversées, ou date non finie |
| `R-CONN-REUSED` | connexion réutilisée : ni CONNECT ni TLS mesurés (choix M1) |
| `R-TXN-<n>` | nombre de transactions, borné à 9 (« 9 ou plus ») ; seule la première est détaillée |
| `R-TRANSACTION-NONE` | callback reçu, **zéro** transaction publiée |
| `R-METRICS-PENDING` | lecture immédiate : **aucun callback à cet instant** (état temporel) |

Les trois derniers états ne sont jamais confondus : `PENDING` (rien reçu à cet instant),
`TRANSACTION-NONE` (métriques reçues, aucune transaction), phases (transaction présente).
Aucun seuil n'est qualifié de « lent » ; aucune date absolue, URL, adresse, certificat, corps,
en-tête, `userInfo` ni description libre n'est émise.

## 4. Cycle de vie, synchronisation, émission

- Le délégué est appelé sur la file de délégué de la session ; l'écriture et la lecture de la sonde
  sont protégées par `NSLock`. Aucune course avec le test.
- **Aucune attente** : ni boucle, ni `Task.sleep`, ni échéance, ni horloge. Le transport n'est jamais
  retardé et aucune annulation n'est absorbée.
- À la **première** observation éligible, la sonde retient les marqueurs puis appelle son `sink`
  **hors verrou**, une seule fois ; le sink ne reçoit que des marqueurs fermés (aucune requête,
  erreur, URL ou objet du test).
- Immédiatement après le `send`, en succès comme en échec, le test lit l'état courant et imprime
  soit les marqueurs reçus, soit `R-METRICS-PENDING`. Ce `PENDING` est **temporel** : il n'affirme
  pas qu'aucun callback ne viendra.
- Un callback **tardif** émet encore sa ligne : la preuve n'est pas supprimée parce qu'un `PENDING`
  a déjà été imprimé. Conséquence assumée : la même mesure peut apparaître deux fois (ligne
  `(callback)` puis ligne immédiate), et une ligne tardive peut arriver après la fin du cas.

## 5. Tests (synthétiques, sans réseau, sans sleep)

| Cas | Vérifie |
|---|---|
| `testReadinessPhaseMarkersStayClosedAndBounded` | marqueurs exacts (dont `R-TXN-1`), tous sûrs ; borne exercée (`milliseconds(700)` → 600 000, négatif → 0, infini → 600 000) ; saturation `R-TXN-9` |
| `testReadinessPhaseMarkersCoverMissingPartialAndInvalidTimestamps` | `TRANSACTION-NONE` ; tout absent → `ABSENT` ; fin sans début → `INVALID` (phase et total) ; début seul → `INCOMPLETE` ; inversé/non fini → `INVALID` ; réutilisé sans TLS ; total incomplet |
| `testReadinessPhaseFilterAcceptsOnlyTheQualificationProbe` | accepte GET HTTPS loopback `/qualification/ready` ; rejette http, hôte distant, chemin voisin, `/extra`, query, fragment, userinfo, POST, `Authorization`, port 80 |
| `testReadinessPhaseProbeStaysPendingUntilCallbackAndKeepsLateObservation` | `immediate == .pending` avant callback ; callback tardif conservé et émis **une fois** ; callback répété sans réémission ni écrasement |
| `testReadinessPhaseProbesKeepSeparateObservations` | deux sondes avec sinks distincts ; requête hors périmètre → ni observation ni émission ; aucun partage |

Le sink des tests est un capteur local qui ne garde que des tableaux de marqueurs.

## 6. Sélection

La garde FFI exige **exactement un** cas dans `MatrixMessagingRelayIntegrationTests` : les tests
vivent donc dans `RelayReadinessDiagnosticTests`, et la sélection `messaging` compte onze classes
(`scripts/ios/test-selection.sh`, `MESSAGING_SUITES`). Les deux scripts sont inchangés depuis
`f0ade133`.

## 7. Contrôles réellement exécutés

| Commande | Résultat | Code |
|---|---|---|
| `python -I scripts/ios/test_test_selection.py` (revue indépendante, scripts inchangés depuis) | `Ran 25 tests … OK` | 0 |
| `python -I scripts/qualification/test_relay_plan.py` (idem) | `Ran 8 tests … OK` | 0 |
| relevé de sélection `messaging` | `count=11`, ordre conservé | 0 |
| `git diff --check` | aucune erreur | 0 |
| `git diff --exit-code` sur garde FFI, workflow, scripts hors sélection, métier, crypto, fixtures | identique | 0 |

**Non exécuté** : compilation Swift, XCTest, exécution Apple. Aucun Xcode ni Swift sur ce poste ;
aucun cycle RED/GREEN Swift n'est revendiqué. Les deux suites Python n'ont pas été relancées dans
cette passe : les scripts de sélection sont inchangés depuis la revue qui les a exécutées.

## 8. Limites

- `R-METRICS-PENDING` à la lecture immédiate ne prouve pas l'absence de callback : seule une ligne
  `(callback)` ultérieure établit une mesure.
- Une **émission tardive** est observable dans les journaux du processus de test / le résultat de
  campagne ; son attribution au même cas XCTest n'est pas garantie sans preuve supplémentaire.
- L'absence de toute ligne ne prouve **pas** un build Release : elle peut venir d'un arrêt avant la
  sonde, d'une lacune de collecte des journaux, ou d'un build hors `DEBUG`/simulateur. La prochaine
  campagne doit constater la configuration, la découverte des cas et la présence des marqueurs.
- Seule la première transaction est détaillée ; `R-TXN-<n>` signale qu'il y en a eu d'autres sans
  les décrire, et ne prouve rien sur l'incident historique.
- La session et son délégué ne sont jamais invalidés (limite **préexistante**, non refactorée) : une
  sonde peut recevoir un callback après la fin du cas.
- M1 : sur connexion réutilisée, CONNECT et TLS sont omis ; choix conservé et documenté.
- Les métriques système ne prouvent pas ce que le relais a reçu.
- L'instrumentation **ne corrige pas** le timeout ; elle le rend observable.

## 9. Fichiers

- `apps/ios/Drivy/SchoolAPI/DrivyAPIClient.swift` : types de phase, filtre, marqueurs, sonde avec
  sink, second initialiseur du transport, configuration inchangée.
- `apps/ios/DrivyTests/MatrixMessagingRelayIntegrationTests.swift` : opt-in de la sonde dans
  `exerciseRealRelay`, lecture immédiate sans attente, cinq cas dans `RelayReadinessDiagnosticTests`.
- `scripts/ios/test-selection.sh`, `scripts/ios/test_test_selection.py` : onzième classe (inchangés
  depuis `f0ade133`).
- Le présent document.

## 10. Corrections après la revue indépendante

| Point | Correction |
|---|---|
| **C1** isolation Swift 6 | `sendReadiness` et `printReadinessPhaseObservation` sont `@MainActor`, comme leur appelant ; aucune méthode d'instance nonisolated `async` n'est plus appelée depuis le MainActor ; la classe n'est pas annotée et Sendable n'est pas relâché. |
| **I1** attente | attente de 2 s supprimée (plus de `printReadinessPhases`, plus de `Date`/`Task.sleep`) ; émission depuis le callback via le sink, lecture immédiate `PENDING`/reçue, callback tardif conservé. |
| **I2** fin sans début | `phase`/`total` distinguent `ABSENT` (aucune extrémité), `INCOMPLETE` (début fini seul) et `INVALID` (fin seule, inversée, non finie). |
| **I3** états confondus | `R-TRANSACTION-NONE` (callback, zéro transaction) et `R-METRICS-PENDING` (pas encore de callback) remplacent `R-METRICS-MISSING`. |
| **I4** transactions multiples | `R-TXN-<n>` borné à 9, à côté des phases de la première transaction ; aucune conclusion sur la tâche entière. |
| **I5** tests | borne 600 000 exercée, fin sans début, `TRANSACTION-NONE`, `PENDING` puis callback tardif, callback répété, isolation des sondes. |
| **M3** doc | plus d'attente annoncée, plus de promesse d'absence définitive ; `PENDING` explicitement temporel. |
| **M4** signal éteint | absence de ligne ≠ build Release ; la campagne doit constater configuration, découverte et marqueurs. |
| **M2** durée de vie | documentée comme limite préexistante, sans refactor du transport. |
