# Q131 — premières mesures web sous latence, 5 novembre 2026

## Correction 1 — confidentialité et verdict réellement observés

Cette section remplace la portée des contrôles de stockage et de confirmation de la livraison `1a6a27dab7a7b2e94f7927aea76e76a70a92a3cb`, conservée dans l'historique. Les observations et fichiers JSON anciens restent inchangés : leur test de sentinelle mal encodée ne prouvait pas l'absence de contenu persisté, et leur attente de 150 ms n'exigeait pas un verdict positif. Ne pas les utiliser comme preuves de ces deux propriétés.

**Correction.** `verifyMetadataOnly` parse le JSON stocké et exige exactement les six champs du contrat `updateMember` (`operationId`, `schoolId`, `kind`, `resourceId`, `resourceVersion`, `createdAt`), avec UUID, type et valeurs valides. La fixture appelle ce même vérificateur après chaque écriture réelle de la clé de suivi et compte les entrées non vides effectivement vérifiées ; une violation fait échouer la campagne sans journaliser le contenu. La saisie et les témoins partagent `accessReason`. Tests négatifs : contenu ajouté à un champ `reason`, corps imbriqué, contenu à la place d'un UUID, Unicode brut et Unicode échappé ; tous doivent être rejetés. Le cas de stockage refusé n'a aucune écriture réussie à qualifier.

`waitForAccessVerdict` attend au plus 22 s un verdict du vrai magasin après réponse. Nominal, stockage refusé et relecture échouée exigent `confirmed=true` et une file vide ; réponse perdue exige une entrée incertaine, refus exige une file vide plus l'erreur UI, compte changé exige le changement de scope et une file vide plus fermeture de la modale. Les trois derniers exigent `confirmed=false`. La reprise après réponse perdue exige aussi positivement le reçu confirmé. La pause de 150 ms est supprimée ; les horodatages page restent ceux des événements et frames observés. Un timeout provoque `completed=false` et une sortie en erreur.

**Préflight réutilisé et revérifié.** Même session `93de892f-dcb4-41f0-8916-80dbfa8b15e4` : reçu initial Orca relu, `launch.effective={agent:codex,model:gpt-6-astra,effort:high}` ; le dispatch de suivi ne répète pas ces options. Skills Superpowers debugging/TDD/verification relus aux chemins ci-dessous ; Impeccable et Uncodixfy déjà chargés, chemins et SHA256 revérifiés inchangés. Application : précision des preuves d'état, contrôles existants et design Drivy préservés, aucune refonte ni score du détecteur ENOENT. Codebase Memory `C-Users-jtoma-orca-workspaces-Drivy-issues-mesures-web-131`, racine absolue correcte, `ready`, watcher actif, index au 5 novembre 00:49:25 UTC / scan 00:59:54 UTC avant édition ; recherche ciblée `parseMetadata|toMetadata` dans `command-core.ts`, contrat et source relus.

**Reproduction.** Commandes Node/tsx identiques ci-dessous ; avant une reconstruction du client, fixer `$env:DRIVY_BUILD_SHA='e2edc85ed092237016620079d52d11eb7a2d02b5'`. Le script refuse des sources produit différentes ou un build d'entrée d'identité différente. Chaque exécution écrit un nouveau dossier horodaté sous `artifacts/web-reactivity-131/correction-1/` ; pas d'écrasement d'une campagne précédente. L'empreinte inclut maintenant les deux nouveaux helpers de vérification et d'attente.

**Campagne fraîche : PASS, exit 0, 42 échantillons dont 3 chauffes**, fichier `artifacts/web-reactivity-131/correction-1/run-2026-11-05T01-06-11.175Z/results.json` ; cinq captures nouvelles dans ce même dossier. Identité exacte du harnais : `8621dbb398dbb900806439b82380f2a3e89021f1f9584f4fa2f7516cda4d24a5` (sources mesurées copiées et empreinte recomposée). Chromium 153.0.8010.12, win32 10.0.26200 x64, Node v24.22.2, produit et build d'entrée `e2edc85ed092237016620079d52d11eb7a2d02b5` inchangés. Les résultats de la première exécution de correction restent dans leur dossier antérieur, comme les résultats initiaux.

| Surface | Latence ajoutée | n hors chauffe | Retour UI min / médiane / max (ms) |
|---|---:|---:|---|
| entry | 0 s | 3 | 3.5 / 3.8 / 12.6 |
| entry | 1 s | 3 | 6.4 / 12.7 / 24.4 |
| entry | 5 s | 1 | 7.6 / 7.6 / 7.6 |
| entry | 15 s | 1 | 17.1 / 17.1 / 17.1 |
| access | 0 s | 3 | 9.6 / 10.1 / 10.1 |
| access | 1 s | 3 | 11.0 / 11.6 / 17.6 |
| access | 5 s | 1 | 15.9 / 15.9 / 15.9 |
| access | 15 s | 1 | 8.8 / 8.8 / 8.8 |
| preferences | 0 s | 3 | 8.2 / 14.6 / 15.6 |
| preferences | 1 s | 3 | 7.6 / 12.8 / 14.2 |
| preferences | 5 s | 1 | 12.9 / 12.9 / 12.9 |
| preferences | 15 s | 1 | 12.8 / 12.8 / 12.8 |

Hors chauffe : **14 accès positivement confirmés**, **9 verdicts initiaux sans faux confirmé** (3 perdus, 3 refusés, 3 comptes changés), puis **3 reprises positivement confirmées**. Aucun champ hors métadonnées ni valeur invalide dans les écritures observées ; les 3 stockages refusés ont explicitement zéro écriture réussie vérifiée. Changement de thème indépendant pendant l'attente 15 s : **11.0 ms**, n=1. Les temps de confirmation, métadonnées et convergence sont agrégés séparément dans `metricSummaries`. Les contrôles sont faits sur l'état et les écritures réels, pas sur la seule absence d'une phrase.

**Revue visuelle fraîche.** Captures du dernier dossier inspectées : `access-wait-1440-light.png`, `access-storage-390-dark-keyboard.png`, `access-refused-390-dark-keyboard.png`. Attente modale, confirmation distincte de l'alerte de stockage, motif préservé au refus et focus visible ; aucun changement de présentation.

**Validation ciblée.** Commandes `node apps/web/node_modules/tsx/dist/cli.mjs scripts/dev/reactivity-131/guards.test.ts` et `stats.test.ts`, puis tsc ciblé avec les options strictes listées dans la livraison initiale et `guards.test.ts` ajouté ; sorties `guards-green.log`, `stats-green.log`, `types-final.log`, exit 0. `verify-final.py` valide les 42 échantillons et l'empreinte exacte, exit 0. RED reproduits : `correction-1/guards-red.log` (absence d'exception malgré fuite) puis `verdict-red.log` (réponse sans confirmation acceptée). GREEN des mêmes tests, statistiques et typage strict ciblé ; contrôle navigateur d'un verdict volontairement absent : timeout attendu, jamais zéro/PASS. La suite web complète inchangée et le typage global hors lot ne sont pas réexécutés, conformément au mandat. Aucune source produit ni ancien test #106 modifié ; aucun outil installé, push, CI ou déploiement. Fichiers : script, fixture, nouveaux `guards.ts`, `guards.test.ts`, `observe.ts`, présent rapport.

**Limites.** Aucun test concurrent lancé par ce worker pendant la mesure ; les autres charges de la machine ne sont pas contrôlées. Le coût du vérificateur et des observateurs est inclus dans les temps ; ces chiffres ne constituent pas un gain comparatif sur la campagne initiale. Windows/Chromium et production synthétique uniquement, n=3 aux cas courts et n=1 à 5/15 s, chauffes séparées ; aucune garantie sur appareil physique, aucune mesure de corps durable. L'oracle de stockage est volontairement limité aux métadonnées de `updateMember`, pas à toutes les clés ni aux familles de commandes de l'application.

## Livraison initiale — observations historiques conservées

Campagne locale ciblée de #131/#105/#106, sans changement produit. Sources produit `e2edc85ed092237016620079d52d11eb7a2d02b5`. Le commit contenant ce rapport identifie le harnais ; son SHA-256 exact et les dates figurent dans `artifacts/web-reactivity-131/results.json`. Les artefacts sont ignorés et restent dans ce worktree.

## Préflight et périmètre

Codex **gpt-6-astra / high** : preuve du coordinateur, message Orca `msg_f13dfba09627`, `worker-show --dispatch ctx_a2255ef4868e --json --full`, `result.worker.startOptions.launch.effective`, associé à `structured:93de892f-dcb4-41f0-8916-80dbfa8b15e4`. Aucun autre worker ni changement de modèle.

Lus : AGENTS, COMMENCER_ICI, DESIGN.md (web Bureau #311), R11/R12, reprise AP72 et T020 ; snapshot `C:/Users/jtoma/orca/workspaces/Drivy/bristleworm/docs/implementation/orchestration-issues-snapshot-20261104.json`, entrée `issues[id=131]` ; les deux rapports et harnais #120/#106 désignés dans le mandat. T020 n'est pas qualifié en base PostgreSQL par cette campagne web.

Skills réellement lus sous `C:/Users/jtoma/.codex/skills/` : `systematic-debugging/SKILL.md`, `test-driven-development/SKILL.md` et `writing-good-tests.md`, `verification-before-completion/SKILL.md`. Le test des statistiques a échoué sur l'implémentation vide (assertion attendue), puis passé ; les contrôles navigateur prouvent aussi qu'un déclencheur absent et un résultat DOM absent échouent sans inventer une durée. Les erreurs de harnais `__name` (sérialisation tsx) et ciblage de l'input caché Base UI ont été reproduites et corrigées uniquement dans le harnais.

UI : `impeccable/SKILL.md` + `reference/audit.md`, provenance `pbakaus/impeccable@2c95b1968ca74c5d2c4c0503dcee72f6d0d555ea`, SHA256 `fab04b31f946573b00a8559db1fc070f8ea5825254d491c2b13156e5661a86d7` ; `uncodixfy/SKILL.md`, provenance `cyxzdev/Uncodixfy@e0e028058b5259debdd94b78147c6d6c77bf7da2`, SHA256 `efb88d150e40d34c5b997a25eb4b88655e8daa1628848568a7f50668f1bf1d10`. Launcher Impeccable `context --target apps/web/client/portal/access-preview.tsx` exécuté : pas de PRODUCT/hook, DESIGN existant lu, aucun init ni refonte. Application : état honnête, clavier/focus, erreurs lisibles, conservation du système Drivy. Palettes génériques, interdiction du bleu, remplacement des polices et décor non applicables à ce mandat de mesure. `ui-skills-root` lu, aucune installation de CLI supplémentaire.

Codebase Memory indexé avant code au chemin absolu de ce worktree : projet `C-Users-jtoma-orca-workspaces-Drivy-issues-mesures-web-131`, 53 046 nœuds / 202 319 liens. Recherche `PortalPendingRequests|buildWebApp|commandStore`, puis `trace_path PortalPendingRequests outbound depth=2` : contexte, magasin, reprise, Alert/Button/Dialog. Le graphe comporte des exclusions et des parsings partiels (notamment SQL/OpenAPI) ; les sources TS/TSX réelles ont été lues. Aucun ADR hors périmètre écrit.

## Reproduction et instrumentation

Depuis la racine, PowerShell :

```powershell
$env:PATH='C:/Users/jtoma/AppData/Local/Temp/drivy-orchestration-20261104/node-v24.22.2-win-x64;'+$env:PATH
npm ci --prefix apps/web --ignore-scripts --no-audit --no-fund
npm ci --prefix infra/dev --ignore-scripts --no-audit --no-fund
npm run build --prefix apps/web
node apps/web/node_modules/tsx/dist/cli.mjs scripts/dev/reactivity-131/stats.test.ts
node apps/web/node_modules/tsx/dist/cli.mjs scripts/dev/measure-web-reactivity-131.ts
```

Chromium déjà installé via `infra/dev/browser.ts` ; aucun téléchargement de navigateur. Deux serveurs loopback avec port libre, arrêtés dans `finally`. Entrée : vrai build Vite production servi par `buildWebApp`, réponses session/me synthétiques. Gestion : fixture isolée Vite **build production** (React, Tailwind, mêmes dépendances verrouillées, alias et SHA), composants/handlers/CSS du produit ; `installPreviewTransport` réel enveloppé pour les fautes et délais. Ce n'est ni Vite dev ni le portail complet en conditions serveur réelles.

L'entrée reçoit un délai sur session puis sur me (donc jusqu'à 30 s cumulées). Le code est tapé pendant session inconnue ; focus/sélection sont comparés avant et après les deux réponses. La convergence est la première frame observant `main[aria-busy=false]` après libération de session. C'est une convergence de lecture, pas une confirmation de mutation.

Gestion : gestes Playwright réels, origine `performance.now()` au click capturé ; première frame montrant `Confirmation…` ou le switch changé. Les réponses ajoutent 0/1/5/15 s aux 650 ms (accès) ou 500 ms (notifications) déjà présents dans la démo. Aucune horloge modifiée. Les métadonnées sont chronométrées après le vrai `sessionStorage.setItem` réussi ; le corps reste en mémoire, sa conservation durable est **NON_MESURÉE / non prévue**, même si les métadonnées sont écrites. Confirmation accès = événement du vrai magasin après réponse ; confirmation notifications = DOM observé après attente Playwright, borne supérieure incluant son surcoût. Reprise après réponse perdue = click « Vérifier le résultat » vers première frame de confirmation du panneau.

Chaque surface comporte une chauffe séparée (`repeat=-1`, exclue des agrégats), trois mesures à 0/1 s, une à 5/15 s. Chaque faute accès a trois répétitions à 1 s. Les temps de démarrage/préparation sont séparés des gestes ; leur origine est côté Node. Pas de p95. Cible 100 ms proposée seulement, sans garantie matérielle. La campagne finale est exécutée sans tests concurrents ; les résultats exploratoires sont conservés séparément.

## Résultats de la campagne

**PASS campagne : 42 échantillons bruts, dont 3 chauffes ; 39 mesures retenues.** Windows 10.0.26200 x64, Node 24.22.2, Chromium 153.0.8010.12. JSON final `completed=true`, processus exit 0.

Premier retour UI, millisecondes :

| Surface | Délai ajouté | n | min | médiane | max |
|---|---:|---:|---:|---:|---:|
| entry | 0 s | 3 | 3.6 | 4.1 | 7.5 |
| entry | 1 s | 3 | 7.3 | 13.1 | 13.6 |
| entry | 5 s | 1 | 6.0 | 6.0 | 6.0 |
| entry | 15 s | 1 | 2.8 | 2.8 | 2.8 |
| access | 0 s | 3 | 9.8 | 10.5 | 15.9 |
| access | 1 s | 3 | 9.6 | 12.6 | 14.3 |
| access | 5 s | 1 | 12.1 | 12.1 | 12.1 |
| access | 15 s | 1 | 10.7 | 10.7 | 10.7 |
| preferences | 0 s | 3 | 13.5 | 14.0 | 14.5 |
| preferences | 1 s | 3 | 12.8 | 12.9 | 13.1 |
| preferences | 5 s | 1 | 13.5 | 13.5 | 13.5 |
| preferences | 15 s | 1 | 12.7 | 12.7 | 12.7 |

À 15 s : accès confirmé à **15 660,7 ms** (métadonnées seules à **0,7 ms**) ; notifications confirmées observées à **15 736,7 ms**. Pendant cette attente, vrai changement de thème indépendant : **12,8 ms**, n=1. Entrée : convergence après session puis me à **30 032,9 ms**, focus/texte/sélection conservés. Reprise après réponse perdue : n=3, **24,0 / 29,9 / 29,9 ms** (min/médiane/max), reçu synthétique disponible immédiatement. Les distributions de chaque métrique, y compris fautes, sont dans `metricSummaries`.

Les 24 gestes nominaux mesurés restent sous 100 ms dans cette exécution. Les fautes ont également un retour initial rapide (9,7–17,8 ms) ; cela ne transforme aucun résultat incertain en succès. Les trois essais de chacune des cinq fautes passent leurs assertions.

Identité mesurée : `25bb38a00b02637b169ff06422fa4cebebdb0f940ff510ada303d1bdfffd2684`. Les sources exactes sont copiées dans les artefacts `measured-harness.ts`, `measured-fixture-source.ts`, `measured-stats.ts` ; empreinte recomposée et vérifiée. Après campagne, seul le blanc final du script a été supprimé pour diffcheck (aucun changement exécutable), puis typage/tests revérifiés.

## États et revue visuelle

Les cinq PNG du résultat sont de vraies captures Chromium, datées et associées au SHA dans le JSON : entrée en attente 390 clair (sélection et focus visibles), accès en attente 1440 clair (bouton « Confirmation… » dans la modale), préférences en attente 1440 sombre (thème changé pendant l'enregistrement), refus 390 sombre (motif conservé et focus sur fermeture), stockage refusé 390 sombre (notice de suivi local distincte de la confirmation serveur). Pas de débordement horizontal relevé par les captures ; aucun changement CSS. La modale d'accès bloque les actions extérieures pendant son attente : l'action indépendante est mesurée sur les préférences, pas avec un bouton témoin inventé.

Refus : aucune confirmation ; réponse perdue : état incertain, puis reçu retrouvé par le vrai panneau ; compte changé : ancienne réponse ignorée par le magasin. Le changement de compte est injecté via le vrai `scopeToPerson`, pas un parcours de connexion UI complet. Succès puis relecture échouée : confirmation de l'écriture et « Actualisation impossible » coexistent, ce qui distingue les deux faits. Stockage refusé : alerte persistante même après confirmation serveur, sans promesse de corps durable. Aucune correction produit réalisée.

## Vérifications et limites

- Build production web : exit 0 ; avertissement préexistant sur `theme-init.js` non module. Build production de fixture et campagne : exit 0.
- Statistiques : RED observé sur assertion, puis GREEN ; dernier lancement exit 0. Contrôles navigateur : sélecteur absent et retour absent provoquent une erreur. `verify-results.py` : exit 0, 42 mesures, 5 captures, empreinte exacte, aucune confirmation avant réponse et aucune durée de stockage inventée.
- Typage ciblé : exit 0, `scoped-types-final.log`, TypeScript 5.9.2 avec `--noEmit --target ES2023 --module NodeNext --moduleResolution NodeNext --strict --noUncheckedIndexedAccess --exactOptionalPropertyTypes --noUnusedLocals --noUnusedParameters --esModuleInterop --skipLibCheck --types node --typeRoots ./apps/web/node_modules/@types`, sur le script et `stats.test.ts` (helpers importés inclus). La fixture TSX générée est compilée par Vite ; son texte embarqué n'est pas vérifié sémantiquement par ce tsc.
- Typage global infra/dev : **exit 2**, 945 lignes de diagnostics, `types-final.log`. Comparaison avec le même projet excluant seulement les nouveaux fichiers : **diagnostics identiques**, `types-baseline.log` / `tsconfig-baseline.json`. Les trois erreurs historiques restent : `check-v3-agenda-acceptance.ts` TS6133 ; `check-v3-entry.ts` et `measure-web-entry.ts` TS2741 (password absent). Cette installation web/infra seule ne reproduit pas un environnement API entièrement installé : autres erreurs de résolution API (`pg`, `zod`, `fastify`, etc.) et leurs cascades. Aucune dépendance API installée hors autorisation, aucun diagnostic masqué, aucun nouveau diagnostic du lot.
- Suite web complète finale : **80 fichiers passent, 842 tests passent, 1 expected fail**, exit 0, `web-tests-final.log` (01:45:45 locale, 18,72 s). Premier essai : **1 échec / 841 passent / 1 expected fail**, `pending-recovery-106.test.tsx > pending recovery: metadata` (assertion « pending already explained by entry is not duplicated », 0 au lieu de 1), en parallèle d'une campagne exploratoire ; avertissement de scan Vite sur l'import zod de notre fixture. L'import du harnais a été rendu explicite, puis la campagne finale et la suite ont été exécutées séparément ; aucun test ni produit #106 modifié. La cause de l'assertion transitoire n'est pas démontrée.
- Détecteur Impeccable lancé : échec ENOENT malgré fichier présent ; son `[]` n'est **pas** une preuve de conformité. Revue visuelle manuelle des captures et du source effectuée ; aucun score d'accessibilité global inventé.
- `git diff --check` et `git diff --cached --check` exécutés avant commit. Produit et locks inchangés.

Fichiers versionnés : `scripts/dev/measure-web-reactivity-131.ts`, helpers neufs `scripts/dev/reactivity-131/{fixture.ts,stats.ts,stats.test.ts}`, ce rapport. Aucun STATUS, registre, conception, produit, lock, workflow ou fichier d'autre lot modifié. Aucun push, PR, CI distante, site activé, déploiement ou service réel.

Restent NON_MESURÉS : appareil physique, Safari/iPad, VoiceOver, zoom natif, grande taille de texte, données/transactions réelles, GPS/batterie ; ensemble des scénarios #131 hors ces gestes (multi-onglets, multi-appareils, 429, réseau coupé avant envoi, etc.). Les préférences ont leur propre magasin mémoire ; le suivi `PortalPendingRequests` est qualifié ici sur les accès. Cette livraison ne clôt pas la matrice.
