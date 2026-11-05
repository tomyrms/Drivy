# Phases de readiness du relais — instrumentation opt-in (#78)

Date : 5 novembre 2026. Base : `0e1aa871935f3d2a904011ea2f4732a968c67c41`, worktree
`integration-issues-20261105`. Suite du diagnostic `artifacts/q9-relay-readiness-diagnostic/RAPPORT.md`
(deux occurrences `READINESS` à ~25 s, phase exacte inconnue) et de l'arbitrage de placement du
coordinateur (option A, section « Arbitrage de placement »).

Objet : **mesurer** les phases d'une seule requête de readiness, sans corriger le timeout, sans
changer le transport, les bornes, le TLS, le verdict ni introduire de réessai ou de préchauffage.

## 1. Contrat

Activé uniquement sous `#if DEBUG && targetEnvironment(simulator)`, et seulement pour la session
créée par la sonde :

- `SchoolURLSessionTransport(readinessPhaseProbe:)` est un second initialiseur ; `SchoolURLSessionTransport()`
  reste identique et n'observe rien. Aucune métrique globale, aucun observer sur les sessions métier.
- La configuration de session est factorisée mais **inchangée** : `ephemeral`, cache et cookies nuls,
  `reloadIgnoringLocalCacheData`, `timeoutIntervalForRequest = 20`, `timeoutIntervalForResource = 30`,
  délégué qui refuse toute redirection.
- Aucun observer en Release ni sur appareil physique : la condition exclut les deux.

## 2. Corrélation à une seule sonde

Trois verrous indépendants, aucun partagé :

1. **Session dédiée** : le test crée une instance de transport par sonde ; le délégué de cette
   session ne connaît que son `readinessPhaseProbe`.
2. **Filtre de requête** (`RelayReadinessPhaseGuard.accepts`) : méthode absente ou `GET`, schéma
   `https`, hôte `localhost` ou `127.0.0.1`, port 1024–65535, chemin exact `/qualification/ready`,
   sans user/password/query/fragment et sans en-tête `Authorization`. Toute autre requête est ignorée.
3. **Première observation seulement** : `RelayReadinessPhaseProbe.record` ignore les observations
   suivantes ; une sonde ne peut pas être réécrite par une requête tardive.

Le délégué lit `task.originalRequest` (jamais une URL reconstruite) et transmet les métriques sans
les stocker.

## 3. Vocabulaire fermé

Seuls des marqueurs `R-…` passant `MessagingDiagnostics.isSafe` (`A-Z`, `0-9`, `-`, ≤ 40 caractères)
sortent. Le singleton `MessagingDiagnostics.shared` n'est **jamais** modifié : la sonde a son propre
stockage, protégé par `NSLock`.

| Marqueur | Sens |
|---|---|
| `R-CONNECT-MS-<n>` / `R-TLS-MS-<n>` | durée mesurée de la phase, en millisecondes entières bornées 0–600 000 |
| `R-REQUEST-MS-<n>` / `R-RESPONSE-MS-<n>` | idem pour l'envoi et la réception |
| `R-TOTAL-MS-<n>` | `fetchStartDate` → `responseEndDate` |
| `R-<PHASE>-ABSENT` | le système n'a pas publié le début de la phase |
| `R-<PHASE>-INCOMPLETE` | début publié, fin absente (cas attendu d'un timeout de réponse) |
| `R-<PHASE>-INVALID` | fin antérieure au début, ou date non finie |
| `R-CONN-REUSED` | connexion réutilisée : ni CONNECT ni TLS mesurés |
| `R-METRICS-MISSING` | aucune métrique reçue : **limite explicite**, jamais un succès de mesure |

Aucun seuil n'est qualifié de « lent » : la mesure ne conclut pas à la place du diagnostic.
Aucune date absolue, URL, adresse, certificat, corps, en-tête, `userInfo` ni description libre
n'est émise ou journalisée.

## 4. Cycle de vie et synchronisation

- Le délégué est appelé sur la file de délégué de la session (hors MainActor) ; l'écriture est
  protégée par verrou, la lecture aussi. Aucune course avec le `catch` du test.
- Le test attend **au plus 2 s** (boucle de 20 ms) l'arrivée du callback, puis imprime
  `L2 readiness phases : …`. Cette attente est bornée, ne retarde jamais le transport et ne change
  ni le résultat ni l'erreur : `URLError` et le verdict `READINESS`/FFI sont conservés tels quels.
- Si le callback n'arrive pas dans la fenêtre, la sortie affiche `R-METRICS-MISSING` : c'est une
  mesure manquante annoncée comme telle.
- Aucune continuation pendante, aucune tâche de fond, aucun état global.

## 5. Tests (synthétiques, sans réseau)

Quatre cas ajoutés à `RelayReadinessDiagnosticTests` (classe existante, même fichier autorisé) :

| Cas | Vérifie |
|---|---|
| `testReadinessPhaseMarkersStayClosedAndBounded` | marqueurs exacts pour des phases synthétiques, tous sûrs, aucun dépassement |
| `testReadinessPhaseMarkersCoverMissingPartialAndInvalidTimestamps` | métriques absentes, phases absentes, fin manquante, dates inversées ou infinies, connexion réutilisée sans TLS |
| `testReadinessPhaseFilterAcceptsOnlyTheQualificationProbe` | accepte GET HTTPS loopback `/qualification/ready` ; rejette http, hôte distant, chemin voisin, query, fragment, userinfo, POST, en-tête `Authorization`, port hors plage |
| `testReadinessPhaseProbesKeepSeparateObservations` | deux sondes ne partagent rien, la seconde observation d'une sonde est ignorée, une requête hors périmètre est ignorée, `R-METRICS-MISSING` avant toute observation |

Aucun de ces cas n'émet de requête : ils construisent des `URLRequest` et des valeurs de phase
synthétiques.

## 6. Sélection

La garde FFI (`scripts/messaging-relay-qualification.py`) exige **exactement un** cas dans
`MatrixMessagingRelayIntegrationTests` : ajouter des cas à cette suite aurait fait échouer la garde
même sur une campagne verte. Les tests vivent donc dans `RelayReadinessDiagnosticTests`, et la
sélection `messaging` est étendue d'une classe, sans retirer ni réordonner les dix existantes :

- `scripts/ios/test-selection.sh` : `RelayReadinessDiagnosticTests` ajoutée en fin de liste.
- `scripts/ios/test_test_selection.py` : `MESSAGING_SUITES` aligné sur cette onzième classe.

Sélection réelle relevée : **11 classes**, `MatrixMessagingRelayIntegrationTests` toujours présente,
`RelayReadinessDiagnosticTests` en dernier, garde FFI inchangée.

## 7. Contrôles réellement exécutés (Windows, sans Xcode)

| Commande | Résultat | Code |
|---|---|---|
| `python -I scripts/ios/test_test_selection.py` | `Ran 25 tests … OK` | 0 |
| `python -I scripts/qualification/test_relay_plan.py` | `Ran 8 tests … OK` | 0 |
| relevé de sélection (Git Bash, `DRIVY_IOS_UNIT_SCOPE=messaging`) | `count=11`, liste conforme | 0 |
| `git diff --check` | aucune erreur | 0 |
| `git diff --exit-code HEAD -- scripts/messaging-relay-qualification.py … workflows … MessagingMediaRealRelayTests.swift MessagingCore MessagingAPI` | identique au HEAD | 0 |

**Non exécuté** : compilation Swift, tests XCTest, exécution Apple. Aucun Xcode ni Swift sur ce
poste ; aucun cycle RED/GREEN Swift n'est revendiqué.

## 8. Limites

- Une mesure absente n'est pas une mesure : `R-METRICS-MISSING` documente le manque.
- Le premier échantillon retenu par sonde est unique ; un second envoi sur la même sonde est ignoré.
- Les métriques système ne disent pas ce que le relais a reçu : elles situent la phase côté client.
- Cette instrumentation **ne corrige pas** le timeout de readiness ; elle ne fait que rendre la
  phase observable lors de la prochaine occurrence.
- Aucun préchauffage, réessai, sleep ajouté au transport, relèvement de délai ni relâchement TLS.

## 9. Fichiers

- `apps/ios/Drivy/SchoolAPI/DrivyAPIClient.swift` : types de phase, filtre, marqueurs, sonde,
  second initialiseur du transport, configuration factorisée à l'identique.
- `apps/ios/DrivyTests/MatrixMessagingRelayIntegrationTests.swift` : opt-in de la sonde dans
  `exerciseRealRelay` (une seule requête readiness), impression bornée, quatre cas de test dans
  `RelayReadinessDiagnosticTests`.
- `scripts/ios/test-selection.sh`, `scripts/ios/test_test_selection.py` : onzième classe.
- Le présent document.

Aucun changement du client métier, des tests UI, de la fixture Fastify, du workflow, des locks,
de la crypto/FFI, du décodeur, des droits ou de la persistance.
