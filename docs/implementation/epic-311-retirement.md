# #334 / R23 — Retrait de l’ancien frontend

Reprise du 29 octobre 2026, après le raccord de toutes les routes au nouveau portail en `f99d4940`. Le graphe complet de `client/main.tsx` a été vérifié avant suppression : il ne rejoignait déjà aucun ancien rendu, aucune ancienne feuille CSS ni l’aperçu fictif. Les suppressions ne remplacent aucun écran actif.

## Suppressions

**60 fichiers retirés**, dont la liste exacte est conservée dans [epic-311-retired-renderers.json](epic-311-retired-renderers.json) :

| Famille | Retrait |
| --- | --- |
| Entrée et compte | Anciennes vues App, compte, récupération, ouverture, préférences, notifications et confirmation d’identité |
| Ancienne console | Tous les rendus `.tsx` de `client/console`, notamment formulaires, fiches et guides historiques |
| Contrôles hérités | `ui.tsx`, `choice-field.tsx`, `person-avatar.tsx` |
| Styles | 15 feuilles CSS historiques, dont styles Studio, ancien shell, agenda, formulaires et dossiers |
| Sélection de présentation | `legacy-styles.ts`, `presentation.ts`, `portal/components/not-rebuilt.tsx` |
| Ancienne galerie | `test/visual.html` et `test/visual.tsx` |

Les modèles, protocoles, contrôleurs purs, transport, commande/reçu, routes, garanties de session et leurs tests sont conservés. `main.tsx`, `BrandSymbol.tsx`, les composants `components/ui` et les rendus actifs `portal` restent les seules familles de JSX du client. La migration des anciens liens `presentation=…` est traitée par le raccord de l’entrée ; ce retrait ne modifie pas ses routes ni les données.

Les huit scripts historiques qui utilisent `test/visual.html` (`capture-web-280`, `check-agenda-integration`, `check-audit-regressions`, `check-audit-v2-regressions`, `check-v3-agenda`, `check-web-redesign`, `check-web-280-access`, `measure-web-280`) restent des outils de comparaison d’anciennes révisions. Ils ne qualifient pas #311 et ne doivent pas être exécutés contre la branche courante. Ils ne sont appelés par aucun workflow GitHub Actions. L’aperçu courant et sa recette sont indiqués dans `apps/web/README.md`.

## Frontière vérifiée

`test/portal-boundary.test.ts` utilise désormais l’AST TypeScript et suit imports statiques, réexports, imports différés littéraux et imports CSS locaux. Il contrôle séparément l’entrée réelle `main.tsx` et l’ensemble des modules de production du portail. Il refuse une dépendance locale absente, un import différé non borné, l’ancien rendu/CSS, l’aperçu fictif dans la production, et la présence physique des fichiers de présentation retirés. Il vérifie aussi les raccords entrée, récupération, compte, opérateur, préparation et console.

Le contrôle des modules réellement émis par Vite appartient à l’intégration finale du coordinateur ; cette vérification du graphe source ne prétend pas le remplacer.

## Exécuté et différé

- Avant suppression : trois contrôles depuis l’entrée réelle **PASS**.
- Après suppression : huit contrôles de frontière **PASS**.
- Typage client et typage serveur/tests sous Node 24.22.1 : **PASS**.
- `git diff --check` : **PASS**.

Aucun test de sécurité existant n’est supprimé ou affaibli. Aucune campagne générale, aucun test PostgreSQL ni mobile physique n’est revendiqué par ce nettoyage. Builds, recette de l’intégration et déploiement restent coordonnés sur le SHA assemblé ; matrice complète et campagnes étendues attendent le retour du porteur.
