# Portail web — Bureau de précision

Décision du 13 octobre 2026. Périmètre : portail web, entrée, invitations et préparation de l’école. Les écrans et le thème clair Apple restent inchangés. Le dossier de conception livré est conservé.

## Direction retenue

Deux pistes ont été comparées avant l’implémentation :

| Direction | Composition | Décision |
|---|---|---|
| **Bureau de précision** | Navigation stable, tables compactes, dossiers structurés, formulaires alignés et peu de surfaces encadrées. | Retenue : lisibilité des listes et des réglages, densité et continuité avec les assets Drivy. |
| Carnet de l’école | Dossiers plus éditoriaux, marges généreuses et davantage de repères chronologiques. | Écartée pour le portail : adaptée au suivi pédagogique, moins efficace pour les tâches de gestion. |

Le logo « La trace », le cobalt et Source Sans 3 sont conservés. Le portail utilise une surface de travail continue, un rail de navigation et un en-tête compact. Les repères de marque restent attachés à une information ; les formulaires ne reçoivent pas de motifs décoratifs. Aucune statistique n’est ajoutée pour remplir un accueil.

## Références réellement examinées

Les cinq références officielles ont été lues. Les captures « After » de l’article Linear et « Preferences » de sa documentation ont été ouvertes et observées dans le navigateur. Aucun compte authentifié Shopify, Stripe ou Linear n’a été utilisé.

| Référence | Observation et adaptation Drivy |
|---|---|
| [Navigation Shopify](https://help.shopify.com/en/manual/shopify-admin/shopify-admin-overview) | Les ressources métier et réglages disposent d’entrées distinctes. Drivy conserve cinq destinations réelles et un état actif constant. La documentation distingue l’interface actuelle d’une refonte en déploiement : leurs emplacements de recherche ne sont pas amalgamés. |
| [Recherche Shopify](https://help.shopify.com/en/manual/shopify-admin/admin-search) | Un résultat de réglage conduit à sa destination et peut souligner le contenu trouvé. Drivy indexe les champs et synonymes, ouvre la page et place le focus sur la cible. |
| [Dashboard Stripe](https://docs.stripe.com/dashboard/basics) | Les réglages personnels, du compte et des produits sont distingués ; les listes permettent d’accéder aux détails. Drivy sépare les paramètres de l’école des préférences personnelles et conserve le contexte de liste au retour. |
| [Refonte Linear, 28 mars 2024](https://linear.app/now/how-we-redesigned-the-linear-ui) | Les en-têtes, listes et panneaux sont éprouvés ensemble ; les neutres prennent moins de bleu. Drivy vérifie la même direction sur une liste, une fiche et un formulaire, en clair et sombre. La capture historique ne représente pas une session actuelle de Linear. |
| [Préférences Linear](https://linear.app/docs/account-preferences) | La capture organise les préférences en rangées et la documentation décrit clair, sombre et système. Drivy rend ce choix personnel disponible dans le compte et sur une page dédiée. |

Ces décisions adaptent des comportements documentés ; elles ne reproduisent pas les produits de référence.

## Architecture et parcours

- Rail stable : Planning, Élèves, Équipe, Formations et tarifs, Paramètres de l’école. Aucun accordéon à découvrir pour trouver une destination principale.
- Navigation secondaire horizontale pour les pages du groupe actif. Les sous-pages profondes conservent leur fil d’Ariane et leur retour contextuel.
- Paramètres de l’école séparés du compte. La recherche indexe destinations, sections, champs et synonymes ; un résultat personnel ouvre les préférences.
- Liste : recherche, filtres, tri explicite et décompte réel ; tableaux pour les élèves et l’équipe. Retour visible depuis la fiche. La recherche de personnes reste en mémoire du parcours, **jamais dans l’URL** (R95).
- Fiche : nom et état utile en tête, informations regroupées, actions au bon endroit. « Profil à compléter » mène aux champs manquants et conserve les erreurs de lecture ou d’écriture.
- Coordonnées de l’école : formulaire à labels persistants, validation au champ, enregistrement explicite et état de sauvegarde. Les modifications non enregistrées sont protégées lors du départ.
- Mobile : Menu déplie la navigation dans le flux. Échap ferme ce menu et rend le focus à son bouton ; aucun faux panneau modal sans gestion du focus.

## Tokens et composants

Source d’exécution : `apps/web/client/styles.css`. Couleurs des pages, dialogues, menus, aperçus et formulaires prises dans des tokens sémantiques. Les anciens styles de navigation accordéon sont retirés ; les doublons de règles de base sont consolidés.

| Token | Clair | Sombre Soft Charcoal |
|---|---|---|
| `canvas` | `#F2F4F7` | `#191B1E` |
| `surface` | `#FFFFFF` | `#222428` |
| `surface-muted` | `#E9EDF3` | `#303338` |
| `surface-inset` | `#F8F9FC` | `#1E2024` |
| `surface-detail` | `#FAFBFE` | `#282B30` |
| `text` | `#202936` | `#F2F3F5` |
| `muted` | `#596579` | `#B3B7BE` |
| `accent` (encre, liens, focus) | `#245BD6` | `#91B5FF` |
| `accent-fill` (action primaire) | `#245BD6` | `#3766D3` |
| `accent-pressed` | `#1947AD` | `#2F58B8` |
| `accent-soft` | `#EAF0FE` | `#2E3C56` |
| `on-accent` | `#FFFFFF` | `#FFFFFF` |
| `border` | `#DFE4EC` | `#3C4047` |
| `control-border` | `#7E899B` | `#868C95` |

Les surfaces sombres sont anthracite neutre. L’accent d’encre et l’aplat d’action sont distincts pour garder des textes lisibles. Succès, avertissement et erreur restent des rôles indépendants du branding de l’école. Le filet `border` structure le contenu ; il ne remplace pas le contour visible `control-border` d’un champ.

- **Type** : Source Sans 3 variable auto-hébergée ; titre 24–28 px/650, fiche 22 px/650, section 17 px/600, corps 15–16 px, métadonnées 13–14 px. Heures, prix et dates en chiffres tabulaires.
- **Mesures** : échelle 4/8/12/16/24/32/48 px ; rail 232 px ; en-tête 64 px ; contrôle 40 px desktop, 44 px tactile/petit écran. Cibles de déplacement des signalements conservées à 44 px.
- **Tables élèves et équipe** : au-dessus de 640 px avec pointeur fin et survol, action de ligne de 32 px et marges verticales de cellule de 6 px. La mesure dans Edge donne 45 px par ligne simple, contre 57 px avant cet affinage ; les informations secondaires augmentent naturellement cette hauteur. Sur petit écran ou pointeur tactile, les actions restent à 44 px minimum. Les six états élèves/équipe × ordinateur/tactile/petit écran ont été mesurés sans débordement horizontal.
- **Formes** : rayon contrôle 6 px, contenu 10 px, panneau 12 px ; ombres réservées aux menus superposés, pas aux tableaux ni aux boutons. Les dialogues utilisent un fond opaque et un voile sémantique.
- **États** : focus visible 3 px, sélection avec libellé/état accessible, survol réservé aux pointeurs fins ; mouvement réduit et couleurs forcées conservés.
- **Composants partagés** : boutons, champs, cases, listes, tableaux, `SplitView`, `DetailPanel`, messages, dialogue natif, `AccountMenu`, `ThemeControl`, `SettingsSearch` et barre de sauvegarde. Les CSS spécifiques à l’ouverture, au guide et à l’aperçu des champs réutilisent les mêmes tokens.

## Thème et persistance

`html[data-theme="light"|"dark"]` représente le thème résolu. Le choix Clair/Sombre/Système est appliqué avant le chargement de la feuille de style ; le CSS ne suit directement `prefers-color-scheme` qu’en absence de cet attribut. Le logo suit aussi le thème résolu.

Le choix est conservé sur le navigateur et ne modifie pas l’école. Le mode Système suit ses changements ; un choix manuel reste prioritaire. Une impossibilité de conserver la préférence produit une erreur explicite. Les radios natifs restent accessibles au clavier.

## Qualification et limites

La mesure de contrastes couvre **60 couples de tokens, 60 conformes au seuil testé** : texte utile à 4,5:1, contours de contrôle et focus à 3:1. [Mesures reproductibles](proofs/web-redesign-contrast-20261013.json).

| Couple | Clair | Sombre |
|---|---|---|
| Texte / surface | 14,67:1 | 14,00:1 |
| Secondaire / surface | 5,90:1 | 7,72:1 |
| Texte de l’action primaire / aplat | 5,93:1 | 5,25:1 |
| Contour de champ / surface | 3,54:1 | 4,59:1 |

Ces calculs ne constituent pas à eux seuls une certification WCAG. L’inspection des pages, les captures aux différentes largeurs et les tests exécutés sont consignés dans le suivi de réalisation et `STATUS.md`. Les preuves locales avant/après utilisent uniquement des données synthétiques dans `artifacts/web-redesign-20261013/`. Aucun résultat de lecteur d’écran physique, GPS ou batterie n’est déduit de ces essais web.
