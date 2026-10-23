# Validation finale : manifeste de vague (#84)

Vague ouverte le 21 octobre 2026. Les tests sont écrits avec le code. Leur exécution complète a lieu à la fin.

## Mode vague (IPA seulement)

- Aucun workflow modifié.
- Les push de `refonte-checks`, `school-opening-e2e` et `ipa-essai` ne se déclenchent que sur `master`, `codex/**` et `claude/**`.
- Les branches de vague `vague/**` et `openai/**` ne lancent donc aucune suite au push.
- IPA à la demande : `gh workflow run ipa-essai.yml --ref <branche>`.
- Pas de PR vers `master` avant la campagne finale. Un `pull_request` lancerait `refonte-checks` et l'e2e.
- Pas de `[skip ci]`.
- Restauration : rien à restaurer. Les déclencheurs normaux sont intacts.

Une IPA compilée prouve la construction. Elle ne prouve ni le fonctionnement ni les tests.

## Matrice

États : `PASS`, `FAIL`, `BLOCKED`, `NOT_EXECUTED`, `DEFERRED`.

| Issue | Critère | Commits | Preuve | Résultat | Point restant |
| --- | --- | --- | --- | --- | --- |
| #37 | Epic cours collectifs | | | NOT_EXECUTED | Campagne finale |
| #38 | Création et publication de séries | 7c3bcef | API : 11 tests ciblés passés une fois en local (PostgreSQL 17 jetable), hors CI | NOT_EXECUTED | Campagne finale |
| #39 | Inscription à toute la série | | | NOT_EXECUTED | Campagne finale |
| #40 | Liste d'attente prioritaire | | | NOT_EXECUTED | Activation `offerResponseMinutes` |
| #41 | Annulation et délai | | | NOT_EXECUTED | Campagne finale |
| #42 | Présences | | | NOT_EXECUTED | Campagne finale |
| #43 | Rappels et alerte minimum | | | NOT_EXECUTED | Campagne finale |
| #44 | Préférences push | | | NOT_EXECUTED | Campagne finale |
| #45 | Finance future | | | DEFERRED | Différée par sa description |
| #63 | Audio IA premium | | | DEFERRED | Différée par sa description |
| #79 | Cadrage cours | | `docs/implementation/cours-collectifs-cadrage-79.md` | NOT_EXECUTED | Revue du porteur |
| #80 | Socle cours (migration 042) | 7c3bcef | Migrations 001 à 042 appliquées en local par le harnais | NOT_EXECUTED | Tests PostgreSQL |
| #81 | Règlement sur place | | | NOT_EXECUTED | Campagne finale |
| #82 | Validation finale explicite | | | NOT_EXECUTED | Campagne finale |
| #83 | Recette cours collectifs | | | NOT_EXECUTED | Campagne finale |
| #85 | Attribution Apple Plans visible (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #86 | Temps de démarrage par étape (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #87 | Départ en attente d'une autre leçon sans blocage (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #88 | Epic tracés GPS/OSRM | | | NOT_EXECUTED | Campagne finale |
| #89 | Diagnostic capture et moteur privé (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #90 | Recalage direct ligne et marqueur (fermée, reste couverte) | | | NOT_EXECUTED | Campagne finale |
| #91 | Replay OSRM fiable, portions brutes explicites | | | NOT_EXECUTED | Campagne finale |
| #95 | Démarrage compact, choix GPS réutilisé (fermée, reste couverte) | ce7e3a8, 1826c04 | UI iPhone/iPad réussie sur ce7e3a8 | NOT_EXECUTED | Échec métier corrigé dans 1826c04, non rejoué |

Les contrôles physiques (GPS réel, arrière-plan, autonomie, VoiceOver sur appareil) restent manuels. Le simulateur ne les valide pas.
