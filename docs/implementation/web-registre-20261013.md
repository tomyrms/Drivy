# Portail web — Registre Drivy

Décision du 13 octobre 2026. Cette passe prolonge la base `afe2140` (« Bureau de précision ») pour améliorer les listes, les contrôles et la lecture des fiches. Elle concerne le portail web. La marque La trace, Source Sans 3, le cobalt et le thème Soft Charcoal sont conservés ; le client Apple et le dossier de conception livré ne sont pas modifiés.

## Direction et différence avec la première passe

| Piste | Composition | Décision |
|---|---|---|
| **Registre Drivy** | Données comparables en colonnes, recherche et filtres réunis, petits contrôles dessinés avec précision, fiches autonomes et formulaires bornés. | Retenue pour gérer des listes d’élèves, des accès et un catalogue. Attio guide la précision des contrôles et des tables ; Shopify apporte des principes d’organisation. |
| Dossier éditorial | Identité et résumé plus développés, lignes généreuses et fiches centrées sur la lecture séquentielle. | Écartée comme direction principale : elle consomme davantage de place pour comparer de nombreux dossiers. |

La densité porte sur les informations utiles et leur alignement. Elle ne se réduit pas à diminuer la hauteur de toutes les lignes. Les contacts distinguent les homonymes, les statuts occupent une colonne cohérente, et une erreur de chargement reste différente d’une absence de donnée.

La base `afe2140` avait déjà livré le rail plat, la navigation secondaire, la recherche de paramètres, le menu du compte, Clair / Sombre / Système, le contexte de liste en mémoire et les premiers tableaux élèves/équipe. Ces acquis restent en place. Les preuves de cette première passe figurent dans [son rapport](web-redesign-20261013.md) et [sa direction](web-redesign-design-20261013.md) ; elles ne qualifient pas les nouveaux composants.

| Sujet | Base `afe2140` | Changement de cette passe |
|---|---|---|
| Élèves | Deux colonnes, identité et formation ; alerte de profil sous le nom. | Cinq colonnes : Élève, Contact, Formation, Dossier, Profil. E-mail et téléphone réels ; états ordinaires en texte. |
| Équipe | Identité et rôles ; accès inactif sous le nom. | Colonnes Membre, Rôles, Accès ; filtres d’accès, tri et pagination locale. |
| Outils de liste | Champs et sélecteurs dans une barre générique. | `RecordSearch`, `FilterTabs` et `ListPagination` ; recherche, vues de statut et filtres alignés dans `.record-toolbar`. |
| Fiche | Liste et détail associés sur écran large. | Élèves et équipe utilisent une page de fiche, avec un seul titre principal et un retour à la liste conservée dans le DOM. |
| Lecture d’un élève | Annuaire et enrichissements chargés ensemble ; sélection cherchée dans l’annuaire. | Annuaire indépendant ; lecture individuelle de l’élève hors liste et formations filtrées par son identifiant. |
| Checkbox | Contrôle natif coloré, entouré d’une case encadrée générique. | Dessin partagé, état intermédiaire et variantes `plain` / `confirmation`, avec input et label natifs. |
| Proportions | Rail 232 px, en-tête 64 px, titre jusqu’à 28 px, rayons 6/10/12 px. | Rail 216 px, en-tête 56 px, titre 24 px, rayons 5/8/10 px ; saisie de paramètres bornée à 36 rem. |

## Références, provenance et limites

L’archive `Drivy_Portail_References_et_Prompt.zip` comporte douze entrées et **aucun fichier image embarqué**. `GALERIE.html` est une galerie de cinq balises `img` : elle essaie les fichiers locaux puis les adresses publiques. Ses cartes et descriptions sont un habillage comparatif, pas des captures de produits ni des maquettes Drivy. Le script `RECUPERER_CAPTURES.ps1` n’a pas été exécuté dans cette étude.

Les références publiques documentent des versions et des comportements. Aucun compte authentifié Shopify, Stripe, Linear, Attio, Index ou monday.com n’a été consulté. La disponibilité d’une adresse d’image n’établit ni son chargement effectif dans chaque outil, ni sa date, ni la version actuelle du produit. Les valeurs de composition Drivy ci-dessous sont des décisions d’implémentation, pas des mesures attribuées aux captures tierces.

Le mandat direct autorise le choix de direction et sa réalisation. Le prompt annexe du ZIP sert à comprendre les problèmes visés ; sa demande d’approbation intermédiaire ne remplace pas ce mandat.

| Source | Enseignement retenu et limite |
|---|---|
| [Shopify — navigation](https://help.shopify.com/en/manual/shopify-admin/shopify-admin-overview) | Séparer les destinations métier et les paramètres. La documentation distingue une disposition actuelle et une refonte en déploiement ; leurs emplacements de recherche ne sont pas amalgamés. |
| [Shopify — recherche](https://help.shopify.com/en/manual/shopify-admin/admin-search) | Recherche de réglages, destination précise et repérage du contenu trouvé. Ce comportement est déjà présent dans la base Drivy et reste conservé. |
| [Stripe — Dashboard](https://docs.stripe.com/dashboard/basics) | Séparer réglages personnels, compte et produits ; relier les éléments des listes à leur détail. Les indicateurs financiers propres à Stripe ne sont pas transposés à Drivy. |
| [Linear — refonte du 28 mars 2024](https://linear.app/now/how-we-redesigned-the-linear-ui) | Vérifier ensemble en-têtes, listes, panneaux et niveaux de hiérarchie ; ajuster les alignements sur plusieurs types de vues. Les illustrations appartiennent à cette refonte historique. |
| [Linear — préférences](https://linear.app/docs/account-preferences) | Garder les préférences personnelles distinctes, dont clair, sombre et système. Drivy ne reprend pas le générateur de thèmes personnalisés. |
| [Attio — enregistrements](https://attio.com/help/reference/managing-your-data/records/create-and-view-records) | Documentation des tables filtrables et de la sélection par checkbox. La référence sert à préciser la famille de contrôles ; elle n’autorise pas à ajouter des actions groupées absentes de Drivy. |

Les cinq images référencées par le ZIP sont qualifiées séparément :

| Visuel | Provenance et limite |
|---|---|
| [Attio](https://a.storyblok.com/f/234930/1832x1478/a30a55374f/all-records-actions.png) | Illustration reliée à sa documentation ; le chargement direct a échoué dans l’outil Web pendant cette étude. |
| [Shopify](https://cdn.shopify.com/s/files/1/0643/9262/6408/files/Online_clothing_store-Add_product.png?v=1722349207) | Capture indiquée « Summer ’24 » et « EComposer Demo » dans les sources du ZIP, pas une session actuelle. |
| [Index](https://index.inc/images/Index-3.webp) | Visuel promotionnel avec décor autour de l’interface. Sa dominante bleue ne remplace pas Soft Charcoal. Le site public `index.inc` redirige désormais vers Alloy Planning. |
| Stripe | Image publique relayée par Stripe, adresse conservée dans `sources.json` du ZIP. Le panneau de droite appartient à Spackle ; il ne décrit pas une fiche native Stripe. Date non confirmée. |
| [monday.com](https://support.monday.com/hc/en-us/articles/360011905480-All-about-subitems) | Documentation des sous-éléments ; annotations et flèches appartiennent à la source. Les nombreuses couleurs de statuts ne sont pas reprises. |

## Audit et organisation des parcours

Trois constats de la base ont guidé la réalisation : l’identité seule ne distinguait pas les homonymes dans l’annuaire ; un même encadrement de checkbox servait aux filtres, permissions et confirmations ; une fiche latérale limitait la largeur disponible pour les formations et leur suivi. Le retour utilisateur portait explicitement sur les listes et ces petits contrôles.

Les propriétaires d’exécution restent [layout.tsx](../../apps/web/client/console/layout.tsx), [ui.tsx](../../apps/web/client/ui.tsx), [styles.css](../../apps/web/client/styles.css), [learners.tsx](../../apps/web/client/console/learners.tsx) et [people.tsx](../../apps/web/client/console/people.tsx). Les tableaux du catalogue conservent leurs colonnes métier et réutilisent la même famille visuelle ; leurs commandes, versions et confirmations ne changent pas de sens.

1. **Navigation stable.** Planning, Élèves, Équipe, Formations et tarifs ; Paramètres de l’école séparés. Navigation secondaire horizontale. Le compte conserve les préférences personnelles et le choix de thème.
2. **Registre.** Recherche nom/e-mail/téléphone pour les élèves, filtres de dossier et de profil, tri alphabétique réel et pagination locale de 25 lignes. L’équipe dispose des filtres d’accès et de son tri. Les comptes décrivent les données chargées ; une liste tronquée est annoncée.
3. **Lien vers la fiche.** Le nom est un lien avec une URL canonique `selection`. Le clic normal conserve la navigation locale ; les clics modifiés permettent l’ouverture native dans un nouvel onglet. Recherche, filtres, ordre et page restent en mémoire du contexte école/accès. Le retour restitue le focus à la ligne lorsque possible.
4. **Fiche autonome.** `SplitView mode="page"` masque la liste, tout en conservant son DOM. Le nom du dossier devient `h1` via `DetailPanel headingLevel={1}`. Les sections et sous-sections suivent une hiérarchie cohérente. Le formulaire de correction du profil reste directement présent lorsqu’une action est requise.
5. **Lecture explicite.** Un élève absent de l’annuaire chargé est lu par l’endpoint individuel existant AP15. Ses formations utilisent le filtre `learnerId` de l’endpoint AP22. Les réponses sont validées et vérifiées dans le bon périmètre. Une erreur ou une lecture partielle ne devient pas « Aucune formation » ; les écritures dépendantes restent indisponibles tant que les données nécessaires ne sont pas fiables.

Aucune sélection multiple, aucun export et aucune commande groupée ne sont ajoutés aux annuaires. La capacité `indeterminate` appartient au composant partagé et à sa vérification d’états. Les droits sont toujours relus au serveur. Les recherches nominatives et filtres privés ne sont ni placés dans l’URL ni persistés dans le navigateur (R95). Les contrats API et mécanismes de commandes incertaines AP72 sont conservés.

## Tokens et famille de composants

La source d’exécution est `apps/web/client/styles.css`. Les couleurs de la première passe sont conservées ; la nouvelle composition utilise leurs rôles existants.

| Rôle | Clair | Sombre Soft Charcoal |
|---|---|---|
| `canvas` | `#F2F4F7` | `#191B1E` |
| `surface` | `#FFFFFF` | `#222428` |
| `surface-muted` | `#E9EDF3` | `#303338` |
| `surface-inset` | `#F8F9FC` | `#1E2024` |
| `surface-detail` | `#FAFBFE` | `#282B30` |
| `text` | `#202936` | `#F2F3F5` |
| `muted` | `#596579` | `#B3B7BE` |
| `accent` | `#245BD6` | `#91B5FF` |
| `accent-fill` | `#245BD6` | `#3766D3` |
| `accent-soft` | `#EAF0FE` | `#2E3C56` |
| `on-accent` | `#FFFFFF` | `#FFFFFF` |
| `border` | `#DFE4EC` | `#3C4047` |
| `control-border` | `#7E899B` | `#868C95` |

| Mesure | Valeur déclarée |
|---|---|
| Typographie | Source Sans 3 variable auto-hébergée ; titre 24 px/650, détail 22 px/650 hors mode page, section 17 px/600, corps 15–16 px, métadonnées 13 px et cellules de table 14 px. |
| Structure | Rail 216 px ; en-tête 56 px ; espacements 4/8/12/16/24/32/48 px. |
| Rayons | Champ 5 px, contenu 8 px, panneau 10 px ; checkbox 3 px. |
| Contrôles | Hauteur minimale 40 px, portée à 44 px sur petit écran ou pointeur tactile. La taille visible d’un contrôle ne remplace pas sa zone interactive. |
| Checkbox | Carré de 18 px ; contour 1 px ; coche et tiret SVG de 2 px ; espace de 10 px avant le libellé. |
| Formulaires | Corps de paramètres et formulaires principaux bornés à 36 rem ; le mode fiche peut utiliser un corps plus large pour le suivi et les tableaux. |

Les hauteurs effectives des lignes et le nombre de lignes visibles doivent être mesurés sur les captures finales, avec le même contenu et la même largeur. Les valeurs mesurées de la première passe ne sont pas réattribuées à celle-ci.

| Propriétaire | Contrat d’usage |
|---|---|
| `RecordSearch` | Input `search` natif, label persistant, icône discrète, aucune mémorisation navigateur des noms saisis. |
| `FilterTabs` | Groupe de boutons `aria-pressed` qui filtre une même liste ; ce ne sont pas des panneaux d’onglets. |
| `ListPagination` | Intervalle affiché, total réel, précédent/suivant et nom accessible « Pagination des élèves » ou « Pagination des membres ». |
| `.record-table` | Colonnes comparables, identité dominante, contacts et informations secondaires lisibles, états ordinaires sans badge. À petite largeur, les cellules se présentent avec leur libellé. |
| `SplitView` / `DetailPanel` | Mode partagé conservé pour les autres usages ; mode `page` pour les registres élèves/équipe, titre principal unique et retour explicite. |
| `CheckField` | Input et label natifs ; libellé accessible relié par `aria-labelledby`, aide séparée via `aria-describedby`. Dessin commun des états vide, coché, intermédiaire, désactivé et focus. `plain` pour choix usuels ; `confirmation` pour dialogues métier et entrée par invitation. Le guide garde `plain` lorsque sa section de revue porte déjà le contexte et la conséquence de l’adoption, sans ajouter une carte imbriquée. |
| `ConfirmDialog` et entrée par invitation | Réutilisent `CheckField variant="confirmation"`. L’ancienne apparence `confirm-card` est retirée. |
| `ThemeControl` | Radios natifs avec dessin cohérent ; les choix Clair/Sombre/Système et leur persistance restent inchangés. |
| `.editor-save-bar` | Barre d’enregistrement fixe dans le défilement seulement si largeur et hauteur du viewport dépassent 40 rem ; retour dans le flux sur écran étroit ou bas pour garder les champs visibles. |

Survol, focus clavier et état coché ont des traitements distincts. Le focus général reste de 3 px ; le groupe de checkbox porte un contour de focus de 2 px autour du label. En couleurs forcées, checkbox et radio reviennent au dessin natif, les SVG décoratifs de checkbox sont masqués. Les badges restent réservés aux exceptions et les ombres aux superpositions. Le sombre utilise toujours les tokens sémantiques et `html[data-theme]`, y compris dans les dialogues et menus.

## Résultat et preuves

La réalisation produit `1c43c35` est terminée et **déployée le 14 octobre 2026 à 00:10 Europe/Zurich**, après demande explicite du porteur et sauvegarde de la base vérifiée. [Portail](https://drivy.shulker.ch/app/) · [déploiement et retour arrière](web-registre-deployment-20261014.md).

- **26 parcours locaux**, **439 tests API/PostgreSQL**, **233 tests web** et **80 contrôles intégrés OIDC/BFF/API/PostgreSQL** réussis ; types et compilations réussis.
- **210 configurations visuelles distinctes**, clair et sombre à 1440/1024/390 px, sans débordement du document ni erreur JavaScript. **140 audits axe distincts** sans violation ; deux contrastes indéterminés résolus par inspection et mesure complémentaires, avec les résultats bruts conservés.
- Quatre écrans comparés avant/après dans les deux thèmes : élèves, dossier, coordonnées et équipe. Huit captures de référence `afe2140` préservées avec empreintes. [Galerie](proofs/web-registre-20261013/index.html).
- [Vérification détaillée, pages et parcours exécutés, corrections et limites](web-registre-verification-20261014.md).

La recherche, la navigation, les fiches, les thèmes et le catalogue utilisent les composants communs. Les pages d’entrée, d’ouverture, d’invitation et d’opérateur, ainsi que les six étapes du guide, ont été exercées avec les nouvelles fondations. Les routes existantes et les contrats sont préservés ; aucune modification des écrans natifs.

Le vrai zoom navigateur à 200 %, un lecteur d’écran, Safari et la recette avec une auto-école restent à qualifier. Le reflow 720 CSS px/DPR 2 ne vaut pas un zoom natif. Aucune certification WCAG complète ni qualification physique Apple n’est déduite de ces contrôles.
