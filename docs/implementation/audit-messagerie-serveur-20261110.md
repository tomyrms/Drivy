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

## Preuves (PostgreSQL 17 réelle, base `drivy_test` synthétique, Docker local)

| Contrôle | Résultat |
| --- | --- |
| `npx tsc --noEmit` (apps/api) | RÉUSSI |
| `messaging-keys-436-440.integration.test.ts` (14 tests : 5001 sessions identifiants/contenus exacts, interruption puis reprise avec nouveau service, 409 changement pendant lecture, curseurs/limites invalides, autre compte, taille en octets ; #440 upload→claim→rejeu→redémarrage, concurrence, conflit, RLS, plafond) | RÉUSSI 14/14 (deux tests corrigés dans leur propre énoncé : limite 700 > 500, plafond de 200 mal posé) |
| `messaging-keys.integration.test.ts` (régression) | RÉUSSI |
| `identity-migration`, `course-upgrade`, `messaging-migrations` (combinaison harness `skipMigrations` + `deferCourseMigrations`) | RÉUSSI 6/6 |
| Campagne complète, CI, déploiement, clients Swift/web | NON EXÉCUTÉ |
