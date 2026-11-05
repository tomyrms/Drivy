# Qualification Apple `62875344` — réparation de compilation du test cache (#97)

Suivi mécanique du diagnostic de compilation du candidat assemblé `62875344`, autorisé par le porteur pour la fusion et le déploiement. Aucun critère fonctionnel ni revue des lots précédents n'est rouvert : ni le confinement, ni le cache, ni le quota, ni les assertions ne changent.

## Diagnostic

- Journal primaire relu par le coordinateur : job `127014762437`, `TEST BUILD FAILED`, code de sortie `65`, Xcode 26.6 / Swift 6.3.3 ; Linux vert.
- Défaut reproduit en source : `apps/ios/DrivyTests/MessagingMediaCacheTests.swift:349` appelait `fixture.indexURL()` — déclaré `throws` ligne 1304 — **sans `try`**, dans l'expression de `XCTAssertFalse`, qui n'est pas une fonction `throws`.
- Effet : erreur de compilation « call can throw but is not marked with 'try' » ; aucun test de ce fichier ne pouvait être construit.

## Correction

Un seul token Swift ajouté, ligne 349 :

```swift
XCTAssertFalse(FileManager.default.fileExists(atPath: try fixture.indexURL().path))
```

- L'assertion est conservée à l'identique (même expression, même message absent).
- La propagation d'erreur du test est conservée : l'autoclosure de `XCTAssertFalse` accepte une expression `throws`, donc une erreur d'accès au répertoire fait échouer le test comme avant.
- Aucun autre appel, aucune fixture, aucune source produit, aucune borne, aucun quota, aucune purge modifiés. Les deux autres appels de `indexURL()` (lignes 258 et 329) portaient déjà `try`.
- Aucun test supplémentaire n'a été ajouté : il recopierait la ligne corrigée sans valeur, et Apple sera relancé par le coordinateur sur le candidat assemblé.

## Vérifications réellement exécutées (Windows, sans Swift)

| # | Commande | Résultat | Code |
|---|---|---|---|
| 1 | `git rev-parse HEAD` | `49ff350f22f016209e455b16b8f85caa6ce39674` (base propre annoncée) | 0 |
| 2 | `index_status` (MCP `drivy-media-cache-97-20261104`) | racine exacte `C:/Users/jtoma/orca/workspaces/Drivy/issues-medias-cache-97`, `ready`, 39 684 nœuds ; aucune réindexation générale | 0 |
| 3 | `Select-String 'indexURL\(\)'` | 4 occurrences : déclaration ligne 1304, appels 258 et 329 avec `try`, appel 349 corrigé | 0 |
| 4 | `git diff -U0` | 1 insertion, 1 suppression, une seule ligne | 0 |
| 5 | `git diff --check` | aucune erreur d'espacement | 0 |
| 6 | `git status --porcelain` | ce fichier de test et ce rapport uniquement | 0 |

## Limites

- **Aucun compilateur Swift ici.** Le RED réel est le compilateur Apple cité (Xcode 26.6 / Swift 6.3.3), pas une simulation de syntaxe. Aucun GREEN n'est revendiqué sous Windows : **correctif préparé, Apple à réexécuter** sur le candidat assemblé.
- Le second défaut de compilation du même job ne concerne pas ce fichier ; il n'est ni reproduit, ni modifié, ni interprété ici.
- Modèle : `opencode-go/deepseek-v4.1-flash`, sans override. Skills chargés dans cette session : `systematic-debugging` (lecture de la déclaration et de l'appel avant modification), `test-driven-development` (sans objet au-delà du correctif mécanique), `verification-before-completion` (chargé avant livraison). Aucun sous-agent.
- Aucun push, aucune CI, aucun merge, aucune dépendance, aucun `STATUS.md`, aucun autre fichier.

## Q4 — trois défauts de fixtures du cache (#97)

Suite de la réparation de compilation Q2. Première exécution native au candidat `62560a2e`, run `41962003316` / job `127030313656` : build vert, tests réellement rouges. Diagnostics primaires : `C:/Users/jtoma/orca/workspaces/Drivy/bristleworm/artifacts/q4-diagnostics-metier.json`. Ce suivi corrige des **fixtures et attentes de qualification**, pas la logique produit ; les plafonds fonctionnels ne sont pas rouverts.

| # | Diagnostic primaire | Cause en source | Correction |
|---|---|---|---|
| 1 | `MessagingMediaCacheTests.swift:959` — `NSCocoaErrorDomain Code=4` sur `…/cache` (`NSPOSIXErrorDomain Code=2`) | `uniqueTemporaryDirectory` ne crée rien : `Data.write` visait un fichier dont le répertoire parent n'existait pas, donc le test échouait avant d'atteindre le cache | l'ancre temporaire est créée (`createDirectory`) avant d'écrire le composant possédé `cache` comme **fichier** ; l'assertion de refus d'init et la sentinelle (contenu `[7, 8, 9]`) sont conservées ; `cache` n'est jamais créé comme répertoire |
| 2 | `:55` `XCTAssertEqual ("5") is not equal to ("64")` et `:56` `XCTAssertTrue failed` | la boucle exigeait 64 hexadécimaux pour **tous** les fichiers, y compris `index.sealed`, dont le nom est contractuel (`indexURL` ajoute `index.sealed`) | l'index est vérifié **à son chemin exact** et son nom contractuel asserté ; seuls les fichiers de charge doivent être opaques (64 hexadécimaux) ; l'extension scellée reste exigée pour tous ; les recherches de sentinelles en clair restent exécutées sur **tous** les fichiers, index compris ; deux fichiers de charge attendus (original + miniature) |
| 3 | `:386` — `caught error "protectionUnavailable"` sur `store` du scope courant | `KeyFixture(refusesCreation: true)` créait une clé 256 bits **neuve**, différente de celle qui avait scellé l'index : le refus venait d'une clé étrangère, pas du refus de création | `KeyFixture` accepte un matériau de clé explicite (`key:`) et expose une vue **lecture seule** `material` ; le vérificateur rejoue **la même clé** que l'instance existante, avec comptage de requêtes propre à chaque phase. Le scope courant écrit et relit valablement, zéro demande de création, le scope incohérent échoue fermé **avant toute demande de clé** (nouvelle assertion `blockedVerifier.requests.isEmpty`) et ses fichiers restent inchangés |

Préconditions vérifiées en source (sans Xcode) : (1) le répertoire de base existe puis `cache` y est un fichier ordinaire → `prepareOwnedDirectory` voit `fileExists` vrai et `isDirectory` faux, et lève `protectionUnavailable` avant toute protection ; (2) `allFiles()` renvoie l'index et deux charges, l'index étant exclu de la seule assertion de nom opaque ; (3) la clé du vérificateur est identique à `fixture.key.material`, donc `loadIndex` s'ouvre et `mayCreateKey()` reste faux, tandis que le scope sans index échoue dans `loadIndex` avant l'appel au fournisseur.

Vérifications réellement exécutées (Windows, sans Swift) : `git rev-parse HEAD` = `ff670ec6…` (base annoncée) ; `git diff -U2` = trois fixtures et l'injection de clé de test, **aucun fichier produit** ; 56 méthodes de test avant et après (aucun scénario supprimé) ; délimiteurs équilibrés sur les deux fichiers ; `git diff --check` code 0 ; `git status --porcelain` = ce fichier de test et ce rapport.

Limites : **aucun GREEN local** — le RED est le run Apple cité ; Apple à réexécuter sur le candidat assemblé. Le même journal contient des échecs hors périmètre (`MessagingMediaCoordinatorTests`, `MessagingMediaOutboxTests`, `MessagingMediaPreparationTests`, `MessagingMediaRealRelayTests`, `SchoolPlanningAdmission106Tests`, `SchoolPlanningRecovery106Tests`) : ils ne sont ni reproduits, ni modifiés, ni interprétés ici. Aucun produit, API, UI, contrat cache/confinement/quota, dépendance, CI, push ou merge touché.
