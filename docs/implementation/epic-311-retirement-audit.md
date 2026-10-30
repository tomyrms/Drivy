# R23 · Audit des imports et parité avant retrait

Inspection en lecture seule du worktree d’intégration le 29 octobre 2026, avant la suppression coordonnée. Le graphe des imports TypeScript/TSX/CSS a été parcouru depuis tous les modules du portail hors aperçu. Ce contrôle statique ne remplace pas la recette du produit.

## Retrait permis par le graphe

Aucun module métier `.ts` ni nouvelle vue ne dépend des 40 anciennes vues ci-dessous. Les seuls entrants depuis le reste du client étaient les imports dynamiques de `main.tsx`. Les vues sont donc retirables ensemble après bascule de cette entrée et remplacement de la galerie `test/visual.tsx`.

Chemins relatifs à `apps/web/client` :

```text
App.tsx
account-entry.tsx
account-recovery.tsx
choice-field.tsx
identity-confirmation.tsx
notification-preferences.tsx
person-avatar.tsx
preferences.tsx
school-opening.tsx
ui.tsx
console/Console.tsx
console/agenda.tsx
console/availability.tsx
console/configuration.tsx
console/courses.tsx
console/directory.tsx
console/dossier.tsx
console/formation-editors.tsx
console/formation-references.tsx
console/formation-sheet.tsx
console/formations.tsx
console/gps-consent.tsx
console/gps-settings.tsx
console/layout.tsx
console/learners.tsx
console/lesson-planning.tsx
console/observation-themes.tsx
console/overview.tsx
console/people.tsx
console/planning-readiness.tsx
console/prerequisite-help.tsx
console/privacy.tsx
console/profile-completion.tsx
console/profile-fields-preview.tsx
console/profile-fields.tsx
console/school-setup.tsx
console/settings-search.tsx
console/shared-terms-editor.tsx
console/theme-icons.tsx
console/trips.tsx
```

Les 15 feuilles historiques peuvent partir avec elles : `access.css`, `choice-field.css`, `person-avatar.css`, `school-opening.css`, `styles.css`, puis sous `console/` : `agenda-studio.css`, `formations-studio.css`, `observation-themes.css`, `people-workspace.css`, `planning-workspace.css`, `portal-shell.css`, `profile-fields-preview.css`, `school-setup.css`, `settings-studio.css`, `trips-workspace.css`.

Supprimer également `legacy-styles.ts` après la bascule. `presentation.ts` reste référencé par `portal/components/not-rebuilt.tsx` : retirer ce repli vers l’ancienne interface et ses appels avant de retirer ce sélecteur. Ne pas confondre ce sélecteur avec les modules de présentation métier `portal/agenda/presentation.tsx` ou `portal/courses/course-presentation.ts`, qui restent utiles.

## Logique à conserver

Conserver tous les `.ts` métier et runtime de `console/` : `access-reader`, `agenda-projection`, `context`, `course-model`, `draft-model`, `formation-model`, `list-state`, `load-model`, `management-runtime`, `navigation`, `observation-themes-model`, `privacy-model`, `profile-completion-model`, `route`, `sections`, `settings-search-model`.

Conserver les modèles et protocoles à la racine du client, dont `account-entry-route`, `invitation-link`, `school-opening-model`, `identity-confirmation-model`, `command-*`, `school-api`, `formation-api`, `formation-programme-update`, `lesson-planning-model`, `setup-model`, `setup-progress`, `swiss-prerequisites`, `learner-course-facts`, `notification-preferences-*`, `theme` et `ui-suspension`. Conserver `main.tsx`, `BrandSymbol.tsx`, les composants shadcn et les assets de marque/police/licence.

Les exports purs jadis mêlés aux anciennes vues ont déjà leurs équivalents : `readCourseCatalogue` dans `portal/courses/course-catalogue`, `referenceDestination` dans `portal/formations/sheet-routing`, formatage dans les familles du portail, logique d’entrée dans `portal/entry`. Aucun helper supplémentaire n’est requis par le graphe actuel pour autoriser le retrait des 40 vues.

## Parité trouvée et correction de ce lot

L’ancien agenda rendait `PlanningReadinessBanner` et `FirstLessonActions`. Leur absence dans le nouveau agenda retirait le guidage scolaire : blocages `CAN_PLAN_LESSON`, puis invitation du premier élève, dossier, formation, affectation, disponibilité et premier rendez-vous.

Le lot de correction reconstruit ces deux composants sous `portal/agenda`, avec les mêmes lectures serveur `readiness` et `setup-draft/next-actions`, les mêmes destinations et le même état de réduction par code d’action. Aucun nouveau calcul de droit ou d’éligibilité n’est ajouté. Chaque blocage conserve sa destination connue ; un code de destination inconnu reste lisible sans fabriquer de route. Les réponses sont contrôlées pour l’école courante. Actualiser l’agenda et confirmer une commande relisent aussi la préparation.

La prochaine action `PLAN_FIRST_LESSON` ouvre l’agenda avec `view=nouvelle` et l’élève annoncé par le serveur. Les autres tâches passent par le routeur et ses gardes ; les paramètres sont filtrés avec `readNavigationQuery`. Le guide disparaît selon la réponse serveur une fois le premier rendez-vous confirmé. UI : Alert, Card, Collapsible et Button shadcn, sans ancienne feuille ni ancien JSX.

Point rare encore à vérifier : `console/prerequisite-help.tsx` avait un texte et un lien officiel propres aux catégories G/M ainsi qu’un lien de source en repli pour les démarches sans repère. `portal/learners/learner-information.tsx` affiche seulement « Aucun repère disponible » dans ce cas. Il conserve les faits de cours et leurs refus via `usePrerequisites`, mais ce repli documentaire est une différence réelle, pas seulement stylistique.

## Outils et campagnes à adapter

`apps/web/test/visual.tsx` importe la plupart des anciens rendus et les contrôles historiques. Son entrée `test/visual.html` doit être remplacée ou retirée avec la galerie, pas laissée cassée. Les fichiers de tests métier `.test.ts` n’importent pas ces anciens TSX ; ils ciblent les modèles conservés.

Outils liés à cette galerie : `scripts/dev/check-audit-regressions.mjs`, `check-audit-v2-regressions.mjs`, `check-agenda-integration.mjs`, `check-v3-agenda.mjs`, `check-web-280-access.mjs`, `check-web-redesign.mjs`, `capture-web-280.mjs`, `measure-web-280.mjs`. Ils utilisent `/app/test/visual.html`, parfois des hooks de fixture et les classes `.console-content`, `.console-nav`, `.agenda-lesson`. La mesure #280 lit aussi `test/visual.tsx`. Les archiver ou porter vers le nouvel aperçu avec des assertions métier équivalentes ; ne pas les faire réussir en supprimant leurs assertions.

La campagne effective `.github/workflows/school-opening-e2e.yml` exécute `scripts/dev/check-school-opening.ts`. Ce script attend notamment `.account-entry .notice.error` pour les refus d’inscription. Ses appels au parcours `check-school-first-lesson.ts` et à `check-v3-agenda-acceptance.ts` attendent aussi `details.schedule-add`, `.blocker-list`, `.invitation-facts`, `.profile-completion`, `.agenda-lesson` et des noms de boutons/combobox historiques. Ces sélecteurs devront être portés avant la campagne post-essai. Les vérifications de persistance, compte différent, réponse perdue, premier rendez-vous et absence de mutation interdite doivent rester.

## Vérifications du correctif agenda

18 tests ciblés PASS : destinations du premier rendez-vous, frontières du portail, routes de console. Typage client `tsc --noEmit` PASS avec Node 24 et une copie temporaire du lot d’entrée #319, exclue du commit ; à relancer après intégration de tous les lots. Aucun ancien fichier supprimé par cet agent, aucune campagne complète exécutée, aucun déploiement.
