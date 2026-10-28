# Lot 2 de l'audit UX : écrans vides et dossier (#139, #140, #154)

27 octobre 2026, branche `claude/audit-ux-lots-2-4`, partie du lot 1 (`claude/lot1-navigation-parametres`). Code iOS seulement : aucun contrat, aucune migration, rien à déployer.

## Ce qui change

| Ticket | Avant | Après |
|---|---|---|
| #139 A08 | Élève : « Dossier pas encore ouvert » avec « Ton école l'ouvrira bientôt », « Aucune formation » sans texte ni action. | Un fait sans délai promis, « Contacter l'école » (appel, SMS ou e-mail, depuis les coordonnées publiées par l'école) et « Actualiser ». Sans coordonnées, pas de bouton de contact. Une panne reste affichée en erreur. Dossier vu par l'équipe : « Aucune formation » dit « Ouvre-la sur le web » à l'administration et « L'administration l'ouvre sur le web » à un moniteur. |
| #140 A09 | Messages, contacts et recherche dans une conversation utilisaient `ContentUnavailableView` en surimpression ; Élèves et l'historique, `DrivyEmptyState` en ligne. Le choix d'un contact disait « Aucun contact » pendant le chargement et après une panne. | Même ligne `DrivyEmptyState` partout : « Aucun résultat » + « Effacer la recherche », « Aucune conversation » + « Nouvelle conversation », sous le général au lieu de le recouvrir. Contacts : chargement, panne avec « Réessayer », puis seulement « Aucun contact ». La recherche dans une conversation ne dit « Aucun résultat » qu'après sa réponse. Règle écrite dans `DESIGN.md` (États). |
| #154 A25 | L'en-tête du dossier restait un bouton sans effet quand rien ne se dépliait. | Sans dépliage : simple en-tête (trait `isHeader`), pas de bouton. Avec dépliage : bouton, valeur et indice VoiceOver inchangés. Menu de contact toujours distinct. |

Les textes et conditions propres à A45 (#166, « Aucune conversation » quand le général existe) restent pour le lot 8 ; seule la présentation change ici.

## Vérification

- Compilation par l'IPA d'essai sur GitHub Actions ; aucun test lancé avant l'essai du porteur.
- Tests UI concernés à rejouer ensuite : `MessagingThreadUITests` (attend le texte « Aucune conversation »), `SchoolEntryTests` (« Aucune formation »), `NativeNavigationTests` et `DossierRefreshTests` (en-tête du dossier).
- À vérifier à l'œil : Messages vide ou en recherche, choix d'un contact hors ligne, élève sans dossier ou sans formation (avec et sans coordonnées d'école), en clair et en sombre, iPhone et iPad, grandes tailles de texte.
