# Médias #97 — T2b2 : transport binaire natif, borné et lié au contexte

Base : branche de travail `tomyrms/issues-medias-transport-97`, sur `883581ad321b` (T2a). Livraison initiale `b4ec0dca`, puis **correction 1** (§13). Seuls les cinq fichiers du §11 sont modifiés.

Ce lot livre **une primitive de transport**. Il n'est branché ni à la file d'attente média, ni au coffre, ni au contenu v3, ni à l'UI : aucun envoi utilisateur complet n'est livré, aucun écran n'est activé, aucun texte d'interface n'est défini.

## 1. Pourquoi un transport dédié

`SchoolHTTPResponse` n'expose aucun en-tête : impossible de lire `X-Drivy-School-Id`, `X-Drivy-Access-Epoch`, `X-Drivy-Media-Sha256` ni `Content-Length`. `SchoolURLSessionTransport` borne **toutes** ses réponses à 2 Mio (`maximumResponseBytes`) et sert les appels ordinaires : l'élargir pour les médias élargirait aussi les 29 appelants existants.

Décision : aucun de ces deux types n'est touché. Un fil média dédié (`MessagingMediaHTTPWire` + `MessagingMediaURLSessionTransport`) porte la réponse binaire bornée et les en-têtes nommés. La limite ordinaire reste `2 * 1_024 * 1_024` (vérifié après coup, §10).

## 2. Interface figée (§4.5) et ajouts

```swift
struct MessagingMediaReceipt: Sendable, Equatable {
    enum State: String, Sendable, Equatable { case uploaded = "UPLOADED"; case attached = "ATTACHED" }
    let mediaID: UUID      // celui du sceau, jamais un nouvel UUID
    let byteSize: Int      // taille du chiffré
    let sha256: String     // hex minuscule 64 caractères du chiffré
    let state: State
}

protocol MessagingMediaTransport: Sendable {
    func upload(_ sealed: MessagingSealedMedia, scope: MessagingScope, conversationID: UUID) async throws -> MessagingMediaReceipt
    func download(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws -> Data
    func cancel(mediaID: UUID, scope: MessagingScope, conversationID: UUID) async throws
}

enum MessagingMediaTransportFailure: Error, Equatable, Sendable {
    case invalidIntent, contextChanged, accessChanged, deviceRequired, notFound, purged,
         alreadyAttached, intentConflict, sizeConflict, stateConflict, unavailable,
         invalidResponse, integrityMismatch, tooLarge
}
```

L'énumération est **fermée et sans présentation** : ni `LocalizedError`, ni `errorDescription`, ni texte. La spec du lot exclut toute nouvelle copie UI ; le mapping d'affichage appartient au futur worker UI (§6).

Aucun état `PURGED` n'est représentable dans le reçu : une purge est un refus (`purged`). `ATTACHED` s'interprète comme « le serveur connaît déjà ce média rattaché », jamais comme une preuve de publication ou de livraison au destinataire.

L'identifiant d'appareil est **injecté explicitement** à la construction (`init(baseURL:deviceID:…)`, `using(baseURL:deviceID:tokenSource:…)`) : format `[A-Z0-9]{10,32}`, validé avant tout réseau. Aucune valeur inventée, aucune recherche implicite. L'en-tête `X-Drivy-Device-Id` est un identifiant déclaré, pas une preuve de possession cryptographique (contrat §3.6).

## 3. Contrat réseau appliqué

`PUT|GET|DELETE {base}/v1/schools/{school}/messaging/conversations/{conversation}/media/{media}` — l'URL est construite uniquement depuis la base contrôlée et des UUID. La base doit satisfaire `scope.apiBaseURL == baseURL.absoluteString`, `DrivyAPIClient.permits(baseURL)` et l'hôte final doit rester l'origine de départ.

| Élément | Dépôt | Téléchargement | Annulation |
|---|---|---|---|
| Corps | chiffré brut, `Content-Type: application/octet-stream`, `Content-Length` exact | — | — |
| `Accept` | `application/json` | `application/octet-stream` | `application/json` |
| En-têtes | `Authorization`, `X-Drivy-Expected-Person-Id`, `X-Drivy-Expected-Access-Epoch`, `X-Drivy-Device-Id`, `Cache-Control: no-store` | idem | idem |
| Plafond de lecture | 16 Kio (enveloppe) | 4 Mio + 8 Kio (flux) | 16 Kio (enveloppe) |
| Succès attendu | `200` JSON `data{mediaId,byteSize,sha256,state}` + `context` | `200` octets + `Content-Length` + école/époque/SHA-256 | `200` JSON `data{mediaId,deleted:true}` + `context` |

Bornes exactes, en trois valeurs distinctes et non interchangeables :

| Borne | Valeur | Rôle |
|---|---|---|
| Limite métier du média | `4 194 304` | `MessagingHTTPMediaTransport.maximumByteSize`, identique à `AESCTRMediaCryptography.maximumByteSize` et au serveur |
| Plafond de flux (« 4 Mio + 8 Kio ») | `4 202 496` | `MessagingMediaResponseCeiling.mediaLimit` |
| Plafond d'enveloppe | `16 384` | `MessagingMediaResponseCeiling.envelopeLimit` |

Le wire applique les plafonds de flux/enveloppe ; l'adaptateur applique la limite métier. Un test vérifie l'identité des deux constantes de 4 Mio et qu'une taille de `4 194 305` reste lisible par le wire (c'est l'adaptateur qui la refuse).

## 4. Garanties mises en œuvre

1. **Scope complet avant et après chaque attente.** `verifyCurrent` compare `MessagingScope` (compte, école, époque, URL d'API) avant le jeton, après le jeton, avant chaque émission, après la réponse, et après une invalidation **avant** de demander un renouvellement. `start` vérifie aussi après l'attente de `DrivyAPIClient.permits`. Une réponse tardive d'un contexte quitté lève `contextChanged` et n'est jamais rendue.
2. **Annulation vérifiée aux mêmes points.** `Task.checkCancellation()` à l'entrée de `start`, avant chaque émission, après la réponse, après l'invalidation et de part et d'autre de l'attente du jeton. Une tâche déjà annulée n'entre pas dans la source de jeton.
3. **Jeton.** Porteur non vide, ASCII `> 32 && < 127` : un jeton contenant un CR/LF n'est jamais émis.
4. **Attente du jeton fermée.** `accessToken(scope:operation:)` : annulation → `CancellationError` ; erreurs typées du module préservées ; `IdentityFailure.reauthentication` → `accessChanged` ; tout le reste → `unavailable`. Aucun `NSError`, domaine, `userInfo` ni texte libre ne traverse la frontière (c'est le mapping déjà appliqué par `DrivyAPIClient.accessToken()`).
5. **Renouvellement unique sur 401.** Au plus un nouvel essai, avec le **même** corps, la **même** URL, le **même** `mediaID`, lié au jeton invalidé. Aucun nouvel essai si la source ne renouvelle rien, ni après un second 401.
6. **Aucun renouvellement automatique** sur délai dépassé, 5xx, 404 ou 409 ; aucune nouvelle clé, aucun nouveau chiffré, aucun nouvel identifiant.
7. **Annulation appelante.** `CancellationError` reste une annulation : ni panne (`unavailable`) ni succès.
8. **Wire dédié.** `URLSessionConfiguration.ephemeral`, délais 20/30 s (identiques au transport existant), délégate `MessagingMediaNoRedirects` qui répond `nil` à toute redirection, même de même hôte.
9. **Garanties indépendantes de la configuration injectée.** `MessagingMediaURLSessionTransport.harden(_:)` retire cache, stockage de cookies, envoi de cookies et réutilisation d'une réponse locale **quel que soit** l'objet `URLSessionConfiguration` reçu, puis l'initialiseur crée la session. Un appelant (tests `URLProtocol`) ne peut donc pas réactiver ces comportements par inadvertance.
10. **Lecture bornée avant allocation.** `Content-Length` déclaré au-delà du plafond → refus immédiat ; `expectedContentLength` au-delà → refus ; pendant la lecture, refus dès que la taille atteint le plafond. `reserveCapacity` n'est appelé qu'avec une longueur déjà bornée. Aucun `data(for:)` (vérifié, §10).
11. **Arrêt effectif du flux.** Toute sortie prématurée (en-tête refusé, dépassement pendant la lecture, annulation appelante) appelle `bytes.task.cancel()` — la tâche `URLSessionDataTask` qui alimente **ce** flux (`URLSession.AsyncBytes.task`, iOS 15+, [documentation Apple](https://developer.apple.com/documentation/foundation/urlsession/asyncbytes/task) ; [`URLSessionTask.cancel()`](https://developer.apple.com/documentation/foundation/urlsessiontask/cancel())). Aucune autre requête du même transport n'est annulée : ni la session (`invalidateAndCancel`) ni une tâche partagée ne sont touchées.
12. **Dépôt.** Refus local de `0` octet et de `> 4 194 304` **avant réseau** ; cohérence du sceau T2a (`info.validatedMaterial()`, hash du chiffré) vérifiée avant émission ; puis vérification exacte de `mediaId`, `byteSize`, `sha256`, de l'état (`UPLOADED`/`ATTACHED`, `PURGED` refusé) et du contexte.
13. **Téléchargement.** Type `application/octet-stream`, URL finale exacte, école et époque identiques au scope, `Content-Length` présent, égal au corps et dans `1…4 194 304`, SHA-256 hex64 égal au corps. Rien de partiel n'est rendu ; aucune écriture disque.
14. **Annulation.** Succès **seulement** après `200` cohérent (`mediaId`, `deleted: true`, contexte). `409 MEDIA_ALREADY_ATTACHED` n'est jamais un succès ; `404` et délai dépassé restent des refus honnêtes. Aucune suppression locale d'intention dans ce transport.

Le hash HTTP ne prouve **que** la correspondance au dépôt : l'authenticité vient de l'enveloppe Megolm et sera vérifiée par `MessagingMediaCryptography.open` chez le futur consommateur. Une réponse binaire d'un autre média/contexte est refusée par les contrôles disponibles (URL, école, époque, taille, hash) et, au-delà, par l'intégrité Megolm. Aucun en-tête `actor` n'est inventé pour le `GET` : il n'existe pas au contrat.

## 5. Diagnostics (vocabulaire figé)

Collecteur existant injecté (`MessagingDiagnostics`, `recordIfEmpty` : un seul code par tentative, la cause d'abord). Aucun chemin, identifiant, hash, clé, URL, réponse brute ni message libre.

| Situation | Code |
|---|---|
| Taille locale refusée (dépôt), `413` | `MEDIA-PUT-M-SIZE` |
| Sceau/hash local incohérent, hash de reçu mal formé | `MEDIA-PUT-M-HASH` |
| Appareil invalide (dépôt/téléchargement/annulation) | `MEDIA-<OP>-M-DEVICE` |
| `409 MEDIA_PURGED` | `MEDIA-PUT-M-PURGED` |
| `mediaId`/taille/hash du reçu différents | `MEDIA-PUT-M-INTEGRITY` |
| Enveloppe, type, statut, URL, contexte invalides ; `409` non nommé, `409 ATTACHED` | `MEDIA-<OP>-M-STATE` |
| Taille déclarée absente/fausse (téléchargement) | `MEDIA-GET-M-SIZE` |
| Hash d'en-tête absent/mal formé | `MEDIA-GET-M-HASH` |
| Hash du corps différent | `MEDIA-GET-M-INTEGRITY` |
| Panne réseau, 5xx, 408, 429, panne de la source de jeton | `MEDIA-PUT` / `MEDIA-GET` / `MEDIA-DELETE` (catégorie seule) |
| Réauthentification pendant l'attente du jeton | `MEDIA-PUT` / `MEDIA-GET` / `MEDIA-DELETE` (catégorie seule) |

`MessagingDiagnostics.isSafe` n'accepte que `A-Z`, `0-9`, `-`, 40 octets : tous les codes ci-dessus passent, et les tests vérifient qu'aucun identifiant, hash, URL ni sentinelle d'erreur n'y figure.

## 6. Ce que cette primitive ne dit pas (mapping laissé au futur worker UI)

La primitive expose **seulement** des cas fermés ; elle ne contient ni texte, ni couleur, ni icône, ni consigne d'écran. Le futur worker UI décidera de la présentation des cas suivants, sans que ce document ne fixe de copie :

- `invalidIntent` — refus local, rien n'est parti ;
- `contextChanged` — le contexte de session a changé ;
- `accessChanged`, `deviceRequired` — droits ou appareil ;
- `notFound`, `purged` — média absent ou supprimé définitivement ;
- `alreadyAttached` — l'annulation n'est plus possible ;
- `intentConflict`, `sizeConflict`, `stateConflict` — conflit d'intention ou d'état ;
- `unavailable` — panne, dont la source de jeton ;
- `invalidResponse`, `tooLarge`, `integrityMismatch` — réponse refusée, jamais rendue.

Aucun écran, aucun libellé et aucune activation produit ne sont ajoutés par ce lot.

## 7. Tests écrits (41)

`apps/ios/DrivyTests/MessagingHTTPMediaTransportTests.swift` (30) — fil injectable qui capture méthode, URL, en-têtes, corps et plafond, plus des compteurs de barrière (entrées dans la source de jeton, émissions) :

- dépôt du chiffré seul sous le chemin média, `Content-Length` exact, en-têtes de contexte, aucun nom/type/clé/IV ;
- `1` octet et `4 Mio` acceptés ; `0` et `4 Mio + 1` refusés avant réseau ;
- reçu `UPLOADED` et `ATTACHED` ; faux `mediaId`, taille, hash, hash mal formé, `PURGED`, état inconnu ; contexte étranger ; statut 201, type texte, corps vide, enveloppe partielle ;
- sceau incohérent refusé avant réseau ; appareil invalide refusé avant réseau pour les trois opérations ;
- douze refus serveur mappés distinctement sans second essai ; `500/408/429` non rejoués ; panne de fil → `unavailable` ;
- `401` une fois avec les **mêmes** octets et la **même** URL ; pas de second essai si renouvellement impossible ou second 401 ;
- **changement de contexte pendant l'invalidation du jeton** : `contextChanged`, **une** émission, **une** entrée dans la source de jeton, aucun renouvellement ;
- **tâche déjà annulée** : `CancellationError`, **zéro** entrée dans la source de jeton, **zéro** émission ;
- **échecs de la source de jeton** : panne (NSError à sentinelle) → `unavailable`, réauthentification → `accessChanged`, annulation → `CancellationError`, sans qu'aucune sentinelle ne traverse le cas d'erreur ;
- annulation : `CancellationError` et `URLError.cancelled` restent des annulations ;
- origine/base refusées avant réseau ; changement de compte, d'école et d'époque pendant la réponse → jamais rendu ;
- téléchargement : succès vérifié, en-têtes absents/incohérents, taille absente/fausse/nulle/hors plafond, corps corrompu, type/URL/statut, `403` appareil vs droits, renouvellement unique ;
- annulation : `200` cohérent ; `409 ATTACHED`, `PURGED`, `404`, `503` ; `deleted:false`, identifiant étranger, contexte étranger, `204` ;
- diagnostics : quatre codes fixes réellement enregistrés, sans identifiant/hash/URL/sentinelle.

`apps/ios/DrivyTests/MessagingMediaURLSessionTransportTests.swift` (11) — vrai wire sur `URLProtocol` local :

- plafond média **dérivé de la constante** : `mediaLimit` accepté, `mediaLimit + 1` refusé (plus aucune valeur saisie à la main) ;
- plafond de flux strictement supérieur à la limite métier, et identité des deux constantes de 4 Mio ; `4 194 305` lisible par le wire ;
- plafond d'enveloppe : 900 octets, `envelopeLimit` exactement accepté, `envelopeLimit + 1` refusé ;
- flux sans longueur déclarée au-delà du plafond média → refus pendant la lecture ;
- en-têtes nommés lus (école, époque, hash, type), `Set-Cookie` non conservé ;
- **flux laissé ouvert** (en-têtes + prélude, aucun `didFinishLoading`) : en-tête refusé, dépassement pendant la lecture et annulation appelante provoquent chacun `stopLoading`, observé par attente conditionnelle bornée ; succès normal lu et rendu ;
- configuration injectée hostile (cache, cookies, politique de cache) : les garanties sont rétablies par `harden` ;
- la délégate de redirection répond toujours `nil`.

**Limites de méthode, explicitement assumées :** un `URLProtocol` remet le corps depuis la mémoire locale. Ces tests prouvent la boucle de lecture bornée, l'appel d'annulation de la tâche et le refus de redirection ; ils ne mesurent **ni** le débit réseau réel **ni** une fuite mémoire, et `stopLoading` est le seul signal observable de l'arrêt. Un flux non annulé laisserait le test échouer par délai borné, jamais le figer.

## 8. Ce qui n'a PAS été exécuté

**NON EXÉCUTÉ — aucun outil Apple sur ce poste (Windows).** Aucun test Swift de ce lot n'a été compilé ni exécuté ; aucun RED/GREEN Swift n'est revendiqué. Les 41 tests sont écrits et relus, pas prouvés. La correction du §13 vient d'une revue source et d'arithmétique, **pas** d'un test natif rouge.

À lancer sur un runner Apple, au SHA de livraison exact :

```bash
xcodebuild test \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DrivyTests/MessagingHTTPMediaTransportTests \
  -only-testing:DrivyTests/MessagingMediaURLSessionTransportTests \
  -derivedDataPath artifacts/ios/DerivedData
```

La sélection `DRIVY_IOS_UNIT_TEST_SCOPE=messaging` de `scripts/ios/test-selection.sh` **n'inclut pas** ces deux classes : ce fichier appartient à un autre lot et n'a pas été modifié. Tant que son propriétaire ne les ajoute pas, seul le `-only-testing` ci-dessus les exécute.

Non vérifiable ici : comportement réel de `URLSession.AsyncBytes` sous `URLProtocol` (délivrance du prélude, appel de `stopLoading` sur annulation), respect de `Content-Length` fourni par un `URLProtocol`, stricte conformité Swift 6 (`SWIFT_STRICT_CONCURRENCY: complete`), et le fait que l'itération asynchrone rende bien la main à l'annulation.

## 9. Modèle, skills, Codebase Memory réellement utilisés

- **Modèle** : `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans paramètre de modèle ni d'effort. La révision 1017 et l'effort ne sont pas exposés par ce runtime : **non vérifiables** ici.
- **Skills Superpowers chargés (outil `skill`, réellement), sur les deux passes :**
  - `test-driven-development` — base `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development` : tests écrits **avant** l'implémentation, y compris pour cette correction (fixtures et tests d'arrêt de flux ajoutés avant la modification du wire). La boucle RED → GREEN reste **non exécutée** faute de compilateur Swift.
  - `systematic-debugging` — base `…\superpowers\skills\systematic-debugging` : les quatre constats ont été reproduits en source (arithmétique du plafond, sorties sans annulation, attente non gardée, textes dans la primitive) avant toute modification.
  - `verification-before-completion` — base `…\superpowers\skills\verification-before-completion` : chargé avant la livraison ; il interdit de présenter le lot comme compilé ou testé, ce que ce document respecte.
  - Aucun sous-agent, aucune revue indépendante simulée, aucun autre skill invoqué.
- **Codebase Memory** : projet **unique** de ce worktree, `drivy-t2b2-media-transport-97-20261104`. Réindexé pour cette correction : `index_status` → racine `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-transport-97`, `status: ready`, `indexed_at: 2026-11-04T18:27:13Z`, 39 173 nœuds / 168 325 arêtes.
  - `search_graph` : `MessagingHTTPMediaTransport`, `MessagingMediaTransportFailure`, `MessagingMediaHTTPWire` — les quatre fichiers du lot sont dans l'index.
  - `check_index_coverage` : 4/4 fichiers du lot en `no_recorded_issue` + `metadata_match`, `generation_matches: true`.
  - Lacunes assumées : 18 `parse_partial` hors périmètre, `openapi.yaml` non analysable, répertoires exclus par `.gitignore`.

## 10. Commandes réellement exécutées (Windows, sans Swift)

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `git rev-parse HEAD` | `b4ec0dca16e2…` (candidat relu) | 0 |
| 2 | `index_repository` + `index_status` (MCP, chemin absolu) | racine du worktree, `ready`, 39 173 nœuds | 0 |
| 3 | `search_graph` ×3 + `check_index_coverage` | 4 fichiers du lot indexés, 4/4 sans anomalie | 0 |
| 4 | `webfetch` documentation Apple (`AsyncBytes.task`, `URLSessionTask.cancel()`) | `var task: URLSessionDataTask { get }` (iOS 15+) ; `func cancel()` | 0 |
| 5 | `Select-String 'LocalizedError\|errorDescription'` sur la primitive | aucune occurrence | 0 |
| 6 | `Select-String 'task.cancel()\|bytes.task'` sur le wire | 1 obtention de tâche + 5 annulations sur sortie prématurée | 0 |
| 7 | `Select-String 'harden\|Self.harden'` | 1 définition + 1 application dans l'initialiseur ; le test de configuration hostile est écrit, **non exécuté** | 0 |
| 8 | `Select-String 'data\(for:'` | aucune occurrence | 0 |
| 9 | `Select-String 'maximumResponseBytes = '` dans `DrivyAPIClient.swift` | `2 * 1_024 * 1_024` (inchangé) | 0 |
| 10 | Python jetable : équilibre des délimiteurs des 4 fichiers | 4 × `balanced` | 0 |
| 11 | `git status --porcelain` | 5 fichiers du lot, aucun autre | 0 |
| 12 | Python jetable : arithmétique des trois bornes (`4 194 304` / `4 202 496` / `16 384`) | ancienne fixture `4 200 000` **inférieure** à `4 202 496` → le test précédent attendait un refus à tort | 0 |
| 13 | `Select-String '4200000'` dans les tests de wire | aucune valeur saisie à la main ne subsiste | 0 |

**Correction d'une affirmation de la livraison précédente.** Le « port Python jetable » annoncé avec « 66 vérifications, 0 échec » ne modélisait **que** les tables de décision de l'adaptateur (statuts, reçu, téléchargement, annulation) : il ne touchait ni les constantes du wire, ni ses fixtures, et ne pouvait donc pas détecter `Content-Length: 4200000` sous le plafond `4202496`. Il n'a jamais été, et ne doit pas être lu comme, une couverture du wire. Aucun port Python n'est présenté ici comme un test Swift : les seules preuves réelles sont les lignes de ce tableau, et le reste est **à exécuter sur Apple**.

## 11. Fichiers

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaTransport.swift` | protocole §4.5, reçu typé, erreurs typées sans présentation |
| `apps/ios/Drivy/MessagingAPI/MessagingHTTPMediaTransport.swift` | adaptateur, wire URLSession dédié durci, arrêt de la tâche de flux, mapping fermé du jeton, délégate sans redirection |
| `apps/ios/DrivyTests/MessagingHTTPMediaTransportTests.swift` | 30 tests de l'adaptateur sur fil injecté, compteurs de barrière |
| `apps/ios/DrivyTests/MessagingMediaURLSessionTransportTests.swift` | 11 tests du vrai wire via `URLProtocol`, dont flux laissé ouvert |
| `docs/implementation/messaging-media-97-transport.md` | ce document |

Aucune dépendance, aucun lockfile, aucun `project.yml` (sources par répertoire), aucun workflow, aucun fichier partagé (`SchoolAPI`, `MessagingHTTPTransport`, `MessagingCryptoRelay`, diagnostics global, authentification), aucune primitive crypto, aucun contenu v3, aucun store/coffre/outbox/factory/UI, aucune API/SQL, aucun `STATUS.md`, aucune conception modifiés.

## 12. Risques et limites honnêtes

- **Aucune preuve Apple** : compilation, tests, conformité Swift 6, comportement réel de `URLProtocol`/`AsyncBytes` restent à qualifier. Le code peut ne pas compiler.
- **`stopLoading` n'est pas une preuve de fin de consommation réseau** : il prouve que la tâche a été marquée annulée et que la couche URL a clôturé le chargement ; la fermeture de la socket n'est pas observable dans ces tests.
- **Configuration mutée** : `harden` modifie l'objet `URLSessionConfiguration` reçu (type référence). C'est voulu et documenté, mais un appelant qui réutiliserait la même configuration pour une autre session verrait ses réglages de cache/cookies retirés.
- **Le hash HTTP n'est pas une authentification** : il ne vaut que relativement au dépôt ; l'authenticité exige Megolm côté consommateur.
- **`X-Drivy-Device-Id` déclaré** : la révocation garantit le refus de cet identifiant, pas l'impossibilité de se présenter avec un autre appareil actif du compte.
- **Téléchargement concurrent du dépôt** : `GET` exige `ATTACHED`; un média encore `UPLOADED` répond `404`.
- **Pas de reprise ici** : la conservation de l'intention et du `mediaID` appartient au lot outbox.
- **Délais 20/30 s** identiques au transport existant : un dépôt de 4 Mio sur un lien lent peut expirer, et c'est un `unavailable` honnête.
- **Diagnostics** : un seul code par tentative (première cause).
- **Portée** : la sélection CI `messaging` ne couvre pas encore ces deux classes.
- **Primitive non branchée** : aucun envoi utilisateur complet, aucun coffre, aucune UI.

## 13. Correction 1 (revue du coordinateur)

| # | Constat | Cause racine | Correction |
|---|---|---|---|
| 1 | `testDeclaredLengthAboveTheMediaCeilingIsRefusedBeforeAnyAccumulation` attendait un refus pour `Content-Length: 4200000`, **inférieur** au plafond `4 194 304 + 8 192 = 4 202 496` | valeur saisie à la main au lieu d'être dérivée de la constante | tests réécrits : `mediaLimit` accepté, `mediaLimit + 1` refusé, `envelopeLimit` exactement accepté puis `+ 1` refusé, et distinction explicite entre plafond de flux (`4 202 496`) et limite métier (`4 194 304`, dont `4 194 305` reste lisible par le wire). Aucune limite correcte n'a été réduite. |
| 2 | le wire sortait par `throw` sans annuler la tâche du flux | aucun accès à la tâche sous-jacente | `let task = bytes.task` puis `task.cancel()` sur : en-tête refusé, longueur réseau trop grande, dépassement pendant la lecture, annulation appelante. Portée limitée à cette tâche — ni la session ni d'autres requêtes ne sont annulées. Tests : `URLProtocol` qui laisse le flux **ouvert** après en-têtes et prélude et compte `stopLoading`. |
| 3 | `exchange` ne recontrôlait pas le scope entre `await invalidate` et `await token` ; les erreurs de `token()` sortaient brutes | enchaînement direct des deux attentes, pas de mapping fermé | `Task.checkCancellation()` + `verifyCurrent` après l'invalidation et avant tout renouvellement ; `accessToken(scope:operation:)` fermé (annulation préservée, erreurs typées préservées, réauthentification → `accessChanged`, reste → `unavailable`) ; `checkCancellation` à l'entrée de `start`. Tests à compteurs : changement pendant l'invalidation → 1 émission, 1 entrée dans la source de jeton ; tâche déjà annulée → 0 et 0 ; sentinelle `NSError` jamais transportée ; `MEDIA-PUT` en diagnostic. |
| 4 | textes d'interface dans la primitive | `LocalizedError` + `errorDescription` (15 libellés) | conformance et propriété supprimées ; cas fermés conservés ; §6 réécrit sans aucune copie, le mapping restant au futur worker UI. |

Complément demandé : la configuration injectée ne peut plus réactiver cache ou cookies (`harden`), sans élargir la surface publique (la méthode reste interne, comme l'initialiseur utilisé par les tests).

Budget de corrections : **1 sur 2** consommée.
