# #311 — Réglages de l’école (#330, R19), première partie

Reconstruit par le coordinateur le 29 octobre 2026, dans `portal/settings/`, section `configuration` (onglet « École » de Réglages).

- Fait : `settings.identity` (coordonnées lues puis éditées dans un formulaire ciblé, `updateSchool` avec `If-Match`, conflit avec rechargement proposé, validation près des champs, focus rendu au bouton Modifier), `settings.timezone` (fuseau affiché comme référence, non modifiable faute de contrat), `settings.activation` (école en préparation renvoyée vers la préparation).
- Après confirmation, la page revient à la lecture ; aucun succès avant le reçu.
- Reste de #330 : informations élèves (`champs-profil`) et leur aperçu, confidentialité et textes, impact sur GPS et captures, option GPS scolaire, conditions versionnées, recherche de réglages. Sources : `console/privacy.tsx`, `privacy-model.ts`, `profile-fields-preview.tsx`, `gps-settings.tsx`, `settings-search*`.

Exécuté : typage, 472 tests web, build d’aperçu, captures 1440/390 en clair et sombre, enregistrement complet dans l’aperçu. Non exécuté : refus et conflit en navigateur, vraie BFF.
