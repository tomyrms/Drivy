# Intégration locale des neuf branches — 4 novembre 2026

Rapport de la tâche I1 (Orca, `task_3ce04dae5082` / dispatch `ctx_faa10c1a6f57`).
Autorisation du porteur : intégration **locale** des neuf têtes dans un worktree neuf, puis
vérifications locales. Aucune publication, aucune PR, aucune CI distante, aucun merge vers
`master`, aucun déploiement, aucune clôture d'issue n'était couverte par cet accord.

- Worktree : `C:/Users/jtoma/orca/workspaces/Drivy/integration-issues-20261104`
- Branche : `tomyrms/integration-issues-20261104`
- Base de départ, vérifiée avant toute opération : `0bdaf32483e3dc4dba9e75056eedb0c74cd43d4e`, arbre propre
- SHA intégré (produit, avant ce rapport) : `38980506d438c32fdc3bc9bf720b83dec7be84c8`
- Conception et contrat OpenAPI canonique 3.11.0 : **inchangés** (aucun chemin `Drivy_Conception_v3_17_2026-09-20/` ni `openapi.yaml` dans le diff)

## Préflight du worker

| Élément | Constat réel |
|---|---|
| Modèle effectif | `opencode-go/deepseek-v4.1-flash` — lu dans `C:\Users\jtoma\.config\opencode\opencode.json` (`model` et agent `build`), identique au modèle annoncé par le runtime de cette session. Variante `max` déclarée pour l'agent `build` ; révision 1017 et effort **non exposés** par le runtime, non vérifiables indépendamment. Aucun changement de modèle ou de fournisseur. |
| Superpowers | `verification-before-completion` et `systematic-debugging` effectivement chargés depuis `C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\`. `test-driven-development` **non applicable** : cette tâche n'écrit ni produit ni test, par consigne explicite. |
| Codebase Memory | Projet neuf et unique `drivy-integration-issues-20261104`, racine exacte `C:/Users/jtoma/orca/workspaces/Drivy/integration-issues-20261104`, indexé après fusion à `2026-11-04T19:19:31Z` : 53 017 nœuds, 202 223 arêtes, état `ready`. Aucun index voisin utilisé comme preuve. |
| Node | 24.22.2 portable (`C:/Users/jtoma/AppData/Local/Temp/drivy-orchestration-20261104/node-v24.22.2-win-x64`), injecté dans le `PATH` des processus seulement ; npm 11.19.1 ; `node --version` relu dans chaque campagne. |
| Docker | Inventaire avant création : 19 conteneurs, tous `Exited`, aucun actif. Aucun conteneur étranger démarré, arrêté ou supprimé. |

## Manifeste des têtes et fusions

Chaque SHA a été vérifié (`git cat-file -e <sha>^{commit}`, type `commit`) et comparé à la tête de
sa branche avant fusion : **neuf concordances exactes**. Les branches sources sont restées
inchangées après l'opération (têtes relues en fin de tâche : identiques). `67c37282` (L1a) est
ancêtre de `b7584e0e` (exit 0) et `883581ad` (crypto) est ancêtre de `d3eccc36`, `31efca80`,
`53889611`, `bbc5c905` (exit 0 chacun) : ces deux têtes n'ont donc été ni rejouées ni cherry-pickées.

| Ordre | Branche source | Tête fusionnée | Commit de merge local | Fichiers du merge |
|---|---|---|---|---|
| 1 | `tomyrms/issues-recuperation-50` | `4c109d1921e65ae6c11154aae7cd4e65ddd97c54` | `9c5164bc3e49e1f43b6fde41336d31cce2e6e1cf` | 4 fichiers, +749 / −50 |
| 2 | `tomyrms/issues-reactivite-106` | `df463e9bc63d606fb665c9f982722f594b99a801` | `63635a03c5ec0d1c583c02a0852cf9192519209d` | 10 fichiers, +485 / −51 |
| 3 | `tomyrms/issues-suivi-web-106` | `b7584e0e4e7445dd485aef578d3af36b78c83a17` | `63a47292af79f7c1e5f51b04549f38dc3099c5f8` | 10 fichiers, +868 / −46 |
| 4 | `tomyrms/issues-medias-97` | `6ae15917f0c0670722237b02fd54aacf29620565` | `c743b3ce8d58ee5e63f14654b8e68072e9359eae` | 14 fichiers, +3152 / −14 |
| 5 | `tomyrms/issues-medias-contenu-97` | `d3eccc368b38f62d113cc4d5916bd16d37996f08` | `d38b50ab264f041d4144cadd0a7175b7843b15e4` | 18 fichiers, +4242 / −8 |
| 6 | `tomyrms/issues-medias-transport-97` | `31efca80dda758d0981556b1dbc1bd44b641c252` | `2c6757b25ec710a5cb875c3a7aec0a42e7c70f76` | 5 fichiers, +2450 / −0 |
| 7 | `tomyrms/issues-attente-native-106` | `e980b60820bd6d38b012f2c18fd1437695c90827` | `7de31d2b0993fefc24e73b196801b4b291da4c7a` | 3 fichiers, +250 / −34 |
| 8 | `tomyrms/issues-rouges-metier-131` | `538896117449ddd4599a383d0af737baaa7341a4` | `53ca110652243f7faa7cce1b0b812f533fb07223` | 8 fichiers, +475 / −4 |
| 9 | `tomyrms/issues-relais-diagnostic-78` | `bbc5c9058cb967310997f3d58fe7f970b0094310` | `38980506d438c32fdc3bc9bf720b83dec7be84c8` | 4 fichiers, +720 / −8 |

Neuf fusions `--no-ff`, **zéro conflit**, aucune résolution manuelle, ni squash, ni rebase, ni
réécriture des sources, ni `reset`/`clean`. Les commits de merge sont des commits à deux parents :
le journal `git log --merges 0bdaf324..38980506` relu en fin de tâche montre les neuf entrées avec
leurs parents exacts (`0bdaf324 4c109d19`, `9c5164bc df463e9b`, … `53ca1106 bbc5c905`).

## Preuve d'équivalence du résultat fusionné

Contrôle indépendant de la préparation (76 chemins / 7 partagés / 0 divergent), refait ici sur le
résultat, et non seulement sur les entrées :

| Contrôle | Résultat |
|---|---|
| Union des chemins `base…tête` pour les neuf branches | **76** chemins |
| Chemins du diff `base..HEAD` | **76** ; manquants **0**, supplémentaires **0** |
| Blob de chaque chemin fusionné comparé au blob de la tête qui le livre | **0 divergence** sur les 76 |
| Chemins partagés par plusieurs têtes | **7**, tous avec **un seul blob distinct** (médias crypto : source, fixture, tests, deux documents, script de génération, test Rust) |
| `git diff --check base..HEAD` | exit 0 |
| `git diff --shortstat base..HEAD` | 76 fichiers, +13 391 / −215 |
| Statut de l'arbre en fin de campagne | propre, aucun fichier non suivi |
| Lock/dépendance/config globale modifiés | **aucun** : aucun `package-lock.json`, `package.json`, `.npmrc`, `tsconfig*.json`, `compose.yaml`, `.github/**`, `project.yml`, `Package.resolved`, `Cargo.toml`/`Cargo.lock` dans le diff |

Les neuf SHA sources ont été recontrôlés ancêtres de `38980506` (`git merge-base --is-ancestor`,
exit 0 pour les neuf).

## Dépendances installées (verrouillées seulement)

Aucune dépendance nouvelle, aucun verrou modifié, aucun paquet global. Installations par
`npm ci` à partir des lockfiles **déjà présents à la base** :

| Commande | Exit | Note |
|---|---|---|
| `npm ci` (racine, workspace `apps/api`) | 0 | 111 paquets ; avertissement informatif `esbuild` postinstall non approuvé, sans effet sur les campagnes |
| `npm ci --prefix apps/web --ignore-scripts` | 0 | 3 vulnérabilités modérées signalées par l'audit npm, antérieures et hors périmètre |
| `npm ci --prefix infra/dev` | 0 | uniquement `playwright-core@1.63.0`, lockfile indépendant documenté dans `docs/implementation/dev-identity.md` |

Le troisième ensemble est nécessaire aux harnais navigateur exigés (`infra/dev/browser.ts`
réexporte `playwright-core`). Il a été installé **après** un premier passage de la suite web qui
échouait faute de ce module (détail en « Défauts constatés »).

## Vérifications exécutées au SHA `38980506`

| Commande | Résultat réel |
|---|---|
| `npm run typecheck` (racine → `@drivy/api`, `tsc --noEmit`) | **exit 0** |
| `npm run build` (racine → `@drivy/api`, `tsc -p tsconfig.build.json`) | **exit 0** |
| `npm test --workspace @drivy/api -- --reporter=default --reporter=json --outputFile=…` | **exit 0** — **93 fichiers, 1042 tests, 1042 réussis, 0 échec, 0 ignoré**, 543 s |
| `npm --prefix apps/web run typecheck` | **exit 0** |
| `npm --prefix apps/web run build` | **exit 0** (avertissement Vite antérieur sur `theme-init.js`, fichier hors diff) |
| `npm --prefix apps/web test -- --reporter=default --reporter=json` | **exit 0** — **80 fichiers, 842 réussis, 1 échec attendu**, 68 s |
| `npx tsx --test scripts/dev/check-school-account-recovery.test.ts` | **exit 0** — **24/24** |
| `ONBOARDING_E2E_DATABASE_URL=… npx tsx scripts/dev/check-school-opening.ts --extended=recovery` | **exit 0** — **151 contrôles**, `result.json` `PASSED` à `2026-11-04T19:16:31.795Z`, Chromium `153.0.8010.12`, suites étendues `["recovery"]` |
| `node --test scripts/ios/relay-diagnostics.test.mjs` (Node 24.22.2, OpenSSL 3.6.5 local) | **exit 0** — **9/9** |
| `node --import ./apps/web/node_modules/tsx/dist/loader.mjs scripts/dev/check-entry-continuity-120.ts` | **exit 0** — `PASS 12 checks; synthetic UI only` |
| `node --import ./apps/web/node_modules/tsx/dist/loader.mjs scripts/dev/check-pending-recovery-106.ts all` | **exit 0** — `{"result":"PASS"}` sur les quatre familles (conservation lecture/écriture/effacement, clavier et focus, rechargement, course d'échéance) |
| `npx tsc -p infra/dev/tsconfig.json` | **exit 2** — 7 diagnostics, détail ci-dessous |

### Campagne API avec PostgreSQL et Mailpit réels

Conteneurs éphémères à mon nom, sur ports loopback libres inventoriés avant création :
`drivy-i1-20261104-pg` (`postgres:17-alpine@sha256:b0f9560a…`, `127.0.0.1:55451`) et
`drivy-i1-20261104-mailpit` (`axllent/mailpit:v1.31.2@sha256:74d609a4…`, `127.0.0.1:18025/18080`).
Environnement aligné sur `qualification-checks.yml` : `TEST_DATABASE_URL`, `WEB_COMMAND_TEST_DATABASE_URL`,
`TEST_SMTP_PORT=18025`, `TEST_MAILPIT_URL=http://127.0.0.1:18080`, base `drivy_web_test` créée sur le
même serveur. `fileParallelism:false` de `apps/api/vitest.config.ts` **conservé** (fichier non modifié) :
aucune suite n'a tourné en concurrence sur la base.

Points historiquement rouges, vérifiés ici dans le JSON et non recopiés d'anciens rapports :

| Suite | Résultat |
|---|---|
| `test/g1d.integration.test.ts` | **27/27 réussis**, seule suite active sur la base à ce moment |
| `test/g1c.integration.test.ts` (SMTP/Mailpit) | **64/64 réussis** — Mailpit effectivement présent et configuré |
| `test/messaging-media.integration.test.ts` | 22/22 réussis |
| `test/messaging.integration.test.ts` | 12/12 réussis |

### Recette d'ouverture d'école `--extended=recovery`

Exécutée selon `school-opening-e2e.yml`, sur la base **neuve** `drivy_onboarding_e2e` créée pour
l'occasion (distincte de `drivy_test`), via `ONBOARDING_E2E_DATABASE_URL` sur le même PostgreSQL
synthétique. Le harnais compile le fournisseur d'identité contre la distribution verrouillée
(`infra/deploy/runtime-lock.json`, JDK 21 local), démarre un Keycloak 26.7.4 éphémère nommé
`drivy-opening-e2e-<uuid>` sur `127.0.0.1:8081`, et pousse son SMTP vers un Mailpit publié sur
`127.0.0.1:1025/8025` (`drivy-i1-20261104-mailpit-e2e`, même digeste verrouillé). Aucun SMTP réel,
aucune base réelle, comptes `@example.invalid` seulement. Le conteneur Keycloak a été retiré par le
harnais lui-même (contrôle final : aucun conteneur `drivy-opening-e2e*`). Le journal ne contient que
l'étape et des textes d'interface.

### Rejeu des harnais synthétiques d'entrée continue et de pending web

Automatisation existante seulement, aucun changement d'UI, aucun redesign, aucune conclusion
visuelle nouvelle. `check-entry-continuity-120.ts` a produit 12 contrôles et 33 captures
(`artifacts/entry-continuity-120/`) ; `check-pending-recovery-106.ts all` a produit un PASS et
39 captures (`artifacts/pending-recovery-106/`). La recette a produit 9 captures et son
`result.json` (`artifacts/onboarding-web-synthetic/`). **Je n'ai tiré aucun verdict visuel** :
l'inspection des captures revient au coordinateur.

## Vérification Codebase Memory après fusion

Projet unique `drivy-integration-issues-20261104`, racine exacte du worktree, réindexé **après**
les neuf fusions (`indexed_at` `2026-11-04T19:19:31Z`, `status: ready`, 53 017 nœuds / 202 223 arêtes).
Recherches effectuées sur les types partagés et leurs consommateurs dans l'arbre fusionné :

- `MessagingMediaTransport` : protocole et membres `upload`/`download`/`cancel` dans
  `apps/ios/Drivy/MessagingCore/MessagingMediaTransport.swift` (l. 28-32), reçus et échec borné ;
- `MessagingHTTPMediaTransport` : implémentation réelle `apps/ios/Drivy/MessagingAPI/MessagingHTTPMediaTransport.swift` (l. 164-588) ;
- `MessagingDecryptedContent` : provenance typée `MessagingContracts.swift` (l. 106-129) ;
- `MessagingMediaCryptography` : `seal`/`open` (l. 126-128, implémentation 200-222) ;
- `SchoolWaitMonitor` : phases, `run`, `retry`, `waitUntilIdle` et les annonces (`SchoolJoinUI/SchoolWaitMonitor.swift`) ;
- `SchoolCommandOutbox` : `pending`, `save`, `remove`, `pendingCommands`, `PendingSchoolCommand.matches` (`SchoolConfigurationAPI/SchoolCommandOutbox.swift`).

**Limites de couverture déclarées par l'index** (à ne pas lire comme une garantie) : 88 fichiers
`parse_partial` (dont plusieurs migrations SQL), 4 fichiers illisibles pour l'analyseur
(`openapi.yaml`, `022_lesson_availability.sql`, `026_observation_themes.sql`,
`20261023d_messaging_removed_members.sql`), répertoires exclus par conception (`apps/api/dist`,
`node_modules`, `apps/web/dist`, `.claude`). Les fichiers signalés en lecture partielle ont été lus
directement quand un contrôle en dépendait ; le graphe ne prouve à lui seul ni compilation ni
comportement.

## Swift : inventaire seulement, **AUCUNE compilation ni exécution**

Aucun Swift, Xcode ou `simctl` disponible sur ce poste ; aucune commande Apple n'a été tentée. Le
projet Xcode n'est pas versionné : `apps/ios/project.yml` (non modifié) prend les sources par
répertoire, donc les nouveaux fichiers entrent sans déclaration manuelle.

Classes et suites **nouvellement incluses** dans la sélection `unit_test_scope=all`
(`-only-testing:DrivyTests`, cf. `scripts/ios/test-selection.sh`) :

| Nouveau fichier / classe | Méthodes présentes (statique) |
|---|---|
| `MessagingMediaCryptographyTests` (nouveau fichier) | 15 méthodes XCTest |
| `MessagingMediaContentTests` (nouveau fichier) | 18 méthodes XCTest |
| `MessagingHTTPMediaTransportTests` (nouveau fichier) | 33 méthodes XCTest |
| `MessagingMediaURLSessionTransportTests` (nouveau fichier) | 12 méthodes XCTest |
| `SchoolNativeRegression131Tests` (nouveau fichier, swift-testing) | 2 `@Test` (`aRefusedPermitReviewKeepsTheRemainingBlockingCommand`, `aRefusedPermitReviewWhoseRemovalFailsKeepsTheLockAndTheCommand`) |
| `RelayReadinessDiagnosticTests` (nouvelle classe dans un fichier existant) | 8 méthodes XCTest |

Classes existantes **modifiées** (donc à rejouer aussi) : `MessagingCoreTests`, `MessagingHTTPTransportTests`
(+ `MessagingReportTransportTests`), `MessagingThreadTests`, `MatrixMessagingCryptographyTests`
(+ `MatrixMessagingReportSealingTests`), `MatrixMessagingRelayIntegrationTests`,
`SchoolCommandScopes106Tests`, `SchoolLiveObservationRecorderTests`, `SchoolTrainingRefreshTests`,
`SchoolWaitMonitorTests`.

Les **cinq cas R6** (rouges métier) restent, à ce candidat, des attentes de source non exécutées :

| Cas | Suite / méthode |
|---|---|
| A | `SchoolCommandScopes106Tests/anInvitationAndAProfileRecordDoNotShareAVersion` |
| B1 | `SchoolLessonHubTests/aRefusedPermitReviewKeepsTheLessonAndFallsBackToTheWrittenReason` |
| B2 | `SchoolLessonLifecycleTests/laterGPSDepartureAlsoWaitsForSavedObjectives` |
| C | `SchoolLiveObservationRecorderTests/lateConfirmationRefreshesTheNoGPSWorkspaceAfterItsSheetClosed` |
| D | `SchoolTrainingRefreshTests/receiptOfAnotherLessonNeverBroadcastsTheOpenLessonAsItsTarget` |

Relais : `MatrixMessagingRelayIntegrationTests/testRealRelayExchangeIdempotenceRecoveryAndContextRefusal`
(scénario contre le vrai relais, échouait en `READINESS`/diagnostic `NONE` au run 41861281984) et les
huit méthodes `RelayReadinessDiagnosticTests` qui classent l'erreur sans fuite. Le harnais **hôte**
`scripts/ios/relay-diagnostics.test.mjs` est vert (9/9) ; cela ne prouve ni la cause ni la réparation
du relais, encore inconnue.

Le run distant 41861281984 ne couvre que `883581ad321b67ae3b7efe15ef2c6b89970b1e20` (1415 tests,
1409 réussis, 6 échecs, dont les cinq cas métier et le relais) et reste **globalement rouge**. Aucun
push, rerun ou workflow n'a été déclenché pour exécuter ces fichiers au SHA intégré.

## Défauts constatés, séparés du périmètre d'intégration

1. **Quatre diagnostics de typage introduits par un harnais de développement.** `npx tsc -p infra/dev/tsconfig.json`
   donne **exit 2** avec 7 diagnostics : les 3 préexistants (fichiers identiques à la base :
   `check-v3-agenda-acceptance.ts`, `check-v3-entry.ts`, `measure-web-entry.ts`) **plus 4 nouveaux**
   dans `scripts/dev/check-pending-recovery-106.ts` (l. 66, 67, 74 : index `undefined`, `address`
   possiblement nul, `port` absent de `string | AddressInfo`). Ce fichier est livré tel quel par
   `tomyrms/issues-suivi-web-106` (blob identique à `b7584e0e`, absent de la base) : ce n'est pas un
   artefact de fusion. Il est hors des portées de typage vérifiées en CI (`npm run typecheck` =
   workspace API ; `npm run typecheck --prefix apps/web`), donc invisible pour la qualification.
   **Non corrigé** : cette tâche interdit toute modification produit ou test.
2. **Suite web dépendante d'un ensemble de dépendances non verrouillé au niveau racine.**
   Premier passage : `test/pending-recovery-106.test.tsx` échoue (2 tests, exit 1) car
   `infra/dev/browser.ts` importe `playwright-core`, absent après `npm ci` racine et `npm --prefix apps/web`.
   Cause exacte : `playwright-core` n'est verrouillé que dans `infra/dev/package-lock.json`
   (`1.63.0`), conformément à `docs/implementation/dev-identity.md` ; `qualification-checks.yml` ne
   l'installe que dans le job d'ouverture d'école, pas dans le job web. Après
   `npm ci --prefix infra/dev` (lockfile existant, exit 0), la suite complète passe. Ce n'est pas un
   défaut produit, mais un prérequis d'environnement à documenter pour reproduire la suite web hors CI.
3. **Deux rouges SMTP anciens** ne se reproduisent pas ici : Mailpit était configuré et `g1c` passe
   64/64. Aucun résultat ancien n'a été recopié.
4. **`--extended=formations` et `--extended=code` ont signalé d'eux-mêmes** qu'ils ne sont pas
   rejoués (« harnais à réaligner sur le portail reconstruit ») ; seules les suites demandées ont été
   jouées. Ce message vient du harnais, pas d'un échec masqué.

## Ressources créées et arrêtées

| Ressource | Nom | Fin de vie |
|---|---|---|
| PostgreSQL 17 | `drivy-i1-20261104-pg` (`127.0.0.1:55451`) | arrêté et supprimé |
| Mailpit (API/qualification) | `drivy-i1-20261104-mailpit` (`127.0.0.1:18025/18080`) | arrêté et supprimé |
| Mailpit (recette OIDC) | `drivy-i1-20261104-mailpit-e2e` (`127.0.0.1:1025/8025`) | arrêté et supprimé |
| Keycloak éphémère | `drivy-opening-e2e-<uuid>` | retiré par le harnais lui-même |

Contrôle final : aucune ressource `drivy-i1-20261104*` ni `drivy-opening-e2e*` restante, aucun
conteneur en cours sur le poste, 19 conteneurs étrangers toujours `Exited` comme à l'inventaire
initial. Aucune purge globale, aucun volume nommé créé, aucune base réelle touchée.

## Limites et restes

- **Tous les médias natifs restent non branchés au parcours complet** : le contenu v3, la primitive
  crypto, le transport binaire et le backend média sont intégrés et testés séparément, mais il
  manque le coordinateur média (coffre/cache), la préparation et l'UI natives, le `mediaRef` serveur
  et les consommateurs à provenance typée. Aucune issue n'est terminée par cette intégration.
- Aucune preuve Apple, simulateur, appareil physique, GPS/batterie/FaceID/VoiceOver, ni Safari/zoom
  natif n'est acquise ; le run existant reste rouge et n'a pas été relancé.
- Aucun push, PR, CI distante, merge vers `master`, déploiement, clôture d'issue, ni modification de
  `STATUS.md` ou du registre de coordination : ce suivi reste au coordinateur.
- Zéro retour correctif consommé pour cette tâche ; les plafonds des tâches sources ne sont pas remis à zéro.
- Les preuves brutes (journaux, JSON vitest, captures) sont sous `artifacts/`, répertoire ignoré par
  Git : aucun secret réel, aucune donnée de personne réelle, identifiants de fixtures synthétiques seulement.
