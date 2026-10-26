# Vague parcours du 26 octobre 2026

Le porteur a demandé la réalisation des cinq lots proposés dans le chat : bilan (#162/#163), fondations de réactivité et pilote réglages (#106/#107/#119), finalisation de la réactivité Messages (#104), formulaires et cours (#143/#99), récupération d'accès et planning web (#50/#51).

## Base et coordination

- Branche de réalisation : `codex/bilans-reactivite-parcours-20261026`, worktree isolé. Les changements non commités du checkout du porteur ne sont pas importés.
- Base : travail messagerie jusqu'à `da7f8f3` (dont #169/#170/#141), fusion de `origin/master` à `71390e9` (agenda #178). Ces correctifs préexistants sont conservés.
- Dossier de conception conservé. Les décisions du 28 septembre sur le partage automatique priment sur les anciens textes de publication.
- Propriétaires distincts : bilan/messagerie/identité/intégration ; fondations web ; fondations natives ; cours et formulaires natifs.

## Périmètre et preuve attendue

| Lot | État initial de cette vague | Livraison attendue |
|---|---|---|
| #162/#163 | À réaliser | Conservation du brouillon vérifiée, erreur sans fermeture, action terminale explicite. |
| #106/#107/#119 | À réaliser, mécanismes existants à réutiliser | Socles minimaux par dépendance réelle, lectures autorisées, adoption complète du pilote préférences ; autres parcours documentés pour adoption progressive. |
| #104 | Déjà partiellement implémenté | Intentions protégées après relance, reprise/convergence et recette sous latence. |
| #143/#99 | À réaliser | Sorties des formulaires sans perte silencieuse et points A30/A31/A32/A33/A34/A37/A38/A39. |
| #50 | À réaliser | Récupération via fournisseur d'identité existant, canal vérifié et tests isolés. |
| #51 | À réaliser | Création/déplacement/annulation de leçons dans le bureau web avec commandes métier existantes. |

## Vérification

Tests ciblés utiles pendant les lots, compilation Apple et IPA non signée sur GitHub Actions. Campagne intégrée #84 après intégration du périmètre retenu. Les résultats, SHA et limites sont ajoutés au fil de l'exécution dans les rapports de lot et `STATUS.md`. Aucun test physique ni VoiceOver réel ne peut être déduit d'un simulateur. Les déploiements ne sont pas des effets implicites d'une compilation.
