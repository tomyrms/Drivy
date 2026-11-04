# Médias E2EE de la messagerie — backend (T1, #97)

Date : 4 novembre 2026. Branche `tomyrms/issues-medias-97`. Commit initial `a526187f` (base `b0152a2a`), **correction 1**
après revue indépendante (`artifacts/t1-independent-review/rapport.md`). Tâche T1 du contrat
`docs/implementation/medias-exploitation-contrat-20261104.md` §§3–4/6/7, arbitrages du coordinateur :
une pièce par message, plafond 4 Mio, JPEG/PNG/PDF côté appareil, miniatures locales, aucune purge automatique,
aucune activation.

## 0. Cadre de cette correction

- Modèle effectif : `opencode-go/deepseek-v4.1-flash` (OpenCode), sans variante d'effort exposée.
- Skills Superpowers réellement chargés dans ce runtime : `systematic-debugging`, `test-driven-development`,
  `verification-before-completion`. Usage : reproduction et cause racine de chaque défaut avant correction,
  RED/GREEN par test durable, vérification finale par commandes réelles (sorties en §9).
- Codebase Memory : projet `drivy-issues-medias-97`, racine
  `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-97`, réindexé à HEAD avant travaux
  (`indexed_at=2026-11-04T16:00:18Z`, `ready`). Recherches : `sendEnvelope`, `cancelMedia`, `lockRights`,
  `addContentTypeParser`, `messaging_media`. Limite connue : `apps/api/migrations/` est exclu de l'index par
  conception ; les fonctions SQL ont donc été relues dans le source. Aucun index d'un autre worktree n'a été utilisé.
- Aucun secret, jeton, donnée de personne réelle ni position. Les identifiants/octets synthétiques des reproductions
  locales ne sont pas recopiés ici.

## 1. Périmètre livré

| Élément | Fichier |
|---|---|
| Migration additive (tables, états, fonctions, RLS, journal) | `apps/api/migrations/20261104_messaging_media_97.sql` |
| Module média (dépôt, téléchargement, annulation, attache, appareil, verrous) | `apps/api/src/messaging-media.ts` |
| Schémas exécutables et constantes de contrat | `apps/api/src/messaging-media-contract.ts` |
| Générateur du contrat JSON | `apps/api/scripts/generate-messaging-media-contract.ts` |
| Contrat généré | `apps/api/contracts/messaging-media.json` |
| Script de purge **manuel** | `apps/api/scripts/purge-messaging-media.ts` |
| Routes média (scope Fastify encapsulé) + champ `media` du POST message | `apps/api/src/messaging-routes.ts` |
| Empreinte d'idempotence, intention média, attache transactionnelle | `apps/api/src/messaging.ts` |
| Projection `media` du message et codes d'erreur média | `apps/api/src/messaging-view.ts` |
| Tests unitaires, intégration PostgreSQL, contrat | `apps/api/test/messaging-media*.test.ts` |

Aucun autre fichier modifié : ni le contrat préparatoire, ni `STATUS.md` (hors périmètre worker), ni l'infra, ni les
verrous, ni l'ancien SQL, ni les sources iOS/web, ni les scripts de développement, ni le harnais partagé.

## 2. Corrections de la revue indépendante

### S1 — Rejeu des messages enregistrés avant l'ajout des médias

- Cause racine : l'empreinte d'idempotence était devenue un tableau à cinq éléments, le cinquième valant `null` sans
  média ; les messages antérieurs portent une empreinte à quatre éléments → `409 INTENT_CONFLICT` au lieu du reçu.
- Correctif : le couple média n'est ajouté au tableau d'empreinte que lorsqu'une intention média existe ; tout message
  sans média garde **exactement** `sha256(JSON.stringify([enveloppe, mentions, réponse, sondage]))`. Aucun `UPDATE` de
  masse des empreintes, aucun affaiblissement du contrôle : changer le média, son identifiant ou sa taille reste un
  conflit.
- Preuve : test de transition (empreinte historique réécrite puis rejeu) → même `id`, même `sequence`, une seule ligne ;
  empreinte d'un message média vérifiée à cinq éléments ; mutation check (retour au tableau à cinq éléments) → le test
  échoue sur l'empreinte. Script indépendant `repro.ts` (A) : rejeu `200`.

### S2 — Annulation visant une autre conversation que celle de l'URL

- Cause racine : `cancelMedia` verrouillait la conversation de l'URL puis appelait `messaging_purge_media`, qui ne
  connaît que la conversation portée par la ligne média ; l'état du média fuyait hors du périmètre nommé.
- Correctif : après le verrou de conversation, la ligne média est verrouillée via `drivy.messaging_lock_media` (bornée
  au déposant) et sa `conversation_id` est comparée **sous verrou** à celle de l'URL ; sinon `404 MEDIA_NOT_FOUND`
  uniforme, sans purge, sans journal, sans changement de séquence. L'idempotence reste acquise à la bonne URL.
- Preuve : test couvrant `UPLOADED`, `ATTACHED` (plus de `409` révélateur) et `PURGED` (plus de `200` hors URL), plus
  tiers et école étrangère ; mutation check (retrait du contrôle) → `200` au lieu de `404`. `repro.ts` (B),
  `repro3.ts` : `404` dans les trois états.

### S3 — Parser binaire global

- Cause racine : `addContentTypeParser` est global à l'instance Fastify ; le parser `application/octet-stream` à
  4,2 Mio élargissait toutes les routes ordinaires (20 Kio et 1 Mio acceptés puis `400` de schéma).
- Correctif : parser **et** trois routes média sont enregistrés dans un scope Fastify encapsulé
  (`app.register(async function messagingMediaRoutes(scope) { … })`). Hors média, aucun parser de ce type n'existe :
  Fastify refuse le type en `415 UNSUPPORTED_MEDIA_TYPE` avant tout parsing, comme avant le lot. Le `bodyLimit` global
  reste **16 384 octets** ; la limite média (4 194 304 + 8 192) ne s'applique qu'aux routes média.
- Preuve : `read-state` et `POST messages` en `octet-stream` (20 000 et 1 000 000 octets) → `415` ; JSON ordinaire de
  20 000 octets → `413` ; média 1…4 Mio fonctionnel (plafond exact accepté) ; mutation check (parser réenregistré au
  niveau racine) → le test échoue. `repro.ts` (F) et `repro2.ts` : `415`.

### S4 — Contrat réellement relié au service

- Cause racine : les schémas Zod n'étaient importés que par le générateur et un test circulaire ; l'enveloppe servie
  n'était pas modélisée et le corps binaire était décrit comme une chaîne JSON.
- Correctif :
  - `messaging-media-contract.ts` devient la source unique des constantes (plafond, états de reçu) et des schémas :
    intention média du POST, réponse de dépôt, annulation, `media` du message, **enveloppes**
    `{ data, context, requestId, serverTime }`, erreurs.
  - l'intention média du POST est validée **par ce schéma** à la frontière du domaine (`sendEnvelope`) ;
  - les tests d'intégration valident les **réponses HTTP réelles** (Ajv 2020 + le fichier généré) : enveloppe de dépôt,
    enveloppe d'annulation, `media` du message, corps d'erreur `409`/`415` ;
  - un reçu de dépôt n'annonce que `UPLOADED` ou `ATTACHED` (type et schéma), jamais `PURGED` ;
  - les codes réellement émis sont dans `mediaErrorCodes` (`INVALID_MEDIA`, `INVALID_REQUEST`, `PAYLOAD_TOO_LARGE`,
    `UNSUPPORTED_MEDIA_TYPE`, `AUTHENTICATION_REQUIRED`, `ACCESS_DENIED`, `MESSAGING_DEVICE_REQUIRED`,
    `MEDIA_NOT_FOUND`, `MEDIA_INTENT_CONFLICT`, `MEDIA_ALREADY_ATTACHED`, `MEDIA_SIZE_MISMATCH`, `MEDIA_PURGED`,
    `CONCURRENT_REQUEST`, `MESSAGING_NOT_ENABLED`, `SERVICE_UNAVAILABLE`) ;
  - le corps du PUT reste **binaire brut** : le générateur ajoute `contentMediaType: application/octet-stream` et un
    `$comment` qui dit explicitement que `type: "string"`/`maxLength` sont l'annotation JSON Schema d'une limite, pas
    une validation des octets ; aucun `contentEncoding: base64` n'est revendiqué. Un test de transport séparé vérifie
    qu'un corps JSON est refusé (`415`) et qu'une chaîne ressemblant à du base64 n'est **pas** décodée (elle reste
    quatre octets opaques).
- Preuve : test de contrat (définitions + annotation binaire + états de reçu + codes) et test d'intégration de
  validation des réponses réelles.

### S5 — Sources de droits non verrouillées avant la conversation

- Cause racine : contrairement à `lockForWrite` de la messagerie, le dépôt/annulation média prenait la conversation sans
  `messaging_lock_rights` ; une fin d'éligibilité pouvait se committer entre le contrôle et l'écriture.
- Correctif : `lockConversationForWrite` réutilise `lockRights` (exporté par `messaging.ts`) avant le verrou de
  conversation, puis relit `messaging_can_write` avant **et** après `syncLinks`. Ordre retenu :
  **droits → conversation → message → média**, sans jamais prendre les droits après la conversation (pas de cycle).
- Découverte liée, corrigée : `SELECT … FOR UPDATE` sur `messaging_conversation` applique aussi la politique RLS
  `UPDATE` (qui exige `messaging_can_write`). Une fin d'éligibilité déjà commitée faisait donc disparaître la ligne et
  répondait `404` au lieu de `403`. Le contrôle d'écriture est désormais fait **avant** le verrou de conversation
  (403), et de nouveau après la synchronisation des liens.
- Preuve : barrière déterministe (mise à jour d'affectation non commitée, `pg_blocking_pids`) → le dépôt attend le
  verrou des sources (`messaging_lock_rights`), puis répond `403` et n'écrit aucune ligne ; mutation check (retrait de
  `lockRights`) → le dépôt ne bloque plus (test rouge). Couvre M09 (fin de lien avant dépôt → `403`, rien) et
  M10 (fin de lien entre dépôt et message → `403`, média `UPLOADED`).

### S6 — Codes et ordre de porte

- Correctif : la porte de qualification est évaluée **avant** `deviceHeader` et avant toute validation métier des
  routes média (école fermée + appareil invalide → `503 MESSAGING_NOT_ENABLED`) ; l'identifiant et la taille média du
  POST message sont validés par le schéma de domaine → `400 INVALID_MEDIA` (les refus des messages ordinaires restent
  `400 INVALID_REQUEST` / `INVALID_ENVELOPE`) ; `415 UNSUPPORTED_MEDIA_TYPE` est documenté et asserté, y compris dans
  le contrat.
- Preuve : tests dédiés (`503` porte-avant-appareil, `INVALID_MEDIA` pour identifiant/taille invalides) ; `repro3.ts`
  confirme `503` et `INVALID_MEDIA`.

### Couverture ajoutée

- **M09** : fin de lien avant dépôt → `403`, aucune ligne (barrière S5).
- **M10** : fin de lien entre dépôt et message → `403`, média `UPLOADED`, aucun message.
- **M20** : course attache/purge orpheline avec barrières contrôlées (`pg_blocking_pids`) → la purge attend, puis
  `0` purge, octets conservés, journal `0`.
- **O02** : sentinelle sur les **vrais logs applicatifs** (instance `buildApp` avec logger actif et flux capturé) :
  méthode, modèle de route, statut et code présents ; aucun identifiant de média, de conversation ou de personne,
  aucun appareil, aucun SHA-256, aucune charge d'enveloppe. `requestId` technique reste autorisé.

## 3. Serveur opaque : ce qui est stocké

`drivy.messaging_media` ne contient que : identifiant, école, conversation, déposant, **taille**, **SHA-256 du chiffré**,
**octets chiffrés**, horodatages, état dérivé de colonnes et message porteur. Aucun nom, type MIME, légende, dimension,
clé, IV, miniature ni hash du clair n'est reçu, stocké, journalisé ou renvoyé. Le serveur ne peut pas lire le fichier.

| État | `ciphertext` | `message_id` | Contraintes |
|---|---|---|---|
| `UPLOADED` | présent | `NULL` | `(message_id IS NULL) = (attached_at IS NULL)` |
| `ATTACHED` | présent | non nul | idem |
| `PURGED` | `NULL` | indifférent | `(ciphertext IS NULL) = (purged_at IS NOT NULL)` et `= (purge_reason IS NOT NULL)` |

`PURGED` est **terminal** : aucune fonction ne réécrit des octets ; le `PUT` d'un identifiant purgé répond
`409 MEDIA_PURGED`, l'attache d'un média purgé `404 MEDIA_NOT_FOUND`. L'identifiant n'est jamais réutilisé.

`drivy.messaging_media_purge` est un **journal d'audit dans la même base** : il ne protège **pas** d'une restauration
(aucune archive indépendante, #68 — MED68-07/08/09 restent **NON FOURNI**).

## 4. Interface HTTP exacte

Préfixe `/v1/schools/{schoolId}/messaging`, en-têtes existants (`Authorization`, `X-Drivy-Expected-Person-Id`,
`X-Drivy-Expected-Access-Epoch`) plus `X-Drivy-Device-Id` (`[A-Z0-9]{10,32}`) pour les trois routes média. Toutes
restent derrière la porte de qualification : école non autorisée → `503 MESSAGING_NOT_ENABLED`, sans accès base et
avant toute validation d'appareil ou de média.

| Méthode | Chemin | Corps | Succès |
|---|---|---|---|
| `PUT` | `/conversations/{conversationId}/media/{mediaId}` | octets chiffrés bruts, `application/octet-stream`, `Content-Length` obligatoire | `200 { data: { mediaId, byteSize, sha256, state }, context: { schoolId, actorPersonId, accessEpoch }, requestId, serverTime }` |
| `GET` | `/conversations/{conversationId}/media/{mediaId}` | — | `200 application/octet-stream` + `Content-Length`, `Cache-Control: private, no-store`, `X-Drivy-School-Id`, `X-Drivy-Access-Epoch`, `X-Drivy-Media-Sha256` |
| `DELETE` | `/conversations/{conversationId}/media/{mediaId}` | — | `200 { data: { mediaId, deleted: true }, context, requestId, serverTime }` |
| `POST` | `/conversations/{conversationId}/messages` | champ `media: { mediaId, byteSize }` (facultatif, exclusif de `poll`) | `Message` étendu : `media: { mediaId, byteSize, deleted } \| null` |

Comportement du `PUT` (un dépôt identique est reconnu, jamais un faux conflit) :

| État courant | Même SHA-256 et même taille | Octets différents |
|---|---|---|
| aucun | crée `UPLOADED`, `200` | — |
| `UPLOADED` | `200`, aucune écriture, `created_at` inchangé | `409 MEDIA_INTENT_CONFLICT` |
| `ATTACHED` | `200 { state: "ATTACHED" }` | `409 MEDIA_INTENT_CONFLICT` |
| `PURGED` | `409 MEDIA_PURGED`, aucun octet recréé | `409 MEDIA_PURGED` |

Un identifiant déjà pris par un média **invisible** (autre déposant, autre école) répond `404 MEDIA_NOT_FOUND`, jamais
`409` : la clé primaire est protégée par `ON CONFLICT (id) DO NOTHING`, sans erreur SQL observable.

Codes : `400 INVALID_MEDIA`, `400 INVALID_REQUEST`, `413 PAYLOAD_TOO_LARGE`, `415 UNSUPPORTED_MEDIA_TYPE`,
`401 AUTHENTICATION_REQUIRED`, `403 ACCESS_DENIED`, `403 MESSAGING_DEVICE_REQUIRED`, `404 MEDIA_NOT_FOUND` (uniforme :
inconnu, autre école, autre conversation, non participant, hors plage, masqué, supprimé, purgé),
`409 MEDIA_INTENT_CONFLICT`, `409 MEDIA_ALREADY_ATTACHED`, `409 MEDIA_SIZE_MISMATCH`, `409 MEDIA_PURGED`,
`409 CONCURRENT_REQUEST`, `503 MESSAGING_NOT_ENABLED`, `503 SERVICE_UNAVAILABLE`.

## 5. Droits relus côté serveur

Chaque route reprend la transaction de la messagerie : porte, identité OIDC, acteur attendu, époque d'accès sous verrou
(`FOR SHARE`), appartenance active, puis `SET LOCAL ROLE drivy_app` et RLS forcée.

- **Dépôt** : conversation visible (sinon `404 MEDIA_NOT_FOUND`) → **sources de droits verrouillées** →
  `messaging_can_write` (sinon `403`) → verrou de conversation → synchronisation des liens → droit recontrôlé →
  appareil **déclaré actif** non révoqué (`403 MESSAGING_DEVICE_REQUIRED`).
- **Téléchargement** : conversation visible, média `ATTACHED` avec octets, message **non supprimé pour tout le monde**,
  `messaging_readable_sequence`, message **non masqué**, appareil actif ; sinon le même `404`, sans hash ni taille.
- **Annulation** : conversation visible, droits verrouillés, droit d'écriture, ligne média verrouillée et sa
  conversation comparée à celle de l'URL (sinon `404` uniforme), déposant = acteur.
- **Attache** : dans la transaction du message, sous le verrou de conversation, `SECURITY DEFINER` vérifie déposant =
  expéditeur, même conversation, état `UPLOADED`, octets présents, `byte_size` = taille déclarée ; un échec annule
  l'insertion (aucun succès partiel, aucune séquence consommée).

**Portée honnête de l'appareil** : `X-Drivy-Device-Id` est un identifiant déclaré, pas une preuve de possession
cryptographique. La révocation garantit le refus de ce `deviceId` et l'arrêt des distributions de clés ; elle ne
garantit pas qu'un porteur du `Bearer` du compte ne se présente pas avec un autre appareil actif, ni l'effacement des
copies locales. Aucune liaison cryptographique requête/appareil n'a été inventée.

## 6. Verrous, courses et atomicité

Ordre unique : **droits → conversation → message → média**. La purge orpheline ne prend que le verrou des lignes média.

| Opération | Verrous pris |
|---|---|
| `PUT` média | sources de droits (`messaging_lock_rights`) → conversation (`FOR UPDATE`) → ligne média (`messaging_lock_media`) |
| Attache (POST message) | sources de droits → conversation → message (insertion) → média |
| Annulation (`DELETE` média) | sources de droits → conversation → ligne média (conversation comparée sous verrou) |
| Suppression pour tout le monde | sources de droits → conversation → message → média (purge) |
| Purge orpheline | lignes média seulement (`UPDATE … WHERE message_id IS NULL AND ciphertext IS NOT NULL`) |

Conséquences vérifiées : deux dépôts identiques concurrents → une ligne ; attache et annulation concurrentes → un seul
gagnant, jamais d'état mixte ; purge orpheline perdant la course contre une attache → `ATTACHED`, aucun octet effacé,
journal `0` ; une purge annulée par `ROLLBACK` ne laisse ni octet effacé ni entrée ; rejeu du même message → même reçu,
aucune seconde attache.

Le rôle applicatif n'a **aucun privilège `UPDATE` ni `DELETE`** sur `drivy.messaging_media` : le verrou de ligne du
dépôt passe par `drivy.messaging_lock_media(uuid,uuid)`, bornée aux lignes du déposant ; toutes les transitions passent
par des fonctions `SECURITY DEFINER`. `messaging_purge_orphan_media` est réservée au rôle propriétaire (script manuel) :
`drivy_app` reçoit `42501`.

## 7. Limites et ressources (aucun quota ni service inventé)

- Plafond par pièce : **4 194 304 octets**. Limite de corps des routes média : **4 194 304 + 8 192 octets**.
- Le `bodyLimit` global de l'API reste **16 384 octets** ; le parser `application/octet-stream` est **encapsulé** au
  scope média. Hors média, ce type est refusé par le transport (`415`), comme avant le lot ; les limites dédiées des
  autres routes (rapports 640 Kio, relais de clés 262 Kio) restent effectives.
- Mémoire : un `Buffer` par requête, borné par la limite de corps du scope média ; aucune copie supplémentaire.
- Délais existants conservés : `lock_timeout` 5 s, `statement_timeout` 10 s par transaction.
- Aucun quota par compte, aucune durée de conservation, aucun TTL d'orphelins par défaut, aucune planification.
- `SET STORAGE EXTERNAL` sur `ciphertext` : des octets aléatoires ne sont pas recompressés.

## 8. Contrat exécutable et purge manuelle

`messaging-media-contract.ts` → `scripts/generate-messaging-media-contract.ts` →
`apps/api/contracts/messaging-media.json` (`$id: urn:drivy:contract:messaging-media:1`), par `z.toJSONSchema` comme
`learner-course-facts`. Le dossier de conception 3.11.0 reste **immuable**. Le fichier contient les définitions
`MediaPutBody` (annotée binaire), `MediaMessageIntent`, `MediaUploadResponse`, `MediaCancelResponse`, `MediaMessage`,
`MediaUploadEnvelope`, `MediaCancelEnvelope`, `MediaError` ; les tests d'intégration valident les réponses réelles
contre ce fichier (Ajv 2020), et le test de contrat vérifie la projection, l'annotation binaire, les états de reçu et
l'absence de champ interdit.

`apps/api/scripts/purge-messaging-media.ts` : inactif par défaut (simulation seule), `--cutoff <ISO-8601>` obligatoire,
cible non locale refusée sauf `--allow-remote-target`, `MIGRATION_DATABASE_URL` (rôle propriétaire) exigée, sortie
numérique uniquement, aucune planification.

## 9. Preuves exécutées (environnement local réel)

Node 24.22.2 portable, PostgreSQL 17.11, conteneur jetable `drivy-t1-97-pg`
(`postgres:17-alpine@sha256:b0f9560a…`), port loopback 55497, base `drivy_test` ; une campagne à la fois.

| Commande | Résultat |
|---|---|
| `npx vitest run test/messaging-media.integration.test.ts test/messaging-media.test.ts test/messaging-media-contract.test.ts` | 3 fichiers, **27 tests réussis** (22 + 4 + 1), exit 0 |
| `npx vitest run test/messaging` (suites `messaging*.test.ts`) | 20 fichiers, **165 tests réussis**, exit 0 |
| `npx tsc --noEmit` | exit **0** |
| `npm run build` | exit **0** |
| `npx tsx artifacts/t1-independent-review/repro.ts` | exit 0 : rejeu historique `200`, annulation hors conversation `404` (`UPLOADED` conservé), `octet-stream` ordinaire `415` (20 Kio, 1 Mio, 4,2 Mio), JSON 20 Kio `413`, `byteSize` hors plafond `400 INVALID_MEDIA` |
| `npx tsx artifacts/t1-independent-review/repro3.ts` | exit 0 : `ATTACHED`/`PURGED` hors conversation `404`, autre déposant `404` + séquence inchangée, école fermée + appareil invalide `503`, `mediaId` invalide `400 INVALID_MEDIA`, `octet-stream` sur `/reports` `415` |
| `npx tsx artifacts/t1-independent-review/repro2.ts` | exit 0 : barrières attache/purge/annulation conformes, `journal 0/1` cohérent, `ROLLBACK` sans effet, périmètre école `DV403`, `lock_media` borné, `415` à 4,3 Mio, appareil révoqué `403` |
| `npx tsx scripts/purge-messaging-media.ts` (sans argument) | exit **2**, refus, aucune écriture |
| `… --cutoff 2026-11-01T00:00:00Z` (boucle locale) | exit 0, simulation 0 dépôt, aucune écriture |

Mutation checks (chaque nouveau test a été vu rouge sans son correctif, puis vert) :

| Défaut | Mutation appliquée | Résultat observé |
|---|---|---|
| S1 | empreinte revenue à cinq éléments | test rouge : empreinte différente de la forme historique |
| S2 | contrôle de conversation retiré de `cancelMedia` | test rouge : `200` au lieu de `404` |
| S3 | parser réenregistré au niveau racine | test rouge : `octet-stream` ordinaire accepté au lieu de `415` |
| S5 | `lockRights` retiré du verrou de conversation | test rouge : `blocked=false` (le dépôt n'attend pas les droits) |

## 10. Non exécuté / limites

- Aucune CI distante, aucun push, aucun déploiement, aucune activation, aucune fermeture d'issue, aucun `STATUS.md`.
- Aucune preuve de résidence, sauvegarde, restauration ou non-résurrection : MED68-01…09 restent **NON EXÉCUTÉ /
  NON FOURNI**. Le journal `messaging_media_purge` n'est pas une archive indépendante.
- Aucun test natif, UI, VoiceOver, appareil physique : T2/T3 restent ouvertes.
- Aucun quota, aucune durée de conservation, aucun scan antivirus serveur (impossible sur du chiffré), aucun CDN.
- La suppression pour tout le monde efface les octets **côté service** ; elle ne peut pas effacer les copies déjà
  reçues, les captures d'écran ni un export local.
- Le script de purge n'est pas planifié et ne doit pas l'être avant une politique de conservation approuvée.
- Les deux rouges SMTP de `test/g1c.integration.test.ts` restent un écart d'environnement (aucun serveur Mailpit sur
  1025/8025 dans ce contexte), hors lot et non masqués.
