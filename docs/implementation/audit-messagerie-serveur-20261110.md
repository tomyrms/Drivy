# Audit messagerie serveur — lot F (#436, #440), 2026-11-10

## #436 — sauvegarde restaurable au-delà de 5000 sessions

Cause : `getBackupKeys` lisait `LIMIT 5001` et répondait `503` au-delà, alors que `PUT` accepte 5001 sessions et plus : une sauvegarde acceptée n'était plus restaurable.

Correction (`apps/api/src/messaging-keys.ts`, `messaging-keys-routes.ts`) : lecture paginée par curseur sur (roomId, sessionId), `limit` ≤ 500, page ≤ 2 Mio, `etag` relu après la page, curseur validé (portée compte/école/version/etag). Contrat client : `docs/implementation/messaging-api-contract.md`, « Lecture paginée de la sauvegarde ». Forme historique conservée pour ≤ 5000 sessions ; au-delà elle refuse explicitement (422) au lieu d'un 503. Les uploads ne sont pas refusés pour contourner.

Limite : le client natif (#435/#428) n'est pas raccordé ; ces tickets ne sont pas résolus par ce lot.

## #440 — clé à usage unique jamais redistribuée

Cause : la réclamation supprimait la ligne ; un renvoi identique du lot la réinsérait, donc la clé pouvait être distribuée deux fois.

Correction : migration `20261110_messaging_otk_consumption_proof.sql` ajoute `consumed_at` et `key_digest` (SHA-256). La réclamation marque la ligne consommée et efface la clé publique (`""`) ; la ligne sert de preuve par compte/appareil/identifiant. Le renvoi identique est idempotent (200), un contenu différent sous le même identifiant donne 409 `ONE_TIME_KEY_CONFLICT` (disponible ou consommé). Compteurs et plafond de 200 : clés disponibles seulement. Politique de lecture des pairs limitée aux clés disponibles. Révocation d'appareil : toutes les lignes, preuves comprises, sont supprimées (comportement inchangé).

Transition : les clés consommées avant la migration ont été supprimées sans trace ; aucune empreinte n'est inventée. Un renvoi d'un ancien lot déjà consommé avant la migration peut donc encore être accepté une fois comme nouvelle clé. Seules les clés présentes reçoivent une empreinte.

Retour arrière (API arrêtée, jamais exécuté en production) : supprimer les lignes `consumed_at IS NOT NULL`, rétablir la politique `messaging_otk_peer_read` d'origine et la fonction de `20261023f`, puis `DROP COLUMN consumed_at, key_digest` et l'index `messaging_one_time_key_available`. Rétablir la suppression ressuscite le risque #440.

## Ordre de mise à jour (#440)

La migration n'est pas compatible avec d'anciennes instances encore actives : après `ADD COLUMN key_digest … SET NOT NULL`, l'ancien `INSERT` sans `key_digest` échoue, et l'ancienne réclamation (`DELETE`) n'est plus couverte par la politique de lecture. Ordre exigé : arrêter toutes les instances de l'API, sauvegarder la base, appliquer la migration, démarrer la nouvelle version. Pas de déploiement progressif. Aucun déploiement n'a été fait ni n'est demandé par ce lot.

## Preuves (PostgreSQL 17 réelle, base `drivy_test` synthétique, Docker local, 2026-11-10)

Runtime requalifié sous Node **v24.22.2** (npm 11.19.1, `node24-extract/node-v24.22.2-win-x64`), cible de `apps/api/package.json` (>=24 <25). Les premiers résultats du lot (14/14 et `messaging-keys`) avaient été obtenus sous Node v26.8.1, hors cible : ils sont remplacés par les lignes ci-dessous. Le préfixe `PATH` n'est pas pris en compte par le shell sur cette machine : les commandes appellent `node.exe` 24 par chemin complet (`node ..\..\node_modules\vitest\vitest.mjs`, `node ..\..\node_modules\typescript\bin\tsc`).

| Contrôle (Node 24.22.2) | Résultat |
| --- | --- |
| `tsc --noEmit` (apps/api) | RÉUSSI, code 0 |
| `tsc -p tsconfig.build.json` (build) | RÉUSSI, code 0 |
| `vitest run` de `messaging-keys-436-440` (14 tests), `messaging-keys` (11 tests, non chiffré jusque-là) et `messaging-keys-440-migration` (4 tests) | RÉUSSI : 3 fichiers, 29/29 |
| Campagne complète, CI, déploiement, clients Swift/web | NON EXÉCUTÉ |

`messaging-keys-440-migration.integration.test.ts` (nouveau, patron `identity-migration`) : `freshDatabase({ skipMigrations: /^20261110_messaging_otk_consumption_proof/ })`, schéma antérieur vérifié sans `consumed_at`/`key_digest`, deux clés synthétiques non consommées insérées, puis `migrate()` sous `drivy_harness_migrator` (non superuser, sans BYPASSRLS). Prouvé : empreinte SHA-256 de chaque clé présente (recalculée côté Node) et contenu conservé, toutes disponibles, compteur 2 ; rejeu identique 200, claim, rejeu, claim, claim vide, rejeu final sans résurrection ; contenu différent sur un identifiant consommé `409 ONE_TIME_KEY_CONFLICT` ; nouvelle clé distincte acceptée puis distribuée une fois ; limite : un identifiant consommé avant la migration n'a aucune trace et se republie comme une clé neuve (aucun tombstone inventé).