# Passe native — compte, dossier et accès à l’école

Cette passe conserve l’identité native de Drivy. Elle améliore la place des actions, la densité et l’adaptation aux grandes tailles de texte. Les changements concernent dix fichiers de vues ; ni l’API ni les règles de partage ou de persistance ne sont modifiées.

## Références et méthode

`AGENTS.md` et `COMMENCER_ICI.md` ont été lus, ainsi que les règles de profils et de dossier R05–R06 et R17–R20, les dispositions applicables des contrats AP01–AP20, et les scénarios liés aux profils, invitations et lectures de progression. La décision de partage automatique du 28 septembre prévaut sur les anciennes mentions de publication manuelle.

Guides appliqués : `ui-skills-root` et son catalogue SwiftUI, `swiftui-ui-patterns` avec les références Form, List, NavigationStack, split views et theming ; `better-layout` avec regroupement et adaptation ; `better-typography`, `better-writing`, `better-accessibility` et les principes de hiérarchie de `refactoring-ui`. Les contrôles système, les couleurs sémantiques et les composants Drivy sont conservés.

Les captures suivantes ont été ouvertes réellement, sans retouche :

- Dossier iPhone clair, dossier iPad clair et progression iPhone sombre du run `36722303236`, source `9c77dd64298f5417845a042d1c0e1f88961fa2e0`, sous `artifacts/retours-20260930/visual/36722303236/`.
- Profil, saisie du code d’école et accueil d’onboarding iPad clair des preuves `artifacts/review-20260929/gallery-proofs/ui-account-orientation-e720-20260929.json`, source `e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0`.

Ces images documentent des versions précédentes. Le diagnostic a été confronté au code courant ; elles ne qualifient pas le rendu des modifications de cette passe.

## Changements

| Écran | Fichiers | Modification et objectif |
| --- | --- | --- |
| Profil et trajets | `SchoolUI/SchoolProfileTabView.swift`, `SchoolTripsUI/SchoolTripsView.swift` | Le profil regroupe le compte et les destinations utiles. Une entrée « Trajets » ouvre la liste dédiée, avec ses filtres, sa pagination, son actualisation et la réouverture des trajets conservés. Les préférences de leçon sont placées dans le même groupe. Le titre n’est plus répété dans le contenu de la destination. |
| Compte et édition du profil | `SchoolUI/SchoolAccountComponents.swift`, `SchoolProfileUI/SchoolProfileView.swift` | Avatar ramené de 72 à 52 points, masqué aux tailles d’accessibilité. La barre Enregistrer paraît lorsqu’une modification est présente ou pendant l’écriture. Suppression du doublon du libellé de naissance et du placeholder « Facultatif » du téléphone, qui pouvait contredire une règle d’école. Ligne biométrique de 52 points minimum. |
| Onboarding | `SchoolProfileUI/SchoolOnboardingView.swift` | Colonne de formulaire adaptée à l’iPad ; icône et titre réunis sur une rangée. L’illustration prend 44 points au lieu de 88. Les étapes, refus, consentements et demandes de permission restent identiques. |
| Rejoindre une école | `SchoolJoinUI/SchoolCodeJoinView.swift`, `SchoolJoinUI/SchoolJoinView.swift` | Champ du code réduit de 80 à 64 points minimum, police de base de 36 à 28. Dans la confirmation, emblème de l’école et nom sont alignés ensemble, puis les informations suivent. Les choix et accusés de lecture restent inchangés. |
| Code d’invitation | `SchoolInvitationsUI/SchoolInvitationsView.swift` | Le code utilise une ou deux rangées de quatre caractères selon la place disponible. Suppression du rétrécissement de police à 40 % et du filet décoratif. Aux tailles d’accessibilité, police système body monospaced en gras, sans interlettrage ajouté. La valeur complète épelée pour VoiceOver, la copie avec expiration et le partage sont conservés. |
| Dossier d’un élève | `SchoolUI/SchoolBrowserView.swift` | Démarrer et Planifier occupent une barre commune de 52 points minimum, côte à côte puis empilés aux tailles d’accessibilité. La même barre existe pour un dossier à une ou plusieurs formations. Les actions gardent les conditions de rôle, d’école active et d’archivage existantes ; le démarrage passe par le sélecteur de formation existant. Les contacts placent leurs actions sous la valeur aux grandes tailles de texte. |
| Leçons et progression | `SchoolTrainingUI/SchoolTrainingView.swift` | Réduction des espacements entre groupes et de l’avatar. Les filtres et la période forment un libellé qui peut revenir à la ligne. Leur valeur d’accessibilité inclut le tri. Dans les compétences, texte et indicateur passent en disposition verticale aux tailles d’accessibilité ; les niveaux et liens vers la leçon source sont conservés. |

## Accès, interactions et qualification

Les commandes durables, la gestion de demande en attente, la validation de profil et les contrôles serveur restent en place. Les préférences ne s’affichent que pour les rôles déjà prévus. Les boutons de contact restent des liens natifs avec cibles de 44 × 44 points. Les détails du dossier et la visibilité des données privées ne sont pas modifiés.

Identifiants pour la vérification intégrée : `profile-list` reste la liste du profil ; `profile-open-trips` ouvre la destination dont la liste est `trips-list` ; `profile-planning-settings` ouvre les préférences. `learner-start-now`, `learner-plan-lesson` et `invitation-code-value` restent stables. La fixture d’édition doit effectuer une modification avant de chercher le bouton Enregistrer.

`git diff --check` sur les dix fichiers ne signale aucune erreur de contenu, seulement les avertissements de normalisation CRLF habituels. Les vues ont été relues avec leurs appelants. Aucun test Apple, rendu du nouveau code ou essai matériel n’est déclaré par ce lot à ce stade. L’agent principal centralise la compilation, les tests et les captures iPhone/iPad, dont les tailles d’accessibilité. VoiceOver physique, GPS et batterie restent hors de cette revue.

Une seconde lecture indépendante du lot agenda a vérifié les formulaires, prix, conditions de disponibilité et contrôles d’auteur. Un risque de sélection périmée au nouveau Réessayer du démarrage après échec de stockage a été signalé à son propriétaire : le rechargement doit revalider l’élève et ses formations. Ce point est traité dans le lot agenda, sans modification de ces fichiers par le présent lot.
