# G2 — capture privée rattachée à une leçon

Cette tranche implémente le cycle serveur d'une capture réelle explicitement démarrée : information et choix, diagnostic, autorisation, lots chiffrés, arrêt, finalisation et replay privé. Elle n'active pas un collecteur natif, ne qualifie aucun appareil physique et ne partage aucune géométrie avec l'élève. Les séances locales G0 et les parcours `EXAMPLE` restent séparés ; il n'existe aucun import automatique de leur historique.

Références conservées : [F15/F16](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/gps-replay.md), [R41–45, R83–84, R101, R111](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md), [synchronisation](../../Drivy_Conception_v3_17_2026-09-20/04-technique/synchronisation.md), [transactions](../../Drivy_Conception_v3_17_2026-09-20/04-technique/transactions-v2.md), [OpenAPI 3.11.0](../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml). Aucun document canonique modifié.

## Les six points READY

1. **Action utilisateur** : le moniteur désigné et encore affecté demande l'autorisation d'une leçon planifiée ; l'élève confirme un choix `SELF`, ou le moniteur consigne un choix réellement exprimé `RECORDED_VERBAL`. Le choix ne découle jamais du réglage scolaire. Le collecteur devra s'arrêter localement avant AP157, même sans réseau.
2. **Source de vérité** : PostgreSQL pour droits courants, choix append-only, diagnostic, bail, identités de lots, manifeste et accusés. Une signature ne remplace ni la session OIDC courante, ni la vérification des droits, ni les bornes conservées au serveur.
3. **Échec/concurrence** : verrous identité→école→ressources existants, trois contraintes d'unicité distinctes pour leçon/moniteur/appareil, clé d'opération durable, unicité capture/segment/chunk, exclusion des séquences qui se recouvrent. Même lot/même hash est acquitté sans duplication ; autre hash est refusé. Le refus SELF ne peut être levé par un accord verbal.
4. **Persistance minimale** : cinq tables ajoutées par `008_capture.sql` : `capture_installation`, `capture_device_assessment`, `recording_choice`, `capture_session`, `capture_chunk`. Les segments vides restent dans le manifeste JSON ; les segments reçus sont décrits dans les lots. Aucune table de position unitaire, de publication ou de télémétrie ajoutée.
5. **Contrat/UI** : corps et réponses canoniques AP152–158/160/190–191. Deux lectures supplémentaires documentées ci-dessous. La voie sans GPS reste disponible. L'état serveur `AUTHORIZED` ne signifie pas que le téléphone collecte actuellement.
6. **Preuve attendue** : compilation TypeScript et un parcours ciblé sur PostgreSQL avec vrai rôle runtime RLS, propriétaire de migrations sans superuser/BYPASSRLS/CREATEROLE, données synthétiques et clés éphémères. La recette physique iPhone/iPad, l'outbox native, le hash croisé Swift/JS et la recette réseau interrompu restent à réaliser avant activation du collecteur scolaire.

## Routes et reprise

Préfixe scolaire : `/v1/schools/{schoolId}`. Les réponses utilisent `{data,requestId,serverTime}`, `Cache-Control: no-store` et les erreurs métier existantes. Toutes les commandes exigent `Idempotency-Key = operationId`.

| API | Route | Concurrence | AP72 : commandType → resourceType |
|---|---|---|---|
| AP190 | POST `/devices/{deviceId}/assessments` | identité d'installation globale, 201 | `ASSESS_CAPTURE_DEVICE` → `DeviceAssessment` |
| AP191 | GET `/devices/{deviceId}/assessments/{assessmentId}` | propriétaire INSTRUCTOR, dernière évaluation valide | — |
| AP152 | GET `/learners/{learnerId}/recording-choice?lessonId=…` | aucun événement : 404 `RECORDING_CHOICE_NOT_SET` | — |
| AP153 | POST `/learners/{learnerId}/recording-choice` | append-only, version par dossier, 200 | `RECORD_RECORDING_CHOICE` → `RecordingChoice` |
| AP154 | POST `/lessons/{lessonId}/captures` | If-Match de Lesson, 201 | `START_CAPTURE` → `CaptureSession` |
| AP155 | GET `/captures/{captureId}` | projection courante privée | — |
| AP156 | PUT `/captures/{captureId}/segments/{segmentId}/chunks/{chunkIndex}` | sans If-Match, identité/hash, 200 | `UPLOAD_TRACK_CHUNK` → `CaptureSession` |
| AP157 | POST `/captures/{captureId}/stop` | sans If-Match ; borne monotone, 200 | `STOP_CAPTURE` → `CaptureSession` |
| AP158 | POST `/captures/{captureId}/finalize` | If-Match de CaptureSession, 200 | `FINALIZE_CAPTURE` → `CaptureSession` |
| AP160 | GET `/captures/{captureId}/replay` | curseur privé lié à reconstruction/personne/epoch | — |

AP72 garde la forme existante : auteur, opération, type, ressource et version, sans coordonnées ni preuve signée. Le receipt AP156 contient l'identité de lot, le hash, la date du premier accusé durable et `duplicate`. Un nouvel operationId sur un lot identique ne crée pas un deuxième lot. Les corps de commande ne sont pas enregistrés dans l'audit ; `Operation.response_data` ne contient ni points ni autorisation signée. Les preuves AP154 sont dérivées après commit à partir du bail durable. Une reprise retourne la capture courante ; une capture arrêtée/révoquée/expirée ne permet jamais un nouveau départ, même si une ancienne signature est encore valide.

**Extensions de lecture** :

- `GET /v1/capture-keys` : enveloppe `{data:{keys:[JWK public Ed25519]},requestId,serverTime}`. Le client fait confiance à l'origine API HTTPS configurée, jamais à une URL contenue dans un JWT.
- `GET /v1/schools/{schoolId}/recording-notice` : membre actif, enveloppe `{data:{noticeVersionId,noticeText,retentionText,contactEmail,approvedAt},requestId,serverTime}`. Cette lecture fournit la dernière notice effectivement adoptée avant un choix ; elle n'adopte rien.

AP159 retrait, AP161–164 observations et partage GPS AP54 ne sont pas implémentés par cette tranche. AP160 avec `reportRevisionId` répond 404 sans repli sur le privé. AP54 conserve son refus explicite de sélection GPS. `publicationState` reste `PRIVATE`.

## Autorité et configuration privée

`main.ts` appelle `readCaptureConfig()` puis passe `capture` à `buildApp`. Configuration facultative : son absence ne bloque pas l'API générale, donne un diagnostic `NEEDS_CHECK` et refuse AP154 avec `CAPTURE_SERVICE_NOT_CONFIGURED`.

| Variable | Valeur / usage |
|---|---|
| `CAPTURE_ENCRYPTION_KEY_HEX` | 32 octets aléatoires, encodage hexadécimal ; clé dédiée, différente de l'email, des curseurs et du coffre G0 |
| `CAPTURE_ENCRYPTION_KEY_ID` | identifiant technique de la clé, 1–80 caractères alphanumériques, `_`, `-` |
| `CAPTURE_SIGNING_PRIVATE_JWK` | JSON privé `kty=OKP`, `crv=Ed25519`, `x`, `d`, `kid` ; jamais distribué au client |
| `CAPTURE_AUTHORITY_ISSUER` | base API HTTPS exacte de confiance, par exemple `https://drivy.shulker.ch/refonte` |
| `CAPTURE_UPLOAD_HOURS` | délai après `expiresAt`, 1–168 heures, défaut 72 ; choix technique, pas politique de rétention |
| `CAPTURE_QUALIFICATION_PROFILES_JSON` | tableau de profils mesurés ; défaut `[]`, donc aucun matériel qualifié |

Chaque profil exige les clés `version`, `platform` (`IOS`/`ANDROID`), `deviceClass` (`PHONE`/`TABLET`), `modelCode`, `osVersion`, `appBuild`, `expiresAt`, `maxSampleAgeSeconds` (0–60), `maxHorizontalAccuracyMeters` (>0, ≤1000), `minimumFreeBytes`, `requireBackground`, `requirePreciseLocation`. Correspondance exacte, sans joker. La présence d'une carte ou d'une connexion n'est pas une preuve de localisation. Aucun profil de production n'est créé par une migration ou un test.

Le diagnostic expire après cinq minutes. Une évaluation plus récente remplace la précédente pour le départ, même si elle est moins favorable. Un diagnostic dégradé ou un changement appareil/système/build/profil révoque les baux actifs concernés. Le départ relit le profil, sa date, le diagnostic et son auteur. Les déclarations client ne sont pas une attestation anti-fraude.

Les JWT utilisent `alg=EdDSA`, `typ=drivy-capture+jwt`, `kid` configuré, `iss=CAPTURE_AUTHORITY_ISSUER`, `aud=drivy-native-capture`, `sub=Person.id`. Claims liés : `schoolId`, `captureId`, `lessonId`, `deviceId`, `deviceAssessmentId`, `authorizedAt`, `expiresAt`, `uploadDeadline`. `scope=capture:collect` expire à `expiresAt` ; `scope=capture:upload` expire à `uploadDeadline`. `iat` vient d'`authorizedAt`, `jti=captureId:scope`. Les secondes JWT sont arrondies vers le bas ; les dates métier conservent les millisecondes. AP156 vérifie signature, portée, expiration, auteur et toutes les identités liées, plus la session et les droits courants.

La fenêtre technique de départ va de trente minutes avant le début prévu à trente minutes après la fin prévue. Le bail finit au plus tard trois heures après sa délivrance, ou avant si le profil ou l'affectation expire. Il n'est pas repoussé par une réception, une relance ni un départ local tardif. Un bail expiré est libéré par une commande de départ, pas par mutation lors d'un GET.

La tranche utilise une clé active de signature et une clé active de chiffrement. Une rotation doit conserver l'accès aux données existantes et aux transferts autorisés ; le recouvrement multiclés/réchiffrement n'est pas livré. Ne pas remplacer ces clés en exploitation en supposant que les anciennes captures resteront lisibles. Une clé de chiffrement absente/incompatible produit `CAPTURE_KEY_UNAVAILABLE`, jamais un repli en clair.

## Chiffrement, lots et interruptions

Les points sont chiffrés en AES-256-GCM avec nonce aléatoire 96 bits et tag 128 bits avant INSERT. AAD : représentation canonique `{schoolId,captureId,segmentId,chunkIndex,hash}` ; UUID normalisés en minuscules. Changer école, capture, segment, indice ou hash empêche le déchiffrement. Le lot et son accusé sont dans la même transaction PostgreSQL : aucune fenêtre de désaccord avec un stockage objet séparé.

`contentHash` est le SHA-256 UTF-8 de `{segmentIndex,segmentStartedAt,segmentStartReason,points}` avec clés d'objet triées lexicographiquement, tableaux dans leur ordre et nombres rendus par `JSON.stringify` ECMAScript. `operationId` et `signedUploadAuthorization` sont exclus. Les chaînes de date sont conservées telles qu'envoyées dans ce hash. Les points d'un lot sont immuables ; ne pas reconstruire différemment la requête lors d'une reprise native.

Fixture numérique commune, entièrement synthétique :

```json
{"points":[{"accuracyMeters":1e+21,"capturedAt":"2026-09-24T12:00:00.001Z","elapsedMs":1,"latitude":0,"longitude":1e-7,"sequence":0}],"segmentIndex":0,"segmentStartReason":"START","segmentStartedAt":"2026-09-24T12:00:00.000Z"}
```

Hash : `65e7f15eec6b99ce5ca16137a146a690bfabab9017619f8c7657da69e30b1ecd`. Une latitude d'entrée `-0` devient `0`. La précision très grande éprouve seulement la sérialisation des exposants, sans représenter une mesure physique qualifiée.

Limites de cette tranche : 1000 points/lot, 512 Kio/requête AP156–158, 200 segments, 2000 lots et 100000 points par capture. Les indices de segment vont de 0 à 199 ; les indices de lot de 0 à 999. Les manifestes ont des identités et indices distincts et incluent explicitement les segments vides. Pas de séquence fictive pour un segment vide.

Le serveur refuse les précisions négatives/non finies, les séquences ou temps non croissants, les chevauchements entre lots ou segments, les positions antérieures au début et celles à/après la borne d'arrêt. `capturedAt - segmentStartedAt` correspond à `elapsedMs` à une milliseconde près, limite de représentation de cette implémentation ; ce n'est pas une tolérance GPS physique. Le mapping monotone/horloge du collecteur reste nécessaire. Une pause n'est pas interpolée : les raisons et indices de segments sont conservés. Le serveur ne peut pas prouver le moment d'une pause locale non transmis par le client.

Un arrêt conserve le manifeste scellé et resserre `cutoffAt`; un arrêt ultérieur ne peut pas l'allonger. Si des points ont déjà été reçus au-delà d'une nouvelle borne, le chiffrement du lot entier concerné est supprimé et la reconstruction devient partielle. Les identités/hashes/accusés restent des tombstones, sans coordonnées. Les points valides d'un tel lot ne sont pas réécrits sous l'ancien hash.

Des triggers de `008` bornent aussi les captures à la clôture/annulation de leçon, au refus connu, à la révocation de personne/appartenance/affectation, à la fermeture de formation/école, à la désactivation GPS et à une nouvelle notice. Une modification d'horaire/moniteur pendant un bail actif est bloquée en base. Le moniteur doit arrêter/reconcilier avant de déplacer la leçon ; ce refus de contrainte n'a pas encore de code métier spécifique dans AP42.

AP158 compare le manifeste aux lots reçus. Si des lots manquent : `CAPTURE_INCOMPLETE`, ou `PARTIAL` seulement après `allowPartial=true`. Une finalisation ferme les nouveaux uploads ; les doublons durables restent consultables. Un manifeste vide peut être `SYNCED`, sans prétendre qu'une position existe. Le replay ne remet jamais en continuité des segments distincts. `hasGapBefore` représente une vraie rupture disponible ; `continuesFromPreviousPage`/`continuesOnNextPage` représentent la pagination. Le paramètre `limit` respecte la borne OpenAPI de 100 points/page, malgré le plafond global de 1000 cité ailleurs dans la documentation. Le curseur est chiffré et lié à la version de reconstruction, l'acteur et son epoch ; un changement impose de repartir de la première page.

## Vérification effectuée

Le 24 septembre 2026 : `npm run typecheck --workspace @drivy/api` et `npm run build --workspace @drivy/api` réussis. `test/capture.integration.test.ts` contient une recette bornée ; aucune campagne générale supplémentaire. Elle a passé sur PostgreSQL **17.11**, port local dédié 55435, données synthétiques uniquement. Migrations 001–008 appliquées sous `drivy_capture_migrator` **NOSUPERUSER/NOBYPASSRLS/NOCREATEROLE** : **39/39 tables FORCE RLS**.

La recette vérifie : évaluation qualifiée synthétique et absence de profil réel, remplacement d'un diagnostic, choix SELF, preuves signées distinctes, un seul bail, lots arrivant hors ordre, chiffrement, doublons, absence d'accès privé ADMIN seul/élève, arrêt et finalisation, replay paginé, AP72 sans preuve signée, borne d'arrêt exclue et purge du lot touché, refus SELF protégé et révocation du bail actif. Ce résultat ne prouve ni une collecte physique native, ni un déploiement distant, ni un partage GPS élève.

Le test exige `TEST_DATABASE_URL` vers la base isolée `drivy_test`, comme les autres tests API, et remet uniquement son schéma à zéro. Exécution ciblée : `npm run test --workspace @drivy/api -- test/capture.integration.test.ts`.

Implémentation cryptographique fondée sur les primitives maintenues [Node.js Crypto](https://nodejs.org/docs/latest-v24.x/api/crypto.html#ciphersetaadbuffer-options) et [jose SignJWT](https://github.com/panva/jose/blob/main/docs/jwt/sign/classes/SignJWT.md)/[jwtVerify](https://github.com/panva/jose/blob/main/docs/jwt/verify/functions/jwtVerify.md), sans algorithme de signature maison.
