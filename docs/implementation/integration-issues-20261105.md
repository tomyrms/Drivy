# I2 — réunir les lots relus et vérifier le candidat local

Intégration locale et vérification, 5 novembre 2026. Tâche Orca `task_4af327acad6f`,
dispatch `ctx_0fe4874cde03`, worker `orca_session_id:e0bc243a-f5ce-4614-81d8-a7de9c935ce0`.

- Worktree : `C:/Users/jtoma/orca/workspaces/Drivy/integration-issues-20261105`
- Branche : `tomyrms/integration-issues-20261105`
- Base vérifiée avant toute opération : `b91e173b2e41f414a553d315fac17a0b6c82c508`, arbre propre
- **SHA produit** des onze fusions, avant cette mise à jour : `9b50c597b8a0d511954735fff1dff830097204d3`
- **SHA final** complet : celui du commit de ce rapport, indiqué dans `git log -1` et dans la
  livraison Orca (un fichier ne peut pas citer son propre SHA avant d'être créé).
- Aucune publication, PR, CI distante, fusion `master`, activation ni déploiement.
- Aucun correctif produit ou de test écrit par cette tâche : elle fusionne et vérifie.

## Préflight effectif

| Élément | Constat réel |
|---|---|
| Modèle | `opencode-go/deepseek-v4.1-flash` (OpenCode Go, identifiant relevé par l'outil `models`) ; variantes `low/high/max` existantes mais **aucun effort demandé ni exposé**. Aucun changement de modèle ou de fournisseur. |
| Superpowers | `verification-before-completion` effectivement chargé depuis `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\verification-before-completion`. `test-driven-development` et `systematic-debugging` **non applicables** : aucune ligne de produit ni de test produite, aucun défaut corrigé ici. |
| Codebase Memory | Projet propre à la racine exacte du worktree : `C-Users-jtoma-orca-workspaces-Drivy-integration-issues-20261105`, indexé **par chemin absolu** avant fusion (40 632 nœuds / 178 856 arêtes) puis laissé à jour après chaque fusion par le watcher du projet : **55 045 nœuds / 216 667 arêtes**, `status: ready`. Aucun index de worktree parent utilisé comme preuve. |
| Node | 24.22.2 portable (`C:/Users/jtoma/AppData/Local/Temp/drivy-orchestration-20261104/node-v24.22.2-win-x64`), injecté dans le `PATH` du processus seulement ; npm 11.19.1. |
| Docker | Inventaire avant création : 6 conteneurs actifs (`idrive-*`, projet sans rapport) et 25 au total, tous laissés intacts. Aucun arrêt, aucune purge. |
| Apple | Xcode/Swift/simctl **absents** de ce poste : aucune compilation, aucun XCTest, aucun simulateur, aucun relais Apple exécuté. |

## Phase A — six fusions mécaniques

Chaque SHA a été vérifié (`git cat-file -t` → `commit`), comparé à la tête de sa branche source
après l'opération (six concordances exactes) et contrôlé non-ancêtre de la base avant fusion.

| Ordre | Branche source | Tête fusionnée | Merge `--no-ff` | Fichiers | Delta |
|---|---|---|---|---|---|
| 1 | `tomyrms/issues-medias-outbox-97` | `541768e9a368a68c546053a77c28aa3b57616f91` | `553f5d0e51158d9a7bbe7a5aa4dd4996aa8b4100` | 2 | +19 / −10 |
| 2 | `tomyrms/issues-medias-relais-reel-97` | `ce6bafdfc36da0e7f8355cdde2954e5781891801` | `eb1c98e42fb39bf1adc1c66ebdd6ea042c5671ba` | 5 | +1638 / −5 |
| 3 | `tomyrms/issues-reprise-native-106` | `bc2c53cbaae6fa719e6203ea77119a753d6780d7` | `613252facb7970e3b5cde19de8ecfd317a4a6699` | 6 | +626 / −8 |
| 4 | `tomyrms/issues-sortie-brouillon-106` | `9e5748b6520dd199131c22edd14e0f91b92d8f3a` | `15d4f47c1f72de59d63dc4af7663ab154a4b366f` | 5 | +397 / −18 |
| 5 | `tomyrms/issues-cours-processus-37` | `5b4fb1e0cf98bbf25d13079708c4be53188a904a` | `b8059f30fa7b87094ba8b65cbee40e8fb34f7f98` | 3 | +542 / −0 |
| 6 | `tomyrms/issues-garde-recuperation-50` | `3d39c4f9694b5672a51c8739a6fbdb940d9bf77c` | `fd62668704a93c5036a04307a66967e98e858ec0` | 6 | +1424 / −0 |

Six fusions, **zéro conflit**, aucune résolution manuelle, ni squash, ni rebase, ni `reset`/`clean`,
aucune réécriture des sources. Total Phase A : **27 chemins, +4646 / −41**, `git diff --check` exit 0.

### Preuve d'équivalence des sources

Les six commits ont des bases différentes : `627bd4bb` (outbox), `62850171` (relais), `e2edc85e`
(L1b, U106, C37, R50). Le chevauchement entre les chemins livrés et les chemins modifiés par la base
a été calculé **avant** chaque fusion : **0 chemin commun** pour les six branches — ce qui explique
l'absence de conflit, et non une résolution silencieuse.

| Contrôle après fusion | Résultat |
|---|---|
| Union des 27 chemins livrés retrouvée dans `b91e173b..HEAD` | 27/27, aucun manquant, aucun supplémentaire |
| Blob de chaque chemin fusionné comparé au blob de la tête qui le livre | **0 divergence** sur 27 |
| Fichiers verrouillés/config dans le diff (`package-lock`, `package.json`, `.npmrc`, `tsconfig*`, `compose`, `project.yml`, `Package.resolved`, `Cargo*`, `.github/**`, `scripts/ios/**`) | **aucun** |
| Conception et contrat (`Drivy_Conception_v3_17_2026-09-20/`, `openapi.yaml`) | **inchangés** |
| `git merge-base --is-ancestor` des six têtes | exit 0 pour les six |
| Branches sources après l'opération | têtes identiques aux six SHA exigés |

## Phase B — exception M97 autorisée par le porteur

Tête exacte transmise par le coordinateur : `3dbbe101730aefbe7fc10ef24937b7efffd63ff8`, parent
`b91e173b2e41f414a553d315fac17a0b6c82c508`.

| Élément | Constat |
|---|---|
| Merge local `--no-ff` | `d6d742ee3ff936c45ded547307672b72a2a49984` (parents `fd626687` + `3dbbe101`) |
| Chemins | 3 : `MessagingMediaCoordinator.swift`, `MessagingMediaCoordinatorTests.swift`, `messaging-media-97-journey.md` — **+129 / −31** |
| Blobs comparés à `3dbbe101` | identiques (`0e11a30e`, `800e3fcc`, `73e10e4f`) |
| Chevauchement avec les 27 chemins de Phase A | aucun |
| `git diff --check` | exit 0 |

Lecture de source avant fusion (contrôle d'identité, sans éditer) :

- les trois blocs `catch` de `MessagingMediaCoordinator` préservent désormais
  `MessagingMediaRuntimeFailure` ; `MessagingMediaRuntimeFailure`
  (`MessagingMediaRuntimeContracts.swift:24`) et `MessagingFailure`
  (`MessagingContracts.swift:75`) sont deux `enum` distincts, donc l'ordre des `catch` dans le
  troisième bloc ne réintroduit pas le mapping fautif ;
- le helper de délai des tests devient `throws`/`Try` avec échéance explicite et un scénario
  « tâche non coopérative » ajouté ; aucune assertion métier retirée (seuls des `_ = try?` sur des
  valeurs non utilisées).

Conséquence pour les validations : `git diff --name-only fd626687..HEAD -- apps/api/src apps/web
infra package.json package-lock.json .github` est **vide** (seuls des scripts et documents neufs
s'ajoutent avec Q131, puis un fichier de test API avec S131 — voir le gel final). Les campagnes API,
web et scripts exécutées sur l'arbre `fd626687` restent donc valides **par identité de source** pour le
produit du candidat final ; aucune n'a été rejouée, et aucun résultat Swift n'est transféré. Le fichier
`apps/api/test/messaging-media.integration.test.ts`, modifié par S131 après ces campagnes, dispose de sa
propre preuve ciblée héritée (23 tests PostgreSQL verts, `tsc` exit 0 au SHA source).

Delta total `b91e173b..HEAD` (hors rapport) : **49 fichiers, +7274 / −97** (après le gel final ci-dessous).

## Gel final — trois fusions autorisées (S131, N106, U106-L2)

Fusions locales `--no-ff` dans l'ordre imposé, sur l'arbre `58121dcb` vérifié propre.

| Ordre | Lot | Tête fusionnée | Merge local | Fichiers |
|---|---|---|---|---|
| 9 | S131 — stabilité du test média 409 | `921eafc39cd1daeccbb0ec3938aec2f0e50057f7` | `e79658244954634987a34dfce911dcef8ed7b65a` | 2 : test API + rapport |
| 10 | N106 — admission d'envoi bornée | `54060efd786dc8a3126f1733af7acc418da8b7f7` | `a2c73f2b51f5a1b084311ad2a67e61e289813c06` | 5 : client, nouvelle admission, 2 tests, rapport |
| 11 | U106-L2 — annulation avant transport | `5c3c378a7b60a1bb2877c5521dd2e41edd3a48f8` | `9b50c597b8a0d511954735fff1dff830097204d3` | 6 : vue, workspace, revue visuelle, 2 tests, rapport |

**Aucun conflit** sur les trois fusions, aucune résolution manuelle. Le troisième merge est propre parce
que N106 (`54060efd`, dont le parent est `d5c9dee0`) est entré avant U106-L2 : la base de fusion devient
`d5c9dee0`, si bien que les deux branches ne modifient plus les mêmes chemins.

### Identité des sources et chevauchement expliqué

| Contrôle | Résultat |
|---|---|
| Chemins importés (union des trois deltas) | **18 entrées / 15 chemins uniques** |
| Blob de chaque chemin comparé à son propriétaire final | **15 identiques** ; **3 écarts expliqués** ci-dessous |
| Correction N106 (`54060efd`) sur ses trois fichiers | **intacte** (`SchoolCommandSendAdmissionTests.swift`, `SchoolPlanningAdmission106Tests.swift`, `planning-send-admission-106-20261105.md` = blobs de `54060efd`) |
| `git diff --check` / arbre | exit 0 / propre |
| Workflows, lockfiles, `package.json`, `infra/**` | inchangés |
| `apps/api/src`, `apps/web` (produit) | **aucun delta** par rapport à `58121dcb` |
| Ancien HEAD et têtes sources | **13 ancêtres vérifiés, 0 manquant** (base, `58121dcb`, 8 têtes antérieures, 3 nouvelles) |

Les **trois écarts** sont ceux que la consigne nomme : U106-L2 porte encore la version *antérieure* à la
correction de N106 des deux fichiers de tests et du rapport d'admission. Après la fusion ordonnée,
c'est **`54060efd` qui fait foi** sur ces trois chemins, exactement comme demandé (« la correction
`54060efd` doit rester intacte ») ; aucun autre chemin n'est touché par cette superposition. Ce n'est
donc pas une divergence silencieuse mais la conséquence attendue de l'ordre des fusions.

### Preuves héritées et nouveau test

- **Aucune campagne globale relancée** : le produit API (`apps/api/src`) et tout `apps/web` sont
  byte-identiques à l'arbre des campagnes I2 (`58121dcb`), donc les résultats API 1048/1049 exit 0 et
  web 880 + 1 attendu exit 0 restent valides **par identité de source**, pas comme nouvelles exécutions.
- **Seul `apps/api/test/messaging-media.integration.test.ts` change** (S131). Sa preuve est ciblée et
  héritée du lot : **23 tests PostgreSQL verts et `tsc` exit 0** au SHA source, exécutés par son auteur
  avec une PostgreSQL jetable. Le correctif est déterministe et conforme à ce qui avait été constaté
  dans le rapport I2 : vérification par `status`/`type`/`code` et liste fermée de champs, `requestId`
  imposé par une instrumentation de **fixture** uniquement (`app.addHook('onRequest')`), plus des cas
  négatifs (409 réel, code erroné, `sha256`/`byteSize` divulgués) qui doivent échouer.
- **Aucun Docker ni service lancé** pour ce gel : trois fusions mécaniques et des contrôles `git`.
- **Q131 n'a pas été lancé** contre I2 ; son benchmark reste figé sur `e2edc85e`.

### Limite Apple de ce gel

Les nouveaux tests Swift et UI (`SchoolCommandSendAdmissionTests`,
`SchoolPlanningAdmission106Tests`, `SchoolPlanningCancellation106Tests`,
`SchoolPlanningCancellationUITests`) sont **NON COMPILÉS et NON EXÉCUTÉS** sous Windows : aucun Xcode
disponible. Leur présence dans les répertoires suffit à la découverte par `unit_test_scope=all`, et
`SchoolPlanningCancellationUITests` exige un lancement UI distinct ; aucune preuve n'est transférée.

## Ajout Q131 — harnais de mesures web (8e fusion, autorisée après les têtes fixées)

Fusion **locale et additive** de `7cefeb415623ab5e36f5952d203bf19e28871e5c` (parent `1a6a27da`),
autorisée par le coordinateur après les sept premières têtes, sans écraser de travail.

| Élément | Constat |
|---|---|
| Merge `--no-ff` | `59b33ea5a8900638086ba247e58e6b037e40ce9a` (parents `4925882d` + `7cefeb41`) |
| Base de la branche | `e2edc85e` (candidat publié) ; merge-base avec I2 = `e2edc85e` |
| Chemins | 8 fichiers **tous nouveaux** : `docs/implementation/web-reactivity-measures-131-20261105.md`, `scripts/dev/measure-web-reactivity-131.ts`, `scripts/dev/reactivity-131/{fixture,guards,guards.test,observe,stats,stats.test}.ts` — **+383 / −0** |
| Blobs comparés à `7cefeb41` | identiques sur les 8 (`830466fb`, `4ac05f93`, `4fdd94be`, `bfa2068f`, `ea33ed58`, `47db98ad`, `45ed2b13`, `7c03e114`) |
| Chevauchement avec les chemins déjà modifiés par I2 | aucun ; ces 8 chemins n'existaient pas à `HEAD` avant fusion |
| Fichier produit, lock, workflow, infra dans ce lot | **aucun** |
| `git diff --check` / arbre | exit 0 / propre |

### Identité des preuves Q131 (héritées, non rejouées)

Ce harnais qualifie **intentionnellement** les sources web de `e2edc85e` : `measure-web-reactivity-131.ts:22`
fixe `sha = 'e2edc85ed092237016620079d52d11eb7a2d02b5'`, l'injecte en `__DRIVY_BUILD_SHA__` et, ligne 23,
refuse la campagne si `git diff e2edc85e -- apps/web` n'est pas vide, puis exige que le build d'entrée
porte la même identité.

Sur I2, cette garde est **légitimement en échec** : `git diff e2edc85e -- apps/web` retourne
`apps/web/server/rate-limit.ts`, `apps/web/server/recovery-direct-guard.ts`,
`apps/web/server/recovery-direct-guard-main.ts` et `apps/web/test/recovery-direct-guard.test.ts`
(lot R50). Le harnais **n'a donc pas été relancé** sur I2, ses gardes n'ont pas été contournées et aucune
ancienne preuve n'a été renommée. Le contrôle ci-dessus est la garde elle-même, lue et rejouée comme
commande `git`, **pas** un lancement de benchmark.

Preuves conservées comme mesures ciblées **sur `e2edc85e` uniquement** (rapport du lot, artefacts dans
l'ancien worktree, non recopiés ici) : campagne PASS exit 0, **42 échantillons dont 3 chauffes → 39
mesures retenues**, **14 accès positivement confirmés**, **9 verdicts initiaux sans faux confirmé**
(3 perdus, 3 refusés, 3 comptes changés), **3 reprises positivement confirmées**, 5 captures Chromium ;
empreinte du harnais `8621dbb398dbb900806439b82380f2a3e89021f1f9584f4fa2f7516cda4d24a5`, Chromium
153.0.8010.12, Node v24.22.2.

Limites à ne pas dépasser en les citant : n=3 à 0/1 s et n=1 à 5/15 s, Windows/Chromium de bureau
seulement, production synthétique sans base ni appareil physique ; l'oracle de stockage ne couvre que
les métadonnées de `updateMember`, **pas** la durabilité des corps ; aucune mesure Safari/iPad,
VoiceOver, zoom natif ni grande taille de texte. Ces chiffres **ne qualifient pas** I2 : ils décrivent
`e2edc85e`. Aucune campagne API/web d'I2 n'a été rejouée pour ce seul ajout de scripts et de
documentation.

## Vérifications exécutées — commandes et codes de sortie

Node 24.22.2 portable (version affichée à chaque campagne), dépendances issues des lockfiles
existants, dans ce seul worktree.

| Commande | Résultat réel |
|---|---|
| `npm ci --no-audit --no-fund` | exit 0, 111 paquets |
| `npm ci --prefix apps/web --ignore-scripts` | exit 0, 153 paquets |
| `npm ci --prefix infra/dev` | exit 0, 1 paquet (`playwright-core` verrouillé) |
| `npm run typecheck` (API, `tsc --noEmit`) | **exit 0** |
| `npm run build` (API) | **exit 0** |
| `npm test --workspace @drivy/api` — **exécution 1** | **exit 1** : 94 fichiers, 1049 tests, 1047 réussis, **1 échec**, 1 ignoré |
| `npm test --workspace @drivy/api` — **exécution 2** | **exit 0** : 94 fichiers, **1048 réussis, 0 échec, 1 ignoré**, 710,9 s |
| `npm run typecheck --prefix apps/web` | **exit 0** |
| `npm run build --prefix apps/web` | **exit 0** |
| `npm test --prefix apps/web` — **exécution 1** | **exit 1** : 81 fichiers, 879 réussis, **1 échec**, 1 échec attendu |
| `npm test --prefix apps/web` — **exécution 2** | **exit 0** : 81 fichiers, **880 réussis, 0 échec, 1 échec attendu** (881), 21,7 s |
| `node --test --import tsx scripts/messaging-media-relay-qualification.test.mjs` | **exit 0** : tests 23, pass 23, fail 0 |
| `node --test --import tsx scripts/messaging-relay-qualification.test.mjs` | **exit 0** : tests 9, pass 9, fail 0 |
| `npx tsc --noEmit --target ES2023 --module NodeNext --moduleResolution NodeNext --strict --skipLibCheck --esModuleInterop --types node --resolveJsonModule scripts/qualification/messaging-media-fixtures.mts scripts/messaging-relay-qualification.mts` | **exit 0** |
| `node node_modules/typescript/bin/tsc -p infra/dev/tsconfig.json` | **exit 2** : exactement les **3 diagnostics hérités** (voir plus bas) |

Environnement des campagnes : PostgreSQL 17.11 (`postgres:17-alpine@sha256:b0f9560a…`) en
`127.0.0.1:55460`, Mailpit `v1.31.2@sha256:74d609a4…` en `127.0.0.1:18030`/`18085`, base synthétique
`drivy_test` (+ `drivy_web_test`), rôle synthétique `drivy_test` identique à la CI
(`TEST_DATABASE_URL`, `WEB_COMMAND_TEST_DATABASE_URL`, `TEST_SMTP_PORT`, `TEST_MAILPIT_URL`).
`fileParallelism:false` conservé ; aucun test, timeout, skip ou fichier de configuration modifié.

### Ce que l'exécution 1 de l'API a révélé (échec transitoire, distinct des échecs connus)

`test/messaging-media.integration.test.ts:312` :

```
AssertionError: expected '{"type":"urn:drivy:problem:media_not_…' not to match /sha256|byteSize|409/
Received: {"type":"urn:drivy:problem:media_not_found",…,"code":"MEDIA_NOT_FOUND","requestId":"dff23de8-9bad-409d-bd7d-1e600974f736"}
```

- Le fichier est **inchangé** depuis la base : blob `311ab1f3` identique à `b91e173b` **et** à la tête
  T1 `6ae15917` ; aucun commit de la phase A ne le touche.
- La réponse est correcte (`status: 404`, `code: MEDIA_NOT_FOUND`) ; l'assertion vise le statut 409
  mais sa regex cherche la sous-chaîne `409` **n'importe où** dans le corps, y compris un
  `requestId` aléatoire.
- Reproduction minimale (script synthétique, `artifacts/i2-20261105/regex-flake-repro.mjs`) :
  `observed_body_matches_/409/ = true` sur ce corps, `status_field_value = 404`, et **1622/200000
  UUID (0,811 %)** contiennent `409` — ce qui explique l'intermittence.
- Le même fichier lancé seul **deux fois** donne **22/22, exit 0** les deux fois, et la campagne
  complète relancée donne **exit 0** sans modification quelconque.

C'est un **défaut de test existant, probabiliste (~0,8 % par exécution)**, pas un défaut produit et
pas un artefact d'intégration. Il n'a pas été corrigé par I2 ; son auteur l'a corrigé ensuite dans
S131 (fusionné au gel final), en vérifiant le statut et le code plutôt qu'une sous-chaîne du corps.

### Ce que l'exécution 1 du web a révélé (dépassement de délai transitoire)

`test/pending-recovery-106.test.tsx` → scénario `metadata` : le harnais lance Chromium puis
`page.goto` du fixture servi par Vite ; **`Timeout 30000ms exceeded`** pendant la navigation, à froid.
Le même harnais exécuté seul **après** : `result:"PASS"`, **exit 0**, moteur déclaré
`{"name":"Chromium","version":"153.0.8010.12"}` ; la suite web complète relancée est **exit 0**.
Aucun navigateur de substitution n'a été utilisé et aucun timeout n'a été modifié.

### Échecs attendus, ignorés et historiques — distingués

| Statut | Cas | Preuve |
|---|---|---|
| Ignoré, déclaré | `course-worker-process.integration.test.ts` — « SIGTERM pendant l'attente » (`skipIf` plateforme) | 1 ignoré dans les deux exécutions ; le signal POSIX reste à exécuter sous Linux |
| Échec attendu, historique | `apps/web/test/course-model-fuseaux-limites.test.ts:131` (`it.fails`, heure doublée) | fichier identique à la base ; 1 échec attendu dans les deux exécutions web |
| Diagnostics hérités (infra/dev) | `check-v3-agenda-acceptance.ts(10,17)`, `check-v3-entry.ts(13,41)`, `measure-web-entry.ts(13,7)` | exit 2, **exactement ces trois** ; aucun diagnostic du nouveau `scripts/dev/check-recovery-direct-guard-50.ts` |
| Transitoires, rejoués verts | `/409/` (API), `page.goto` (web) | détail ci-dessus, aucun résultat ancien réutilisé |

### Isolation du fichier C37 pendant la campagne réelle

`apps/api/test/course-worker-process.integration.test.ts` crée sa propre PostgreSQL et réécrit
`process.env.TEST_DATABASE_URL` dans son runtime. Vérifié pendant la campagne, pas supposé :

- conteneur propre `drivy-c37-pg-b42a0522` observé sur `docker ps` du **01:54:59 au 01:55:49**, puis
  **absent** — supprimé par son `afterAll` ;
- **0 rôle `drivy_c37%`** dans la base de campagne `drivy_test` (les rôles techniques n'existent que
  dans son conteneur) ;
- la même passe compte **94 workers isolés** (un par fichier) et 93 des 94 fichiers réussissent,
  l'unique échec étant la regex `/409/` d'un autre fichier ; la base de campagne reste la cible des
  autres fichiers d'intégration, qui passent.
- Node majeur vérifié par le test lui-même (`24`), sinon refus explicite plutôt qu'une preuve décalée.

### Recette R50 — preuve héritée par identité de source

`RECOVERY_DIRECT_GUARD_RECIPE=1 npx tsx scripts/dev/check-recovery-direct-guard-50.ts` (24 contrôles,
exit 0, Keycloak 26.7.4 + Mailpit aux digests verrouillés) a été exécutée par l'auteur au SHA source
`3d39c4f9`. Les deux fichiers de la recette et le garde sont **byte-identiques** à cette tête dans le
candidat (`recovery-direct-guard.ts`, `recovery-direct-guard-main.ts`, `rate-limit.ts`,
`check-recovery-direct-guard-50.ts`), et aucun fichier `infra/**`, realm ou image n'est modifié par
l'intégration. La recette n'a donc **pas** été relancée à l'aveugle ; elle reste une preuve du SHA
source, pas une exécution de cette tâche. Ses **38 tests de frontière** sont, eux, exécutés dans la
suite web intégrée (38/38).

## Swift : inventaire statique seulement, **aucune exécution**

Aucune compilation, aucun XCTest, aucune capture : Xcode est absent. Les seules affirmations
possibles sont des comptes de méthodes dans les fichiers, pas des résultats.

| Fichier (candidat) | Classe / suite | Méthodes présentes (statique) |
|---|---|---|
| `apps/ios/DrivyTests/MessagingMediaRealRelayTests.swift` (Q97) | `MessagingMediaRealRelayTests` | 2 XCTest |
| `apps/ios/DrivyTests/SchoolPlanningRecovery106Tests.swift` (L1b) | `SchoolPlanningRecovery106Tests` | 15 `@Test` (swift-testing) |
| `apps/ios/DrivyTests/SchoolOnboardingExitTests.swift` (U106) | `SchoolOnboardingExitTests` | 6 `@Test` (swift-testing) |
| `apps/ios/DrivyTests/MessagingMediaOutboxTests.swift` (fixture T2b3) | `MessagingMediaOutboxTests` | 40 XCTest (2 scénarios modifiés) |
| `apps/ios/DrivyTests/MessagingMediaCoordinatorTests.swift` (exception M97) | `MessagingMediaCoordinatorTests` | 44 XCTest (1 scénario d'échéance ajouté) |
| `apps/ios/DrivyUITests/MessagingMediaUITests.swift` (base U97) | `MessagingMediaUITests` | 5 XCTest |
| `apps/ios/DrivyTests/SchoolCommandSendAdmissionTests.swift` (N106) | `SchoolCommandSendAdmissionTests` | 7 `@Test` (swift-testing) |
| `apps/ios/DrivyTests/SchoolPlanningAdmission106Tests.swift` (N106) | `SchoolPlanningAdmission106Tests` | 17 `@Test` (swift-testing) |
| `apps/ios/DrivyTests/SchoolPlanningCancellation106Tests.swift` (U106-L2) | `SchoolPlanningCancellation106Tests` | 9 `@Test` (swift-testing) |
| `apps/ios/DrivyUITests/SchoolPlanningCancellationUITests.swift` (U106-L2) | `SchoolPlanningCancellationUITests` | 3 XCTest |

Sélections préparées pour une future campagne distante autorisée, **sans rien lancer ni modifier** :

1. **Campagne métier complète** : `unit_test_scope=all` → `-only-testing:DrivyTests`
   (`scripts/ios/test-selection.sh:58`), qui découvre les fichiers par répertoire. Cette sélection
   satisfait la condition `relay_required=1` (lignes 100-105, garde `-z "$ui_test_suite"` ligne 102),
   donc le **relais jetable est démarré** :
   `MessagingMediaRealRelayTests` et `MatrixMessagingRelayIntegrationTests` peuvent s'exécuter.
2. **Campagne UI ciblée** : `ui_test_suite=MessagingMediaUITests` avec `ui_ipad=1` — lancement
   **distinct** (une sélection UI désactive `relay_required`, ligne 102). `scripts/ios/**` et
   `.github/**` sont **intacts** dans le diff.

## Codebase Memory après fusion

Recherches de contrôle exécutées sur l'arbre fusionné, projet propre à ce worktree :

- `MessagingMediaRealRelayTests` → classe et `exerciseRealRelay` dans
  `apps/ios/DrivyTests/MessagingMediaRealRelayTests.swift` ;
- `SchoolPlanningRecoveryPolicy` → `admission` dans
  `apps/ios/Drivy/SchoolConfigurationAPI/SchoolPlanningRecoveryPolicy.swift` ;
- `buildRecoveryDirectGuard` → `apps/web/server/recovery-direct-guard.ts` (l. 239-405) et la recette
  `scripts/dev/check-recovery-direct-guard-50.ts` ;
- `worker-process` / `sleep` → `apps/api/test/fixtures/course-worker-process/worker-process.ts` ;
- `boundedValue` → helper de test désormais `throws` (`MessagingMediaCoordinatorTests.swift:90-100`) ;
  `reconfirmed` → `MessagingMediaCoordinator.reconfirmed` (`MessagingMediaCoordinator.swift:702-740`) ;
- `verifyMetadataOnly` et `accessVerdictMatches` → `scripts/dev/reactivity-131/guards.ts` (l. 5-16 et
  19-25), le harnais Q131 étant indexé après sa fusion.

Limites de couverture déclarées par l'index : 89 fichiers en lecture partielle, 4 fichiers inutilisables
pour l'analyseur (`openapi.yaml`, 3 migrations SQL), 9 répertoires exclus par conception (`node_modules`,
`dist`, `.claude`,…). Ces fichiers ont été lus directement quand un contrôle en dépendait ; le graphe ne
prouve ni compilation ni comportement.

## Ressources créées, arrêtées et nettoyées

| Ressource | Nom | Fin de vie |
|---|---|---|
| PostgreSQL 17.11 | `drivy-i2-20261105-pg`, `127.0.0.1:55460`, `--rm` | `docker stop` exit 0, conteneur supprimé |
| Mailpit v1.31.2 | `drivy-i2-20261105-mailpit`, `127.0.0.1:18030/18085`, `--rm` | `docker stop` exit 0, conteneur supprimé |
| PostgreSQL jetable C37 | `drivy-c37-pg-b42a0522` | supprimé par le test lui-même en `afterAll` |

Contrôle final : aucun conteneur `drivy-i2-*`, `drivy-c37*`, `drivy-opening-e2e*` ni `drivy-r50-*` ;
les **6 conteneurs `idrive-*`** sont dans le même état qu'à l'inventaire ; aucun `prune`, aucun volume
nommé créé, aucune image supprimée, aucune base réelle touchée. Le fichier temporaire contenant le mot
de passe PostgreSQL synthétique a été supprimé ; aucun secret, jeton ni donnée de personne réelle n'est
écrit dans `artifacts/i2-20261105/` (répertoire ignoré par Git).

## Limites et restes

- **Aucune qualification Apple** : pas de compilation, pas de XCTest, pas de relais réel, pas de
  capture native. Les 52 tests métier et 28 tests UI mentionnés par la spec ne sont **pas** exécutés ;
  seuls leurs fichiers sont présents dans le candidat.
- **SIGTERM POSIX** du service des cours reste **non exécuté** (Windows seulement) ; il faudra le
  runner Linux.
- **Recette R50** : preuve **héritée** du SHA source par identité de fichiers, pas une exécution de
  cette tâche.
- Le défaut `/409/` de `messaging-media.integration.test.ts` est désormais **corrigé par son auteur**
  dans S131 (fusionné) ; il n'était pas corrigé par I2. Le dépassement de délai à froid du harnais
  `pending-recovery-106` reste **non corrigé** : hors périmètre d'un intégrateur.
- Aucun push, PR, CI distante, `merge master`, déploiement, activation ni clôture d'issue ; `STATUS.md`
  et le registre restent au coordinateur. Le harnais Q131 est désormais **fusionné** comme lot
  documentaire/harnais, mais ses mesures restent des preuves ciblées sur `e2edc85e` et ne sont **pas**
  rejouables sur I2 sans contourner sa garde `apps/web`.
- Les lots **N106** et **U106-L2** sont désormais intégrés (gel final), mais leurs tests Swift restent
  **non compilés/non exécutés** sous Windows et la décision de les qualifier sur Apple revient au
  coordinateur.
- Zéro retour correctif consommé pour cette tâche ; les plafonds des lots sources sont inchangés.
