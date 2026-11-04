# Médias E2EE de la messagerie — backend (T1, #97)

Date : 4 novembre 2026. Branche `tomyrms/issues-medias-97`, base `b0152a2a` (contrat révision 2). Tâche **T1** du contrat
`docs/implementation/medias-exploitation-contrat-20261104.md` §§3–4/6/7, avec les arbitrages du coordinateur
(`orchestration-20261104/medias-arbitrages-coordinateur.md`) : une pièce par message, plafond 4 Mio, JPEG/PNG/PDF côté
appareil, miniatures locales, aucune purge automatique, aucune activation.

## 1. Périmètre livré

| Élément | Fichier |
|---|---|
| Migration additive (tables, états, fonctions, RLS, journal) | `apps/api/migrations/20261104_messaging_media_97.sql` |
| Module média (dépôt, téléchargement, annulation, attache, appareil) | `apps/api/src/messaging-media.ts` |
| Schémas exécutables (Zod) | `apps/api/src/messaging-media-contract.ts` |
| Générateur du contrat JSON | `apps/api/scripts/generate-messaging-media-contract.ts` |
| Contrat généré | `apps/api/contracts/messaging-media.json` |
| Script de purge **manuel** | `apps/api/scripts/purge-messaging-media.ts` |
| Routes média + champ `media` du POST message | `apps/api/src/messaging-routes.ts` |
| Empreinte d'idempotence et attache transactionnelle | `apps/api/src/messaging.ts` |
| Projection `media` du message et codes d'erreur média | `apps/api/src/messaging-view.ts` |
| Tests unitaires, intégration PostgreSQL, contrat | `apps/api/test/messaging-media*.test.ts` |

Aucun autre fichier n'est modifié : ni le contrat préparatoire, ni `STATUS.md`, ni l'infra, ni les verrous, ni l'ancien
SQL, ni les sources iOS/web, ni les scripts de développement, ni le harnais partagé.

## 2. Serveur opaque : ce qui est stocké

`drivy.messaging_media` ne contient que : identifiant, école, conversation, déposant, **taille**, **SHA-256 du chiffré**,
**octets chiffrés**, horodatages, état dérivé de colonnes et message porteur. Aucun nom, type MIME, légende, dimension,
clé, IV, miniature ni hash du clair n'est reçu, stocké, journalisé ou renvoyé. Le serveur ne peut pas lire le fichier.

Les trois états sont **dérivés de colonnes**, jamais d'un booléen libre, et vérifiés par contraintes :

| État | `ciphertext` | `message_id` | Contrainte |
|---|---|---|---|
| `UPLOADED` | présent | `NULL` | `(message_id IS NULL) = (attached_at IS NULL)` |
| `ATTACHED` | présent | non nul | idem |
| `PURGED` | `NULL` | indifférent | `(ciphertext IS NULL) = (purged_at IS NOT NULL)` et `= (purge_reason IS NOT NULL)` |

`PURGED` est **terminal** : aucune fonction ne réécrit des octets, et le `PUT` d'un identifiant purgé répond
`409 MEDIA_PURGED`. L'identifiant n'est jamais réutilisé.

`drivy.messaging_media_purge` est un **journal d'audit dans la même base**. Il ne protège **pas** d'une restauration :
aucune archive indépendante n'existe, la garantie de non-résurrection reste **NON FOURNIE** (#68, MED68-07/08/09).

## 3. Interface HTTP exacte

Préfixe `/v1/schools/{schoolId}/messaging`, mêmes en-têtes que la messagerie existante
(`Authorization`, `X-Drivy-Expected-Person-Id`, `X-Drivy-Expected-Access-Epoch`) plus `X-Drivy-Device-Id`
(`[A-Z0-9]{10,32}`) pour les trois routes média. Toutes restent derrière la porte de qualification existante :
école non autorisée → `503 MESSAGING_NOT_ENABLED`, sans accès base.

| Méthode | Chemin | Corps | Succès |
|---|---|---|---|
| `PUT` | `/conversations/{conversationId}/media/{mediaId}` | octets chiffrés bruts, `application/octet-stream`, `Content-Length` obligatoire | `200 { data: { mediaId, byteSize, sha256, state }, context, requestId, serverTime }` |
| `GET` | `/conversations/{conversationId}/media/{mediaId}` | — | `200 application/octet-stream` + `Content-Length`, `Cache-Control: private, no-store`, `X-Drivy-School-Id`, `X-Drivy-Access-Epoch`, `X-Drivy-Media-Sha256` |
| `DELETE` | `/conversations/{conversationId}/media/{mediaId}` | — | `200 { data: { mediaId, deleted: true } }` |
| `POST` | `/conversations/{conversationId}/messages` | champ `media: { mediaId, byteSize }` (facultatif, exclusif de `poll`) | `Message` étendu : `media: { mediaId, byteSize, deleted } \| null` |

Comportement du `PUT` (reconnaît un dépôt identique au lieu de créer un faux conflit) :

| État courant | Même SHA-256 et même taille | Octets différents |
|---|---|---|
| aucun | crée `UPLOADED`, `200` | — |
| `UPLOADED` | `200`, aucune écriture, `created_at` inchangé | `409 MEDIA_INTENT_CONFLICT` |
| `ATTACHED` | `200 { state: "ATTACHED" }` | `409 MEDIA_INTENT_CONFLICT` |
| `PURGED` | `409 MEDIA_PURGED`, aucun octet recréé | `409 MEDIA_PURGED` |

Codes d'erreur média : `400 INVALID_MEDIA`, `413 PAYLOAD_TOO_LARGE`, `403 MESSAGING_DEVICE_REQUIRED`,
`404 MEDIA_NOT_FOUND` (uniforme : inconnu, autre école, autre conversation, non participant, hors plage, masqué,
supprimé, purgé), `409 MEDIA_INTENT_CONFLICT`, `409 MEDIA_ALREADY_ATTACHED`, `409 MEDIA_SIZE_MISMATCH`,
`409 MEDIA_PURGED`, `503 MESSAGING_NOT_ENABLED`. Les refus de droits restent `403 ACCESS_DENIED` (comportement existant).

Un identifiant déjà pris par un média **invisible** (autre déposant, autre école) répond `404 MEDIA_NOT_FOUND`, jamais
`409` : la clé primaire est protégée par `ON CONFLICT (id) DO NOTHING`, sans erreur SQL observable.

## 4. Droits relus côté serveur

Chaque route reprend la transaction de la messagerie : porte, identité OIDC, acteur attendu, époque d'accès sous
verrou (`FOR SHARE`), appartenance active, puis `SET LOCAL ROLE drivy_app` et RLS forcée.

- **Dépôt** : conversation visible (sinon `404 MEDIA_NOT_FOUND`), verrou de conversation, synchronisation des liens,
  `messaging_can_write` (sinon `403`), appareil **déclaré actif** non révoqué (`403 MESSAGING_DEVICE_REQUIRED`).
- **Téléchargement** : conversation visible, média `ATTACHED` avec octets, message **non supprimé pour tout le monde**,
  `messaging_readable_sequence` (plage du lien), message **non masqué** pour l'acteur, appareil actif. Toute autre
  situation répond le même `404`, sans hash ni taille.
- **Annulation** : conversation visible, verrou, `messaging_can_write`, déposant = acteur (sinon `404` uniforme).
- **Attache** : dans la transaction du message, sous le verrou de conversation, la fonction `SECURITY DEFINER`
  vérifie déposant = expéditeur, même conversation, état `UPLOADED`, octets présents, `byte_size` = taille déclarée,
  puis pose `ATTACHED`. Un échec annule l'insertion du message (aucun succès partiel, aucune séquence consommée).

**Portée honnête de l'appareil** : `X-Drivy-Device-Id` est un identifiant déclaré, pas une preuve de possession
cryptographique. La révocation garantit le refus de ce `deviceId` et l'arrêt des distributions de clés ; elle ne
garantit pas qu'un porteur du `Bearer` du compte ne se présente pas avec un autre appareil actif, ni l'effacement des
copies locales. Aucune liaison cryptographique requête/appareil n'a été inventée.

## 5. Verrous, courses et atomicité

Ordre unique : **conversation → message → média**. La purge ne prend que le verrou de la ligne média.

| Opération | Verrous pris |
|---|---|
| `PUT` média | conversation (`FOR UPDATE`) → ligne média (`messaging_lock_media`) |
| Attache (POST message) | conversation → message (insertion + verrou de conversation) → média |
| Annulation (`DELETE` média) | conversation → média |
| Suppression pour tout le monde | conversation → message → média (purge) |
| Purge orpheline | lignes média seulement (`UPDATE … WHERE message_id IS NULL AND ciphertext IS NOT NULL`) |

Conséquences vérifiées par tests : deux dépôts identiques concurrents → une ligne ; attache et annulation concurrentes
→ un seul gagnant, jamais d'état mixte ; une purge orpheline qui perd la course contre une attache voit `ATTACHED` et
n'efface rien ; un renvoi du même message restitue le même reçu sans seconde attache.

Le rôle applicatif n'a **aucun privilège `UPDATE` ni `DELETE`** sur `drivy.messaging_media` : le verrou de ligne du
dépôt passe par `drivy.messaging_lock_media(uuid,uuid)`, bornée aux lignes du déposant ; toutes les transitions passent
par des fonctions `SECURITY DEFINER`. `messaging_purge_orphan_media` est réservée au rôle propriétaire (script manuel) :
`drivy_app` reçoit `42501` s'il l'appelle.

## 6. Limites et ressources (aucun quota ni service inventé)

- Plafond par pièce : **4 194 304 octets**. Limite de corps des routes média : **4 194 304 + 8 192 octets**.
- Le `bodyLimit` global de l'API reste **16 384 octets** ; le parser `application/octet-stream` n'est ajouté que par la
  messagerie, et les autres routes gardent leurs limites (rapports 640 Kio, relais de clés 262 Kio).
- Mémoire : un `Buffer` par requête, borné par la limite de corps ; aucune concaténation ni copie supplémentaire.
- Délais existants conservés : `lock_timeout` 5 s, `statement_timeout` 10 s par transaction.
- Aucun quota par compte, aucune durée de conservation, aucun TTL d'orphelins par défaut, aucune planification.
- `SET STORAGE EXTERNAL` sur `ciphertext` : des octets aléatoires ne sont pas recompressés.

## 7. Contrat exécutable

`apps/api/src/messaging-media-contract.ts` définit les schémas Zod ; `scripts/generate-messaging-media-contract.ts`
écrit `apps/api/contracts/messaging-media.json` (`$id: urn:drivy:contract:messaging-media:1`) par
`z.toJSONSchema`, comme `learner-course-facts`. Le dossier de conception 3.11.0 reste **immuable** : aucune route n'y
est ajoutée, ce fichier est l'extension exécutable du dépôt. Le test compare le fichier à la projection réelle et
échoue si un champ interdit (nom, MIME, légende, clé, IV, miniature, hash du clair) apparaît.

## 8. Purge manuelle

`apps/api/scripts/purge-messaging-media.ts` :

- **inactif par défaut** : sans `--apply`, seul un compte est affiché, aucune écriture ;
- `--cutoff <ISO-8601>` **obligatoire** : aucune valeur par défaut, aucune durée de conservation implicite ;
- refuse une cible **non locale** sauf `--allow-remote-target` explicite (protection contre un lancement accidentel
  pendant la recette) ; exige `MIGRATION_DATABASE_URL` (rôle propriétaire), jamais le rôle applicatif ;
- n'affiche que des **nombres** : aucun identifiant, aucune taille, aucun octet.

## 9. Preuves exécutées

Environnement : Node 24.22.2 portable, PostgreSQL 17.11 conteneur jetable `drivy-t1-97-pg`
(image `postgres:17-alpine@sha256:b0f9560a…`), port loopback 55497, base `drivy_test`, `TEST_DATABASE_URL` limitée à ce
conteneur.

| Commande | Résultat |
|---|---|
| `npx vitest run test/messaging-media.integration.test.ts` | 14 tests, 14 réussis |
| `npx vitest run test/messaging-media.test.ts test/messaging-media-contract.test.ts` | 2 fichiers, 5 tests réussis |
| `npx vitest run test/messaging` (suites `messaging*.test.ts`) | 20 fichiers, 157 tests réussis |
| `npx tsc --noEmit` | code de sortie 0 |
| `npm run build` (`tsc -p tsconfig.build.json`) | code de sortie 0 |
| `tsx scripts/purge-messaging-media.ts` (sans argument) | refus, code 2, aucune écriture |
| `tsx scripts/purge-messaging-media.ts --cutoff 2026-11-01T00:00:00Z` | simulation, 0 dépôt, code 0 |
| `tsx scripts/purge-messaging-media.ts --cutoff … --apply` sur base synthétique | 1 dépôt purgé, 1 entrée de journal |
| même script avec cible non locale | refus, code 2 |
| `npx vitest run` (suite API entière, campagne longue) | 93 fichiers, 1033 tests : 91 fichiers / 1023 tests réussis, 2 fichiers rouges hors lot (voir ci-dessous) |

Deux rouges **hors lot** de la campagne entière, isolés et rejoués seuls :

- `test/g1d.integration.test.ts` : échec dû à une exécution concurrente sur la même base (`schema "drivy" does not exist`) ;
  rejoué seul : **27 tests réussis**.
- `test/g1c.integration.test.ts` (F02, SMTP réel) : 2 échecs `QUEUED` au lieu de `SENT` parce qu'aucun serveur
  SMTP/Mailpit n'écoute sur `127.0.0.1:1025` / `8025` dans cet environnement (`Test-NetConnection` : refus) ; rejoué
  seul : 62 réussis, 2 échoués, tous deux dans le groupe SMTP. Ces tests ne touchent ni la messagerie ni les médias et
  aucun serveur SMTP n'a été démarré (celui de R3 n'est pas à moi et n'était plus actif).

Cycle TDD : le premier test (média absent → `404 MEDIA_NOT_FOUND`) a d'abord échoué sur `404 NOT_FOUND` (route absente),
puis est passé après implémentation. Les autres scénarios ont été ajoutés après ce premier vert ; les défauts qu'ils ont
révélés ont été corrigés (privilège `FOR UPDATE` refusé au rôle applicatif, marque de suppression masquée par la RLS,
404 uniforme pour une conversation invisible, appareils de recette manquants). Aucun test de régression existant n'a
été rendu rouge artificiellement.

## 10. Non exécuté / limites

- Aucune CI distante, aucun push, aucun déploiement, aucune activation, aucune fermeture d'issue.
- Aucune preuve de résidence, sauvegarde, restauration ou non-résurrection : MED68-01…09 restent **NON EXÉCUTÉ / NON
  FOURNI**. Le journal `messaging_media_purge` n'est pas une archive indépendante.
- Aucun test natif, UI, VoiceOver, appareil physique : T2/T3 restent ouvertes.
- Aucun quota, aucune durée de conservation, aucun scan antivirus serveur (impossible sur du chiffré), aucun CDN.
- La suppression pour tout le monde efface les octets **côté service** ; elle ne peut pas effacer les copies déjà
  reçues, les captures d'écran ni un export local.
- Le script de purge n'est pas planifié et ne doit pas l'être avant une politique de conservation approuvée.
