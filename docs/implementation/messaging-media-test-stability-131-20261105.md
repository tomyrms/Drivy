# Stabilité des tests média — assertion `409` dans un requestId (S131)

Date : 5 novembre 2026. Worktree `issues-medias-97`, tête de départ
`6ae15917f0c0670722237b02fd54aacf29620565` (propre). Aucun changement produit.

## 1. Anomalie et preuve

L'intégration I2 a reçu une réponse **correcte** `404 MEDIA_NOT_FOUND` dont le `requestId`
(`dff23de8-9bad-409d-bd7d-1e600974f736`) contient la sous-chaîne `409`. Le test
`apps/api/test/messaging-media.integration.test.ts` vérifiait
`expect(collision.body).not.toMatch(/sha256|byteSize|409/)` : la sous-chaîne du `requestId` faisait échouer
l'assertion alors que la réponse était conforme.

Reproduction fournie par I2 (`artifacts/i2-20261105/regex-flake-repro.*`) : corps réel `404`, `status: 404`,
`/409/` correspond dans le `requestId` ; sur 200 000 UUID synthétiques, 1 622 contiennent `409` (**0,811 %**).
La fréquence observée (~0,8 %) vient donc de l'aléa du générateur d'identifiant de requête, pas d'un conflit serveur.

## 2. Cause racine

L'assertion contrôlait une **sous-chaîne du corps sérialisé** au lieu du statut HTTP et du type/code de problème.
Un `requestId` est un identifiant technique légal : il peut contenir `409`, `404` ou tout autre fragment sans
signification métier. Le défaut est entièrement dans le test.

## 3. Correctif

- Nouveau vérificateur de test `expectProblem(response, status, code)` : contrôle le **statut HTTP**, le `type`
  (`urn:drivy:problem:<code>`), le `code`, la présence de `requestId`, l'**ensemble exact des champs** du corps de
  problème (`type`, `title`, `status`, `code`, `requestId`) et l'**absence de métadonnées média**
  (`sha256`, `byteSize`, `ciphertext`, `purgedAt`, `mediaId`, `messageId`). Aucune sous-chaîne d'un identifiant légal
  n'est interdite.
- Le contrôle d'absence de métadonnées `sha256`/`byteSize` est conservé, et renforcé par la liste exacte des champs.
- Les deux sites concernés utilisent le vérificateur : `403 ACCESS_DENIED` (école étrangère) et
  `404 MEDIA_NOT_FOUND` (identifiant déjà pris par un média invisible).
- Aucun générateur d'identifiant, gestionnaire d'erreurs, contrat ou dépendance produit n'est modifié.

## 4. Régression déterministe

Nouveau test `ne confond pas une sous-chaîne du requestId avec un conflit ou une fuite de métadonnées` :

1. une **fixture de test** (`app.addHook('onRequest')` du fichier de test, en-tête `x-test-request-id`) impose le
   `requestId` `40900000-0000-4000-8000-000000000409` à une requête réelle de collision ;
2. la réponse réelle est un `404 MEDIA_NOT_FOUND` : le vérificateur l'accepte et le `requestId` renvoyé est exactement
   celui imposé ;
3. le vérificateur **refuse** ensuite un vrai `409 MEDIA_INTENT_CONFLICT` produit par l'API, un corps au bon statut
   mais au mauvais code, et des corps au bon statut/code contenant `sha256` ou `byteSize` divulgués.

Le témoin n'instrumente que la fixture du test ; le produit reste inchangé.

## 5. Preuves exécutées

Environnement : Node 24.22.2 portable, PostgreSQL 17.11, conteneur jetable `drivy-t1-97-pg`
(`postgres:17-alpine@sha256:b0f9560a…`, port loopback 55497, base `drivy_test`), une seule campagne à la fois.

| Commande | Résultat |
|---|---|
| RED : prédicat historique appliqué à la réponse forcée (`expect(collision.body).not.toMatch(/sha256\|byteSize\|409/)`) | **échec** `AssertionError: expected '{"type":"urn:drivy:problem:media_not_…' not to match /sha256\|byteSize\|409/` — symptôme I2 reproduit sans aléa |
| `npx vitest run test/messaging-media.integration.test.ts -t "ne confond pas"` (avec le prédicat historique) | 1 échec / 22 ignorés, exit 1 |
| `npx vitest run test/messaging-media.integration.test.ts` (correctif) | **23 tests réussis**, exit 0 |
| `npx tsc --noEmit` | exit **0** |

Aucune autre suite n'a été relancée (ni les 1 049 tests API, ni les 881 tests web) : le produit est inchangé et la
prochaine campagne complète appartient au candidat final. Le test de stabilité ne modifie ni timeout, ni retry, ni
assertion métier.

## 6. Cadre et limites

- Modèle effectif : `opencode-go/deepseek-v4.1-flash` (OpenCode), sans variante d'effort.
- Skills Superpowers chargés : `systematic-debugging`, `test-driven-development`, `verification-before-completion`
  (reproduction déterministe avant correctif, RED/GREEN observés, vérification finale par commandes réelles).
- Codebase Memory : projet `drivy-issues-medias-97`, racine `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-97`,
  réindexé à la tête `6ae15917` (`indexed_at=2026-11-05T01:51:37Z`, `ready`) ; recherche `messaging media integration
  test collision` puis lecture directe du source et des artefacts I2.
- Périmètre : seul `apps/api/test/messaging-media.integration.test.ts` est modifié, plus ce document. Aucun produit,
  migration, contrat, dépendance, lock, infra/workflow, `STATUS` ou conception.
- Limites : la correction fiabilise cette assertion précise et la classe de défaut qu'elle représente (sous-chaîne dans
  un identifiant) ; elle ne prétend pas auditer les autres assertions du dépôt. Les délais Chromium à froid de l'autre
  harnais sont un constat distinct, hors de ce lot.
