# Agenda : lectures fiables et chronologie commune

26 octobre 2026. Issues #144, #145, #146, #147, #172, #173 et #175, sous l'epic #132. #175 complète le critère d'ouverture de la leçon exacte déjà demandé par #144.

## Base et périmètre

Branche `codex/agenda-fiable-20261026`, issue de `master` `fcfdfde0408cf2a5a84ddabb54bc8bacb6693a77`. Les fichiers de l'agenda sont identiques à ceux de la branche de messagerie `6bfea69` examinée au départ. Les modifications locales du dossier principal sont conservées ; la réalisation utilise un worktree séparé.

Références : `COMMENCER_ICI.md`, R34/R37 (portée et révocation), R55/R64 (offres et engagements), T155/T156/T157 (calendrier et fuseau), contrat canonique AP147 OpenAPI 3.11.0. L'agenda réalisé utilise les extensions existantes `lessons` et `course-series` décrites dans `cours-collectifs-socle-80.md`, sans nouvelle route ni migration.

Le lot traite les erreurs de lecture, l'actualisation de toutes les sources, le filtre par formateur de séance, le tri commun des occurrences et leçons, les repères, les compteurs et la conservation du rendez-vous choisi à son ouverture. Il ne transforme pas une offre de cours en inscription et ne crée aucune autorisation locale.

## Qualification ciblée

Les transports de revue sont synthétiques et sans accès à une école réelle. Les fixtures natives `agenda-mixed` et `agenda-mixed-month` contiennent un cours à 09 h, une leçon à 11 h, un cours à 14 h et un lendemain avec seulement un cours. Les variantes `agenda-courses-error` et `agenda-courses-stale` permettent de provoquer une panne de première lecture ou de relecture.

Conformément à #132/#84, les campagnes API/PostgreSQL, web complète et ouverture d'école ne se lancent pas automatiquement sur les push/PR intermédiaires de cette branche exacte. L'exception se trouve dans `qualification-checks.yml` et `school-opening-e2e.yml`. Les déclenchements manuels, contrôles documentaires, scanners et autres branches conservent leur comportement. Retirer les deux conditions portant sur cette branche suffit à supprimer l'exception ; aucune protection GitHub n'est modifiée.

Le scope métier Apple `agenda` sélectionne les tests d'agenda, de chargement des cours et du transport synthétique. Les tests UI ciblés, captures iPhone/iPad et IPA sont exécutés séparément. Une compilation n'est pas une preuve de fonctionnement.

## Réalisation

- Natif : lecture des cours indépendante des leçons, reprise ciblée, conservation uniquement à portée identique et purge des accès refusés. Compte, école, droits, filtre, fuseau et fenêtre participent à la portée. Les réponses dépassées sont ignorées. Tirer pour actualiser et revenir au premier plan relisent les deux sources.
- Web : le bouton Actualiser et la relecture automatique relisent leçons, répertoire et cours, sans doubler les requêtes en vol ni changer sélection, focus ou recherche. L'heure globale est la plus ancienne des lectures réussies ; une source en erreur interdit le statut global « À jour ».
- Projection commune sur chaque support : ordre début, fin puis identité stable ; une occurrence est distincte de sa série. Brouillons et annulations restent identifiés. Le filtre porte sur le formateur de la séance, pas le responsable de la série. Repères et compteurs reprennent la projection affichée.
- Couverture : le contrat `course-series` est borné à 200 séries sans pagination. Atteindre cette borne rend la couverture potentiellement partielle ; aucune exhaustivité n'est affirmée. La recherche web par élève annonce son périmètre limité aux leçons. Aucune réservation, publication, inscription ou règle de droit modifiée.
- Navigation web : l'UUID de la leçon choisie est conservé dans la route. Le dossier relit le rendez-vous exact par l'endpoint existant et vérifie école, élève et leçon ; les bilans sont contrôlés avant affichage. La liste blanche BFF ajoute uniquement `GET lessons/:id`. La séance de cours sélectionnée est ciblée dans la fiche ou le formulaire existant ; une cible retirée est signalée sans sélectionner arbitrairement une autre séance.

## Preuves exécutées et restantes

Web, Node 24.22.1 : typages client/tests/serveur et build Vite réussis. 69 tests ciblés sur cinq fichiers réussis, puis 8 tests de projection réussis après alignement du départage horaire (un scénario ajouté). Le build final a été rejoué après cet ajustement.

La recette `scripts/dev/check-agenda-integration.mjs` utilise les vraies vues React avec transport synthétique. Elle a reproduit trois défauts sur la baseline avant correction : ordre 09 h/14 h/11 h, cours masqués par le filtre moniteur, cours non actualisés. Après correction : 19 contrôles réussis, aucun échec ; erreurs 503 et 403, reprise, couverture partielle, cours seuls, vrai vide, réponse tardive, navigation et focus inclus. [Résultats](proofs/agenda-20261026/web/results.json), [captures renouvelées](proofs/agenda-20261026/web/captures-results.json), [avant](proofs/agenda-20261026/web/before-1440-light.png), [après](proofs/agenda-20261026/web/after-1440-light.png), [petit écran sombre](proofs/agenda-20261026/web/after-390-dark.png). Les captures ont été inspectées : pas de débordement horizontal ou de régression visuelle bloquante relevée.

Scripts : 17 tests de sélection Apple et 11 tests de captures réussis. Revue indépendante du chargement, du contexte et des projections native/web : aucun défaut bloquant confirmé.

Complément #175/ouverture #144 : 46 tests web ciblés, typages et build réussis sous Node 24.22.1. Dix scénarios Edge supplémentaires réussis : deux leçons du même élève, retour navigateur, lien direct, rechargement, hors pagination, refus 403/404, incohérences d'identité, bilan incohérent, occurrences distinctes et occurrence retirée. [Résultats](proofs/agenda-20261026/web/lesson-context-results.json), [leçon exacte](proofs/agenda-20261026/web/selected-lesson-context.png), [occurrence ciblée](proofs/agenda-20261026/web/selected-course-occurrence.png). Les deux captures ont été inspectées ; la recette agenda précédente a été rejouée avec succès.

Sur Apple, candidat natif `290cd87` : [métier ciblé](https://github.com/tomyrms/Drivy/actions/runs/40305925081) réussi, 48 tests sans échec ni saut, et [IPA](https://github.com/tomyrms/Drivy/actions/runs/40305925127) compilée et vérifiée. Cette première IPA ne couvre pas les ajustements ultérieurs de navigation.

La revue des [premières captures de référence](https://github.com/tomyrms/Drivy/actions/runs/40305370458) sur `fda97e5` a détecté une erreur de fixture : `requestId` n'était pas un UUID, contrairement à l'enveloppe du vrai client agenda. Ces huit captures ne prouvent aucun comportement d'événement. Les [tests UI](https://github.com/tomyrms/Drivy/actions/runs/40305929146) et [captures candidates](https://github.com/tomyrms/Drivy/actions/runs/40305933009) ont été interrompus pour corriger cette cause. Quatre scénarios de transport traversant les vrais clients ont été ajoutés ; ils restent à exécuter sur Apple. La référence corrigée `37a322a` ne change que les deux identifiants synthétiques par rapport à `fda97e5` et conserve les vues avant correction.

Aucun déploiement, changement de base, données réelles ni clôture d'issue à ce stade. Ces tests UI synthétiques ne qualifient pas VoiceOver sur appareil physique, le GPS ou la batterie.
