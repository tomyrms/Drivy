# Reprise — audit global et corrections, 10 octobre 2026

Branche `claude/audit-global-20261010`, partie de `claude/deblocage-demandes-20261010` (`0926c48`).

Demande du porteur : audit complet (technique et UI/UX) avec corrections directes, par cycles, avec des agents en parallèle. Aucune fonctionnalité retirée, aucun déploiement implicite.

## Organisation

Trois agents au plus à la fois (limite d'usage constatée). Lots à fichiers disjoints ; les agents ne committent pas, l'intégration se fait ici par chemin.

| Lot | Périmètre | État |
| --- | --- | --- |
| API | `apps/api` | fait |
| Web | `apps/web` | fait |
| iOS A — terrain | `SchoolCapture*`, `SchoolTripsUI`, `SchoolObservation*` | fait |
| iOS B — leçons | `SchoolAgenda*`, `SchoolLessonReport*`, `SchoolLessonHistoryUI`, `SchoolUI` | fait |
| iOS C — compte et socle | `UI`, `Core`, `Identity`, `SchoolAPI`, `SchoolJoin*`, `SchoolInvitations*`, `SchoolProfile*`, `SchoolTraining*`, `SchoolCatalogAPI`, `SchoolConfigurationAPI` | fait |
| Revue croisée | diff complet de la branche | fait |

## Journal

- Cinq lots et la revue croisée intégrés, huit commits jusqu’à `071af98`. La session a été coupée une fois par la limite d’usage ; les agents ont repris sans perte.
- CI verte sur `071af98` (436 tests Swift, IPA, serveur et web). Release `071af98` déployée sur le homelab après sauvegarde.
- Synthèse : [audit-global-20261010.md](audit-global-20261010.md). Suite possible : campagne visuelle iOS (`visual_only`) et les constats laissés au porteur.
