# Audit intelligent Drivy du 18 octobre 2026

## Synthèse

**13 signaux examinés, 2 défauts confirmés et corrigés : P0 = 0, P1 = 1, P2 = 1, P3 = 0.** Les 11 autres signaux sont écartés, différés ou soumis à clarification, pas présentés comme des bugs. Ce résultat n’est pas une certification de l’ensemble du produit.

Base auditée : `5482dd840264ac894ced123d3b90dd6e558a65eb`, checkout principal `codex/portail-studio-20261014`. Travail isolé dans `C:/Users/jtoma/dv-audit-20261018`, branche **`audit/intelligent-20261018`**. Les changements préexistants du checkout principal et les autres branches ne sont pas intégrés.

## Orchestration et méthode

Dix audits spécialisés terminés en parallèle : **7 GPT-5.6 Luna** (fonctionnel, navigation, UI, UX, états, accessibilité, produit) et **3 GPT-5.6 Sol** (performances, architecture, API). Une contre-revue ciblée supplémentaire a utilisé **GPT-5.6 Astra**. Les premières tentatives Haiku ont été arrêtées ou ont échoué côté fournisseur, sans résultat comptabilisé. Aucun coût monétaire exact n’est revendiqué.

Périmètres séparés, recherches ciblées, budgets de lecture réduits, rapports individuels de 400 mots maximum. Les agents ont seulement écrit leurs rapports, pas le code produit. Le coordinateur a arbitré les preuves, reproduit les défauts, implémenté et intégré. Rapports locaux : `artifacts/audit-20261018/agents/01.md` à `10.md`. Ils contiennent les propositions initiales, parfois réfutées ci-dessous.

Stack et conventions respectées : API TypeScript/Fastify/PostgreSQL, portail React/Vite/BFF, iOS Swift. Lecture d’AGENTS.md, du guide canonique et de DESIGN.md. Réutilisation de `Notice`, des formulaires, tokens, confirmations et gardes existants. Aucune nouvelle dépendance, modification CSS, refonte, migration ou rupture d’API.

## Corrections retenues

### P1 : brouillon d’accès équipe effacé par une relecture concurrente

- **Emplacement :** `apps/web/client/console/people.tsx`, effet de synchronisation initialement lignes 67–73, désormais lignes 70–102, garde d’écriture et notice de conflit.
- **Preuve :** dans Edge avec vrais composants React et store de commandes, modifier rôle, permission et motif. Simuler une première émission 503, une vérification AP72 sans trace, une modification concurrente puis un renvoi 412. La relecture d’une nouvelle version effaçait le brouillon. Le test initial a échoué sur la conservation du rôle.
- **Impact :** perte silencieuse d’une préparation administrative. Aucun écrasement réel de données serveur n’a été démontré.
- **Correction :** mémoriser la base du brouillon, distinguer notre confirmation d’une version concurrente, conserver la saisie, expliquer le conflit et interdire écriture/retrait avant résolution explicite. « Annuler les modifications » reprend l’état serveur actuel. Pas de rebase automatique des permissions.
- **Risque/effort :** risque modéré lié au cycle asynchrone, effort moyen. Bénéfice direct, sans nouvelle complexité de navigation. **Confiance élevée**, vérifiée dans le harnais, pas sur un backend déployé.
- **Contre-revue :** Astra a trouvé une régression intermédiaire, abandon puis réouverture du même membre ressuscitant le conflit. Reproduite en rouge puis corrigée par la désélection explicite, sans assimiler une absence temporaire de données à un abandon. Elle n’était pas un troisième bug de la base auditée.

### P2 : sujet OIDC non textuel accepté

- **Emplacement :** `apps/api/src/auth.ts:32`, tests `apps/api/test/auth.test.ts:25–38`.
- **Preuve :** JWT réellement signés localement. Avant correction, cinq valeurs non textuelles passaient le vérificateur malgré le contrat `Identity.subject: string`. Sept cas invalides sont maintenant rejetés en `401 INVALID_SESSION`.
- **Impact :** identité mal typée transmise aux couches suivantes. Aucun accès à un autre compte, contournement de signature ou exploit d’autorisation démontré, donc pas de classement P0.
- **Correction :** exiger une chaîne non vide. Ne pas appliquer le trim/plafond arbitraire suggéré initialement. Un test protège la restitution exacte d’un sujet opaque avec espaces et Unicode. Les pannes du fournisseur restent des 503.
- **Risque/effort :** faibles, invariant rétabli à la frontière existante. **Confiance élevée**, tests cryptographiques exécutés.

## Arbitrage des autres signaux

Les priorités ci-dessous sont celles des suites éventuelles, pas des bugs confirmés supplémentaires.

| Signal et emplacement | Décision du coordinateur |
| --- | --- |
| Départ avant l’heure prévue le même jour, `apps/api/src/lessons.ts:371–375` | Règle métier ambiguë, non confirmé. Décision humaine seulement si un seuil horaire strict est souhaité. Ajouter une interdiction sans règle pourrait casser un usage légitime. |
| Double sélection Invitations, `navigation.ts:47`, `Console.tsx:294–315` | Faux positif retiré : les sous-liens ne sont rendus que dans le workspace courant. |
| Deep-links métier iOS, `DrivyApp.swift:97–105` | Pas de contrat ni d’émetteur concret établi. Fonctionnalité nouvelle, exclue. |
| Code d’invitation perdu, `people.tsx`, état `issuedCode` et régénération | Le changement de détail n’établit pas la perte alléguée. La disparition au démontage est liée au stockage mémoire. Pas de récupération persistante de secret ajoutée. Le remplacement est déjà explicite. Une précision de copie serait P3, non retenue. |
| Relecture des annuaires après 60 s, `agenda.tsx:36–56` | Comportement réel, mais fraîcheur utile après modifications externes. Pas de retrait ni TTL sans mesure et contrat de fraîcheur. Profilage éventuel P2. |
| Recalcul agenda toutes les 30 s, `agenda.tsx:26–27,59–63,94–98` | Regroupement déjà mémoïsé. Les recherches linéaires existent, mais aucune lenteur mesurée. Optimisation différée, pas de gain inventé. |
| Scripts racine uniquement API, `package.json:6–11` | Organisation explicite et CI web séparée dans `refonte-checks.yml:49–52`. Validation locale des deux exécutée. Pas de refonte workspace/lockfile. |
| Typecheck infra non câblé, `infra/dev/tsconfig.json`, workflows CI | Opportunité P2 de maintenance, sans régression actuelle établie. Non retenue dans ce lot centré sur les défauts utilisateur démontrés. |
| Quatre constructions `WebConfig`, scripts `run-web`, `check-web`, `check-entry`, `check-school-opening` | P3 de maintenance, aucune divergence prouvée. Abstraction commune non ajoutée. |
| Révision de bilan prétendument ancienne, `SchoolLessonReportClient.swift:58–61` | Faux positif : tri décroissant par séquence effectué avant consommation. |
| Clôture avant bilan textuel, parcours de leçon et STATUS | Flux séparé existant, pas un défaut démontré. Rendre le bilan obligatoire est une décision produit, non imposée. |

Agents UI, états et accessibilité : aucun défaut supplémentaire suffisamment démontré. Ce constat ne remplace pas une recette physique Apple ou un audit d’accessibilité complet.

## Vérifications exécutées

| Vérification | Résultat et portée |
| --- | --- |
| API `npm run typecheck`, `npm run test:unit`, `npm run build` | **Réussite, 135 tests dans 8 fichiers**. Baseline : 127. Journaux `api-final.log`. |
| Web `npm run typecheck`, `npm test`, `npm run build` dans `apps/web` | **Réussite, 233 tests dans 21 fichiers**. Journal `web-final.log`. |
| Nouveau `scripts/dev/check-audit-regressions.mjs` | **5 scénarios réussis** : conflit 1440/390 px, abandon puis même membre, renvoi réussi, succès direct puis autre membre. Rôle, autorisation et motif conservés, retrait bloqué, pas d’émission implicite, reset clavier et émission avec nouvelle version vérifiés. |
| Recette web existante, `--checks-only` | **41 interactions réussies, zéro échec**, rejouées sur `35a7aa5`. Résultat : `final-interactions/interaction-results.json`. |
| Captures ciblées | **30 captures**, cinq surfaces équipe/détail/invitations/agenda/élèves, clair/sombre, 1440/1024/390 px, et **1 contrôle de reflow**, aucun échec. Captures du conflit final mobile/desktop inspectées : texte lisible, aucune largeur débordante, composants existants conservés. |
| Intégrité canonique `npm run check:docs` | **556 fichiers inchangés**, contrôle d’intégrité uniquement, pas validation métier. |
| Format du patch | `git diff --check` réussi. Aucun script lint dédié déclaré, donc aucun résultat ESLint inventé. |
| Suite API complète `npm test` | **Tentée et bloquée**, pas verte : 27 fichiers en échec, 10 réussis, 2 tests échoués, 135 réussis, 147 ignorés lors de la baseline. Les échecs demandent la base PostgreSQL isolée absente. Journal `api-full-blocked.log`. |

Les régressions navigateur utilisent Edge et un **BFF synthétique en mémoire**, réseau limité au loopback. Elles vérifient les composants et commandes réels, pas l’intégration déployée OIDC/API/PostgreSQL. La confirmation par reçu AP72 seul n’est pas directement ajoutée au nouveau test, contrairement au renvoi confirmé.

La première campagne générale de captures a atteint le timeout de 300 s : **aucun succès global revendiqué** pour cette tentative. Les reprises bornées ci-dessus fournissent les résultats retenus. Des défauts de fixture/sélecteur ont été corrigés dans le nouveau harnais, sans être comptés comme bugs produit.

Preuves rouges/vertes : `red/results.json`, `review-red/results.json`, `final-regressions/results.json`. Revue indépendante : `review.md`, `review-final.md`. Tous ces chemins sont relatifs à `artifacts/audit-20261018/`.

Reproduction sous Windows, depuis la racine du worktree, avec les dépendances existantes installées et Edge disponible : démarrer `npm --prefix apps/web run dev -- --port 5187` dans un terminal, puis exécuter dans un autre :

```cmd
set "DRIVY_REVIEW_ORIGIN=http://127.0.0.1:5187"
node scripts/dev/check-audit-regressions.mjs
node scripts/dev/check-web-redesign.mjs --checks-only
```

## Complément de qualification réelle, 18 octobre à 18:03 +02:00

Le contrôle de clôture a demandé une preuve plus directe que le seul harnais synthétique. La recette existante de la CI, `scripts/dev/check-school-opening.ts`, a donc été réellement lancée sur la base locale réservée `drivy_onboarding_e2e`, avec `ONBOARDING_E2E_DATABASE_URL` explicitement limité à `127.0.0.1:5432`. Aucun service n’écoutait sur les ports requis 5432, 8081, 8025 et 1025. `docker info` a également échoué : pipe `dockerDesktopLinuxEngine` absent.

**Observation réelle : exit 1 à la première étape « base vierge et migrations non privilégiées », zéro contrôle accepté.** Résultat horodaté `2026-10-18T16:03:15.473Z` dans `artifacts/onboarding-web-synthetic/result.json`, journal dans `artifacts/audit-20261018/acceptance-real.log`. Malgré son nom historique « synthetic », cette recette utilise normalement les vrais services OIDC, BFF, API et PostgreSQL avec des données de test. Ici, elle s’arrête avant migration, création de compte, démarrage des services ou navigateur. Aucun mot de passe réinitialisé ni donnée existante modifiée.

La boucle d’acceptation de bout en bout reste donc **bloquée par l’environnement**, et n’est pas remplacée par les 46 parcours synthétiques. Aucun succès d’intégration ni bénéfice mesuré auprès d’une école réelle n’est revendiqué.

| Exigence ciblée | Observation avant | Observation après | Ce qui reste non établi |
| --- | --- | --- | --- |
| Ne pas perdre un brouillon d’accès lors d’un conflit | Échec Edge sur la conservation du rôle après renvoi refusé (`red/results.json`) | Rôle, autorisation retirée et motif conservés. Écritures bloquées jusqu’au reset explicite, nouvelle émission avec version actuelle, cinq scénarios verts | Même parcours avec comptes, concurrence et PostgreSQL réels |
| Refuser un sujet OIDC mal typé | Cinq JWT signés non textuels acceptés par le vérificateur | Sept valeurs invalides rejetées, chaîne opaque conservée, suite API 135/135 | Parcours fournisseur réel puis HTTP/BFF et base de données |
| Préserver les usages existants | Baseline web 233 tests | 233 tests et 41 interactions existantes toujours verts | Qualification Node 24, Apple et recette complète avec une école |

La preuve démontre une amélioration sur ces cas contrôlés, pas une acceptation utilisateur générale. Prochaine étape technique : rejouer sur le runner isolé Node 24 avec PostgreSQL et services locaux disponibles. Aucun contournement des gardes de production ni faux backend ajouté pour faire passer cette recette.

## Limites et suites humaines

- Node local **26.8.1**, alors que le dépôt exige **24.x**. Rejouer en CI supportée avant intégration.
- Docker installé mais daemon indisponible, PostgreSQL de test absent. Rejouer les tests d’intégration sur une base isolée, jamais production.
- Pas de Swift/Xcode, Safari, VoiceOver ou appareils Apple. iOS analysé statiquement seulement. Aucun résultat Instruments ni certification WCAG revendiqué, aucun nouvel audit axe exécuté.
- Avertissements de build préexistants conservés : script externe `theme-init.js` non bundlé et chunk JS supérieur à 500 ko. Aucune dégradation de performance mesurée ou correction cosmétique opportuniste.
- Valider les corrections avant fusion. Clarifier éventuellement la règle de départ anticipé et l’obligation de bilan, sans les bloquer arbitrairement.

## Fichiers et Git

Fichiers produit/tests modifiés :

1. `apps/api/src/auth.ts`
2. `apps/api/test/auth.test.ts`
3. `apps/web/client/console/people.tsx`
4. `scripts/dev/check-audit-regressions.mjs` (nouveau)

Documentation : ce rapport, `audit-intelligent-20261018-plan.md`, `docs/implementation/STATUS.md`. Les captures, rapports individuels, résultats JSON et journaux restent **locaux et ignorés par Git** sous `artifacts/audit-20261018/`. Les dépendances installées existantes ont été réutilisées par jonctions ignorées, sans modifier les manifests ni lockfiles.

Commits réalisés :

- `f37f44a` : `fix(api): reject non-string OIDC subjects`
- `0dcdac0` : `test(api): preserve opaque OIDC subject identifiers`
- `35a7aa5` : `fix(web): preserve access drafts across concurrent refreshes`
- `1284ddd` : `docs(audit): record findings decisions and validation limits`.
- Le complément de qualification réelle est committé sous `docs(audit): record blocked end-to-end acceptance`, identifiable par `git log -1 -- docs/implementation/audit-intelligent-20261018.md`.

L’état Git final est conservé dans `artifacts/audit-20261018/git-final.txt` : branche, statut court, commits et fichiers du delta. Les artefacts ignorés ne sont pas supprimés.

Branche dédiée uniquement. **Aucune fusion sur main/master, aucun push, déploiement ou changement de données de production.** Le checkout principal est préservé. La validation finale de l’utilisateur reste requise avant intégration.
