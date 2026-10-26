# Agenda : lectures fiables et chronologie commune

26 octobre 2026. Issues #144, #145, #146, #147, #172 et #173, sous l'epic #132.

## Base et périmètre

Branche `codex/agenda-fiable-20261026`, issue de `master` `fcfdfde0408cf2a5a84ddabb54bc8bacb6693a77`. Les fichiers de l'agenda sont identiques à ceux de la branche de messagerie `6bfea69` examinée au départ. Les modifications locales du dossier principal sont conservées ; la réalisation utilise un worktree séparé.

Références : `COMMENCER_ICI.md`, R34/R37 (portée et révocation), R55/R64 (offres et engagements), T155/T156/T157 (calendrier et fuseau), contrat canonique AP147 OpenAPI 3.11.0. L'agenda réalisé utilise les extensions existantes `lessons` et `course-series` décrites dans `cours-collectifs-socle-80.md`, sans nouvelle route ni migration.

Le lot traite les erreurs de lecture, l'actualisation de toutes les sources, le filtre par formateur de séance, le tri commun des occurrences et leçons, les repères et les compteurs. Il ne transforme pas une offre de cours en inscription et ne crée aucune autorisation locale.

## Qualification ciblée

Les transports de revue sont synthétiques et sans accès à une école réelle. Les fixtures natives `agenda-mixed` et `agenda-mixed-month` contiennent un cours à 09 h, une leçon à 11 h, un cours à 14 h et un lendemain avec seulement un cours. Les variantes `agenda-courses-error` et `agenda-courses-stale` permettent de provoquer une panne de première lecture ou de relecture.

Conformément à #132/#84, les campagnes API/PostgreSQL, web complète et ouverture d'école ne se lancent pas automatiquement sur les push/PR intermédiaires de cette branche exacte. L'exception se trouve dans `qualification-checks.yml` et `school-opening-e2e.yml`. Les déclenchements manuels, contrôles documentaires, scanners et autres branches conservent leur comportement. Retirer les deux conditions portant sur cette branche suffit à supprimer l'exception ; aucune protection GitHub n'est modifiée.

Le scope métier Apple `agenda` sélectionne les tests d'agenda, de chargement des cours et du transport synthétique. Les tests UI ciblés, captures iPhone/iPad et IPA sont exécutés séparément. Une compilation n'est pas une preuve de fonctionnement.

## État initial

Préparation des fixtures et des sélections de tests. Aucun correctif produit qualifié ni déploiement à ce stade. Les résultats et liens seront ajoutés après exécution. GPS, batterie et VoiceOver sur appareil physique ne sont pas qualifiés par ce lot.
