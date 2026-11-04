# Médias #97 — T2b2 : transport binaire natif, borné et lié au contexte

Base : branche de travail `tomyrms/issues-medias-transport-97`, commit `883581ad321b` (T2a : primitive crypto validée par 15 tests Apple, `aedc1f0f` + `883581ad`). Personne n'a modifié d'autre fichier que ceux listés au §11.

Ce lot livre **une primitive de transport**. Il n'est branché ni à la file d'attente média, ni au coffre, ni au contenu v3, ni à l'UI : aucun envoi utilisateur complet n'est livré, aucun écran n'est activé. Le transport média est un frère de `MessagingHTTPTransport.request` : même jeton, mêmes en-têtes de contexte, même renouvellement sur 401, mais corps et réponse binaires.

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

enum MessagingMediaTransportFailure: Error, Equatable, Sendable, LocalizedError {
    case invalidIntent, contextChanged, accessChanged, deviceRequired, notFound, purged,
         alreadyAttached, intentConflict, sizeConflict, stateConflict, unavailable,
         invalidResponse, integrityMismatch, tooLarge
}
```

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

Ni nom, ni type MIME, ni clé, ni IV, ni miniature, ni légende n'apparaissent dans l'URL, les en-têtes ou le corps : les octets déposés sont le chiffré seul (test dédié, §7).

## 4. Garanties mises en œuvre

1. **Scope complet avant et après chaque attente.** `verifyCurrent` compare `MessagingScope` (compte, école, époque, URL d'API) avant le jeton, après le jeton, avant chaque émission, après la réponse, avant un second essai, et `start` vérifie aussi après l'attente de `DrivyAPIClient.permits`. Une réponse tardive d'un contexte quitté lève `contextChanged` et n'est jamais rendue.
2. **Jeton.** Porteur non vide, ASCII `> 32 && < 127` : un jeton contenant un CR/LF n'est jamais émis.
3. **Renouvellement unique sur 401.** Au plus un nouvel essai, avec le **même** corps, la **même** URL, le **même** `mediaID`, lié au jeton invalidé. Aucun nouvel essai si la source ne renouvelle rien (`invalidate` faux) ni après un second 401.
4. **Aucun renouvellement automatique** sur délai dépassé, 5xx, 404 ou 409 ; aucune nouvelle clé, aucun nouveau chiffré, aucun nouvel identifiant.
5. **Annulation.** `CancellationError` reste une annulation : ni panne (`unavailable`) ni succès.
6. **Wire dédié.** `URLSessionConfiguration.ephemeral`, `urlCache = nil`, aucun cookie, `reloadIgnoringLocalCacheData`, délais 20/30 s (identiques au transport existant), délégate `MessagingMediaNoRedirects` qui répond `nil` à toute redirection, même de même hôte.
7. **Lecture bornée avant allocation.** `Content-Length` déclaré au-delà du plafond → refus immédiat ; `expectedContentLength` au-delà → refus ; pendant la lecture, refus dès que la taille atteint le plafond. `reserveCapacity` n'est appelé qu'avec une longueur déjà bornée. Aucun `data(for:)` (vérifié, §10).
8. **Dépôt.** Refus local de `0` octet et de `> 4 194 304` **avant réseau** ; cohérence du sceau T2a (`info.validatedMaterial()`, hash du chiffré) vérifiée avant émission ; puis vérification exacte de `mediaId`, `byteSize`, `sha256` et de l'état (`UPLOADED`/`ATTACHED`, `PURGED` refusé) et du contexte.
9. **Téléchargement.** Type `application/octet-stream`, URL finale exacte, école et époque identiques au scope, `Content-Length` présent, égal au corps et dans `1…4 194 304`, SHA-256 hex64 égal au corps. Rien de partiel n'est rendu ; aucun cache n'est écrit (le transport n'écrit rien sur disque).
10. **Annulation.** Succès **seulement** après `200` cohérent (`mediaId`, `deleted: true`, contexte). `409 MEDIA_ALREADY_ATTACHED` n'est jamais un succès ; `404` et délai dépassé restent des refus honnêtes. Aucune suppression locale d'intention dans ce transport.

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
| Panne réseau, 5xx, 408, 429 | `MEDIA-PUT` / `MEDIA-GET` / `MEDIA-DELETE` (catégorie seule) |

`MessagingDiagnostics.isSafe` n'accepte que `A-Z`, `0-9`, `-`, 40 octets : tous les codes ci-dessus passent, et les tests vérifient qu'aucun identifiant/hash/URL n'y figure.

## 6. Mapping UI prévu (non implémenté, aucun écran activé)

| Échec | Intention d'affichage future |
|---|---|
| `invalidIntent` | « Cette pièce jointe ne peut pas être envoyée » (taille, format) — rien n'est parti |
| `contextChanged` | « Recharge Messages » |
| `accessChanged` | « L'accès à cette conversation a changé » |
| `deviceRequired` | « Cet appareil n'est plus autorisé » (réenregistrement d'appareil à décider) |
| `notFound` | « Pièce jointe introuvable » |
| `purged` | « Pièce jointe supprimée » — jamais ressuscitée |
| `alreadyAttached` | « Déjà envoyée : impossible de l'annuler » |
| `intentConflict` / `sizeConflict` | conflit d'intention : conserver l'intention, ne pas rechiffrer |
| `stateConflict` | « Cette pièce jointe a changé » |
| `unavailable` | « Momentanément indisponible, réessaie plus tard » |
| `invalidResponse` / `tooLarge` | réponse refusée ; aucun rendu |
| `integrityMismatch` | « Fichier illisible » ; nouvelle tentative possible |

Ce tableau est une note de conception : aucun texte n'est ajouté à l'UI dans ce lot.

## 7. Tests écrits (32)

`apps/ios/DrivyTests/MessagingHTTPMediaTransportTests.swift` (27) — fil injectable qui capture méthode, URL, en-têtes, corps et plafond :

- dépôt du chiffré seul sous le chemin média, `Content-Length` exact, en-têtes de contexte, aucun nom/type/clé/IV ;
- `1` octet et `4 Mio` acceptés ; `0` et `4 Mio + 1` refusés avant réseau ;
- reçu `UPLOADED` et `ATTACHED` ; faux `mediaId`, taille, hash, hash mal formé, `PURGED`, état inconnu ; contexte étranger ; statut 201, type texte, corps vide, enveloppe partielle ;
- sceau incohérent refusé avant réseau ; appareil invalide refusé avant réseau pour les trois opérations ;
- douze refus serveur mappés distinctement sans second essai ; `500/408/429` non rejoués ; panne de fil → `unavailable` ;
- `401` une fois avec les **mêmes** octets et la **même** URL ; pas de second essai si renouvellement impossible ou second 401 ;
- annulation : `CancellationError` et `URLError.cancelled` restent des annulations ;
- origine/base refusées avant réseau ; changement de compte, d'école et d'époque pendant l'attente → jamais rendu ; changement pendant le renouvellement ;
- téléchargement : succès vérifié, en-têtes absents/incohérents, taille absente/fausse/nulle/hors plafond, corps corrompu, type/URL/statut, `403` appareil vs droits, renouvellement unique ;
- annulation : `200` cohérent ; `409 ATTACHED`, `PURGED`, `404`, `503` ; `deleted:false`, identifiant étranger, contexte étranger, `204` ;
- diagnostics : quatre codes fixes réellement enregistrés, sans identifiant/hash/URL.

`apps/ios/DrivyTests/MessagingMediaURLSessionTransportTests.swift` (5) — vrai wire sur `URLProtocol` local :

- `Content-Length` déclaré au-delà du plafond média → `tooLarge` avant accumulation ;
- plafond d'enveloppe (16 Kio) plus strict que celui du média, 900 octets acceptés ;
- flux sans longueur déclarée au-delà de 4 Mio + 8 Kio → `tooLarge` pendant la lecture ;
- en-têtes nommés lus (école, époque, hash, type), `Set-Cookie` non conservé ;
- la délégate de redirection répond toujours `nil`.

**Limite de méthode, explicitement assumée :** un `URLProtocol` remet un corps déjà en mémoire locale. Ces tests prouvent la **boucle de lecture bornée** et le refus de redirection, pas la cadence réelle du réseau ni une allocation progressive au niveau transport. Aucun test ne prétend mesurer cela.

## 8. Ce qui n'a PAS été exécuté

**NON EXÉCUTÉ — aucun outil Apple sur ce poste (Windows).** Aucun test Swift de ce lot n'a été compilé ni exécuté ; aucun RED/GREEN Swift n'est revendiqué. Le run crypto `883581ad` ne contient pas ces fichiers. Les 32 tests sont écrits et relus, pas prouvés.

À lancer sur un runner Apple, au SHA de livraison exact :

```bash
xcodebuild test \
  -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:DrivyTests/MessagingHTTPMediaTransportTests \
  -only-testing:DrivyTests/MessagingMediaURLSessionTransportTests \
  -derivedDataPath artifacts/ios/DerivedData
```

La sélection `DRIVY_IOS_UNIT_TEST_SCOPE=messaging` de `scripts/ios/test-selection.sh` **n'inclut pas** ces deux classes : ce fichier appartient à un autre lot et n'a pas été modifié. Tant que son propriétaire ne les ajoute pas, seul le `-only-testing` ci-dessus les exécute. C'est un suivi à inscrire, pas un résultat.

Non vérifiable non plus ici : comportement réel de `URLSession.AsyncBytes` sous `URLProtocol`, respect de `Content-Length` fourni par un `URLProtocol`, stricte conformité Swift 6 (`SWIFT_STRICT_CONCURRENCY: complete`) — seuls un compilateur Apple et un simulateur le diront.

## 9. Modèle, skills, Codebase Memory réellement utilisés

- **Modèle** : `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash), sans paramètre de modèle ni d'effort. La révision 1017 et l'effort ne sont pas exposés par ce runtime : **non vérifiables** ici.
- **Skills Superpowers chargés (outil `skill`, réellement) :**
  - `test-driven-development` — base `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development` : tests écrits **avant** l'implémentation. Sa boucle RED → GREEN n'a **pas** pu être honorée faute de compilateur Swift ici ; c'est déclaré au §8, pas contourné.
  - `verification-before-completion` — base `…\superpowers\skills\verification-before-completion` : chargé avant la livraison et appliqué à la passe de vérification du §10. Sa règle « pas de claim de succès sans sortie fraîche » interdit de présenter ce lot comme compilé ou testé : aucun succès Swift n'est revendiqué.
  - Aucun sous-agent, aucune revue indépendante simulée, aucun autre skill invoqué.
- **Codebase Memory** : projet **unique** créé pour ce worktree, `drivy-t2b2-media-transport-97-20261104`, via `index_repository(repo_path: "C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-transport-97", mode: "moderate")`. `index_status` : racine `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-transport-97`, `status: ready`, `indexed_at: 2026-11-04T17:16:09Z`, 38 992 nœuds / 166 832 arêtes.
  - `search_graph` : `MessagingMedia.*`, `MessagingScope`, `MessagingHTTPTransport`, `SchoolHTTPResponse`, `MessagingDiagnostics`.
  - `trace_path` : `MessagingSealedMedia` → 1 appelant (`AESCTRMediaCryptography.seal`) ; `SchoolURLSessionTransport` → 29 appelants (motif du transport dédié plutôt que d'un élargissement).
  - `check_index_coverage` : 6 des 7 fichiers consultés en `no_recorded_issue` + `metadata_match` ; `apps/ios/Drivy/SchoolAPI/DrivyAPIClient.swift` en `partial` (lignes 53-57, 319) — source lue directement, comme recommandé.
  - Lacunes assumées : 18 `parse_partial` hors périmètre, `openapi.yaml` non analysable, répertoires exclus par `.gitignore`. Aucun index d'un autre worktree n'a été utilisé pour conclure sur ce lot (le projet `drivy-issues-medias-97` existe mais n'a pas été interrogé pour ce travail).

## 10. Commandes réellement exécutées (Windows, sans Swift)

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `git rev-parse --short=12 HEAD` | `883581ad321b` (base attendue) | 0 |
| 2 | `git status --porcelain` | 4 fichiers, tous autorisés et nouveaux | 0 |
| 3 | `Select-String … 'data\(for:'` sur `MessagingHTTPMediaTransport.swift` | aucune occurrence | 0 |
| 4 | `Select-String … 'maximumResponseBytes = '` dans `DrivyAPIClient.swift` | `2 * 1_024 * 1_024` (inchangé) | 0 |
| 5 | Python jetable : équilibre des délimiteurs des 4 fichiers (chaînes et commentaires neutralisés) | 4 × `balanced` | 0 |
| 6 | Python jetable : port des tables de décision (statuts, reçu, téléchargement, annulation, code sûr) comparé aux attentes des 32 tests | 66 vérifications, **0 échec** | 0 |
| 7 | `Select-String … 'XCTAssert[^\n]*await'` | aucun `await` dans une autoclosure | 0 |

La ligne 6 ne compile ni n'exécute Swift : elle vérifie seulement que les règles transposées et les attentes écrites ne se contredisent pas. Elle ne remplace pas la ligne absente : `xcodebuild test`.

## 11. Fichiers

| Fichier | Rôle |
|---|---|
| `apps/ios/Drivy/MessagingCore/MessagingMediaTransport.swift` | protocole §4.5, reçu typé, erreurs typées |
| `apps/ios/Drivy/MessagingAPI/MessagingHTTPMediaTransport.swift` | adaptateur, wire URLSession dédié, types de réponse/plafond, délégate sans redirection |
| `apps/ios/DrivyTests/MessagingHTTPMediaTransportTests.swift` | 27 tests de l'adaptateur sur fil injecté |
| `apps/ios/DrivyTests/MessagingMediaURLSessionTransportTests.swift` | 5 tests du vrai wire via `URLProtocol` |
| `docs/implementation/messaging-media-97-transport.md` | ce document |

Aucune dépendance, aucun lockfile, aucun `project.yml` (sources par répertoire), aucun workflow, aucun fichier partagé (`SchoolAPI`, `MessagingHTTPTransport`, `MessagingCryptoRelay`, diagnostics global), aucune primitive crypto, aucun contenu v3, aucun store/coffre/outbox/factory/UI, aucune API/SQL, aucun `STATUS.md`, aucune conception modifiés.

## 12. Risques et limites honnêtes

- **Aucune preuve Apple** : compilation, tests, conformité Swift 6, comportement réel de `URLProtocol`/`AsyncBytes` restent à qualifier. Le code peut ne pas compiler.
- **Primitive non branchée** : aucune intention scellée persistée, aucune file, aucun coffre, aucun contenu v3. Un envoi utilisateur complet n'existe pas.
- **Le hash HTTP n'est pas une authentification** : il ne vaut que relativement au dépôt ; l'authenticité exige Megolm côté consommateur.
- **`X-Drivy-Device-Id` déclaré** : la révocation garantit le refus de cet identifiant, pas l'impossibilité de se présenter avec un autre appareil actif du compte.
- **Téléchargement concurrent du dépôt** : `GET` exige `ATTACHED`; un média encore `UPLOADED` répond `404` (comportement serveur, pas une erreur du transport).
- **Pas de reprise ici** : la conservation de l'intention et du `mediaID` appartient au lot outbox ; ce transport ne crée ni ne recrée jamais d'identifiant.
- **Délais 20/30 s** identiques au transport existant : un dépôt de 4 Mio sur un lien lent peut expirer, et c'est un `unavailable` honnête, sans nouvel essai.
- **Diagnostics** : un seul code par tentative (première cause), comme le collecteur existant ; un second échec du même écran n'est pas visible séparément.
- **Portée** : la sélection CI `messaging` ne couvre pas encore ces deux classes (fichier d'un autre lot).
