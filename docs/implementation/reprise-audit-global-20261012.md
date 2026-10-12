# Reprise — audit global et corrections, 12 octobre 2026

Branche `claude/audit-global-20261012`, partie de `master` (`668deaa`). Session CC1.1.

Demande du porteur : audit technique et fonctionnel de toute l’application (iOS, API, web), puis corrections, tests et bilan chiffré par priorité (P0 à P3). Suite des passes du [10 octobre](audit-global-20261010.md) et du [11 octobre](audit-parcours-20261011.md) : leurs constats ouverts ne sont pas à redécouvrir, seulement à traiter s’ils sont tranchés.

## Garde-fous

- Aucune donnée de production touchée, aucun déploiement, aucune migration appliquée ailleurs que sur une base de test.
- Confirmation du porteur avant tout changement important du comportement métier ou du contrat d’API.
- Direction artistique inchangée (bleu `#245BD6`, clair figé, sombre Soft Charcoal).
- Trois agents au plus à la fois (limite d’usage). Les agents d’audit ne modifient rien ; les agents de correction ont des fichiers disjoints et ne committent pas.

## Phases

| Phase | Contenu | État |
| --- | --- | --- |
| 1 | Compréhension du dépôt, des audits précédents, des skills | fait |
| 2 | Audit en lecture seule, cinq agents en deux vagues | en cours |
| 3 | Consolidation, priorités | à faire |
| 4 | Corrections P0 → P3, par lots à fichiers disjoints | à faire |
| 5 | Améliorations UI/UX | à faire |
| 6 | Validation (typage, tests API et web, IPA, tests Swift sur la CI) | à faire |
| 7 | Bilan : `audit-global-20261012.md`, `STATUS.md`, PR | à faire |

## Agents d’audit

Les rapports sont écrits hors du dépôt, dans le dossier temporaire de la session ; la synthèse ira dans `audit-global-20261012.md`.

| Agent | Périmètre | État |
| --- | --- | --- |
| 1 — iOS, écrans et états | `SchoolUI`, `SchoolAgenda*`, `SchoolLessonReport*`, `SchoolLessonHistoryUI`, `SchoolTraining*`, `SchoolProfile*`, `SchoolJoin*`, `SchoolInvitations*` | lancé |
| 2 — API et base | `apps/api`, migrations, cohérence avec les clients iOS et le serveur web | lancé |
| 5 — fiabilité, concurrence, sécurité | `SchoolCapture*`, `SchoolTripsUI`, `SchoolObservation*`, file des commandes, `Identity`, `Core` | lancé |
| 3 — UI/UX et design system | `UI/`, toutes les vues, console web | à lancer |
| 4 — architecture et code mort | tout le dépôt | à lancer |

## Journal

- 12 octobre : branche créée, phase 1 faite, première vague lancée.

## Pour reprendre (Codex ou autre session)

Lire ce fichier, puis `audit-global-20261012.md` s’il existe. `git status` et `git log master..HEAD` disent ce qui est intégré. Les skills utiles sont dans `.claude/skills/<nom>/SKILL.md` : `write-swift`, `swiftui-ui-patterns`, `swiftui-liquid-glass`, `apple-design` pour iOS ; `baseline-ui`, `fixing-accessibility` pour le web. Compilation Swift : pousser avec `[skip ci]` puis `gh workflow run "IPA d'essai · iLoader" --ref <branche>` ; tests Swift : `gh workflow run "Refonte · iOS" --ref <branche> -f unit_only=true`.
