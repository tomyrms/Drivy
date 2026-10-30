# #311 — Réglages de l’école (#330, R19), première partie

Reconstruit par le coordinateur le 29 octobre 2026, dans `portal/settings/`, section `configuration` (onglet « École » de Réglages).

- Fait : `settings.identity` (coordonnées lues puis éditées dans un formulaire ciblé, `updateSchool` avec `If-Match`, conflit avec rechargement proposé, validation près des champs, focus rendu au bouton Modifier), `settings.timezone` (fuseau affiché comme référence, non modifiable faute de contrat), `settings.activation` (école en préparation renvoyée vers la préparation).
- Après confirmation, la page revient à la lecture ; aucun succès avant le reçu.
- Fait ensuite (`portal/settings/privacy-page.tsx`) : page Confidentialité (option GPS de l’école avec confirmation d’identité préalable, textes de confidentialité lus puis modifiés, revue d’adoption avec effet sur les accords GPS et trajets en cours lu au serveur, case de relecture obligatoire, publication conjointe des informations proposées quand aucune n’est publiée, liens vers conditions commerciales et déroulement) et page Informations des élèves (résumé par champ, édition par choix exclusif et raison obligatoire, aperçu du formulaire élève, avertissement de planification, revue avec case de relecture). Logique de `privacy-model.ts` et commandes `saveDataPolicy`, `createProfilePolicy`, `updateModules` inchangées.
- Reste de #330 : recherche de réglages (`settings.search`) et lien profond vers un champ révélé.

Exécuté : typage, 472 tests web, builds, captures 1440/390 en clair et sombre (enregistrement des coordonnées, revue d’adoption des textes avec effet GPS, édition mobile des informations demandées). Non exécuté : adoption et publication confirmées jusqu’au bout, refus et conflit en navigateur, confirmation d’identité réelle, vraie BFF.
