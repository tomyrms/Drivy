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
