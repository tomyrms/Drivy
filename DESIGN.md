---
version: alpha
name: Drivy · Web et Apple
description: La trace prolonge Cartographie native côté Apple et unifie la marque du web Bureau. Les tokens structurés de cet en-tête concernent Apple uniquement ; les tokens web figurent dans la section Web.
colors:
  canvas: "#F7F8FA"
  surface: "#FFFFFF"
  surface-muted: "#EEF2F7"
  text: "#18212B"
  muted: "#536174"
  accent: "#245BD6"
  accent-pressed: "#1947AD"
  on-accent: "#FFFFFF"
  accent-soft: "#EAF0FE"
  success: "#17633D"
  success-surface: "#E9F5EE"
  warning: "#7A4D00"
  warning-surface: "#FFF3D6"
  danger: "#B02B37"
  danger-surface: "#FDECEF"
  border: "#D9E0E9"
  control-border: "#78869A"
  rail: "#C3CDD9"
  disabled-text: "#5D6A7C"
  disabled-surface: "#E8EDF3"
  route: "#245BD6"
  route-halo: "#FFFFFF"
typography:
  body:
    fontFamily: system-ui
    fontSize: 17px
    fontWeight: 400
  body-web:
    fontFamily: system-ui
    fontSize: 16px
    fontWeight: 400
  metadata:
    fontFamily: system-ui
    fontSize: 14px
    fontWeight: 400
  screen-title:
    fontFamily: system-ui
    fontWeight: 700
  title:
    fontFamily: system-ui
    fontWeight: 700
  section:
    fontFamily: system-ui
    fontWeight: 600
rounded:
  field: 12px
  content: 16px
  map-panel: 24px
spacing:
  xxs: 4px
  xs: 8px
  s: 12px
  m: 16px
  l: 24px
  xl: 32px
  xxl: 48px
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.content}"
    height: 52px
  button-primary-pressed:
    backgroundColor: "{colors.accent-pressed}"
    textColor: "{colors.on-accent}"
  button-primary-disabled:
    backgroundColor: "{colors.disabled-surface}"
    textColor: "{colors.disabled-text}"
  button-secondary:
    backgroundColor: "{colors.surface-muted}"
    textColor: "{colors.accent}"
    rounded: "{rounded.content}"
    height: 52px
  button-secondary-pressed:
    backgroundColor: "{colors.accent-soft}"
  selection-card:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.content}"
  selection-card-selected:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.text}"
  inline-message:
    rounded: "{rounded.field}"
    padding: "{spacing.s}"
  error-notice:
    backgroundColor: "{colors.danger-surface}"
    textColor: "{colors.danger}"
    rounded: "{rounded.content}"
    padding: "{spacing.m}"
---

# Drivy · Web et Apple

La direction web Bureau du 30 septembre est conservée. À la demande du porteur le 9 octobre, la proposition **La trace** du 6 octobre est intégrée : ligne et repère dans les parcours Apple, même symbole et même cobalt côté web. Les structures de navigation, surfaces Bureau et règles métier restent celles de chaque surface. Référence : [Brand System](docs/implementation/brand-system.md) et [intégration](docs/implementation/brand-integration-20261009.md).

Le dossier `Drivy_Conception_v3_17_2026-09-20` reste une livraison conservée. La première passe est consignée dans [web-direction-20260930.md](docs/implementation/web-direction-20260930.md), puis remplacée par [l’architecture des parcours web](docs/implementation/web-architecture-20260930.md) et [la passe esthétique encre et papier](docs/implementation/web-craft-20260930.md). La référence native détaillée reste ci-dessous et dans [la grille iOS](docs/implementation/DESIGN.md).

## Web · Studio, référence Mercury

Le 14 octobre 2026, le porteur rejette Registre et choisit explicitement la démo Mercury pour la refonte du portail. **Studio** en reprend la composition, les proportions et le dessin des commandes, adaptés au cobalt Drivy et au sombre anthracite. La trace est conservée ; Manrope auto-hébergée remplace Source Sans 3 pour le web. Cette section prévaut sur les descriptions web historiques du document ; l’en-tête structuré et les règles Apple restent distincts. [Direction et composants](docs/implementation/web-studio-20261014.md) · [Benchmark et couverture réelle](docs/implementation/web-studio-benchmark-20261014.md) · [Provenance de la police](apps/web/client/assets/fonts/README.md).

### Composition et navigation

- Rail de 220 px, barre supérieure de 56 px : Planning, Élèves, Équipe, Formations et tarifs puis Paramètres de l’école. Les pages de la famille courante apparaissent sous cette destination dans le rail ; la bande horizontale qui répétait la navigation est retirée. Sur petit écran, Menu déplie la navigation dans le flux et Échap la ferme.
- Les paramètres disposent de leur propre navigation avec Retour à la gestion, réglages de l’école et préférences personnelles. L’école courante reste explicite ; le changement d’école n’est proposé qu’aux comptes concernés. Les droits restent relus au serveur.
- Les listes séparent recherche, vues et commandes de filtre. Colonnes utiles, contacts pour distinguer les homonymes, compteur réel et pagination locale conservés. Les noms sont lisibles dans l’encre principale ; le focus et le survol annoncent leur action. Aucun export, avatar ou choix multiple sans fonction ou donnée réelle.
- Les fiches d’élèves et de membres, ainsi que les versions et éditeurs du catalogue, remplacent la liste à toutes les largeurs. `SplitView mode="page"` garde son contexte monté ; le retour explicite restitue le focus. Le nom de la fiche ou de l’éditeur devient son titre principal.
- Les identifiants, semaine et catégorie autorisés restent dans l’URL. Recherches nominatives, filtres privés et page locale restent en mémoire du contexte personne/école/droits. La recherche de paramètres indexe uniquement les fonctions implémentées et ouvre/focalise le champ correspondant.
- L’agenda reste l’entrée quotidienne. Préparation et catalogue décrivent les actions et états serveur réels ; aucun indicateur décoratif n’est ajouté depuis la référence bancaire.

### Tokens et composants

Les tokens d’exécution sont dans `apps/web/client/styles.css`. Manrope variable 200–800 est servie localement, avec `font-display: swap`. Titre de page 28/36 px, graisse 450 ; titre secondaire 20/28 px, graisse 500 ; section 16/24 px, graisse 550 ; corps 15/24 px ; secondaire 14/21 px ; métadonnées 13/19,5 px. Espacements 4/8/12/16/24/32/48 px. Rayons 8 px champs, 12 px contenus, 14 px panneaux ; actions primaires/secondaires en capsule. Contrôles courants 40 px, déclencheurs de choix 42 px, grandes cibles tactiles 44 px. Les champs de filtre ont une enveloppe plus compacte que les champs de saisie.

| Rôle | Clair | Sombre Soft Charcoal |
|---|---|---|
| canvas | `#F7F8FA` | `#191B1E` |
| surface | `#FFFFFF` | `#222428` |
| surface-muted | `#EBEDF1` | `#303338` |
| surface-inset | `#F5F6F8` | `#1E2024` |
| surface-detail | `#FAFBFC` | `#282B30` |
| text | `#272C36` | `#F2F3F5` |
| muted | `#626977` | `#B3B7BE` |
| accent (lien, focus) | `#245BD6` | `#91B5FF` |
| accent-fill (action) | `#245BD6` | `#3766D3` |
| on-accent | `#FFFFFF` | `#FFFFFF` |
| accent-soft | `#EDF2FE` | `#2E3C56` |
| border | `#E5E7EC` | `#3C4047` |
| control-border | `#858C98` | `#868C95` |

Surfaces opaques et séparations discrètes. Les ombres de superposition servent aux menus ; de petites ombres de contrôle peuvent distinguer le choix sélectionné. Les cartes ne deviennent pas le contenant systématique de chaque section. Les couleurs sémantiques ne prennent jamais la couleur d’une école ; les badges signalent les exceptions.

Réutiliser `SectionHeading`, `SplitView`, `DetailPanel`, `TextField`, `TextArea`, `LoadState`, `OutcomeNotice` et `ConfirmDialog`. `SelectField` est une primitive partagée à menu ancré, avec recherche pour les listes longues ; `SegmentField` montre directement les choix courts à l’aide de radios natifs. Le texte recherché dans un menu ne change pas la valeur métier. Les choix restent accessibles au clavier, désactivables et nommés ; le menu d’un dialogue reste dans sa couche modale.

`RecordSearch`, `FilterTabs` et `ListPagination` composent les outils des listes. `FilterTabs` filtre par boutons pressés et ne simule pas un changement de panneau. `record-table` organise les colonnes comparables ; le traitement compact propre aux personnes est isolé dans `people-table`. Les tables de catalogue conservent les libellés associés à leurs valeurs sur petit écran. `DetailPanel headingLevel={1}` donne un seul titre principal aux fiches.

`CheckField` conserve l’input natif, un libellé via `aria-labelledby` et une aide distincte via `aria-describedby`. `plain` sert aux choix usuels ; `confirmation` aux dialogues métier et à l’entrée par invitation. La revue du guide peut porter elle-même la conséquence et garder `plain`. Aucun état intermédiaire ne crée implicitement une sélection de masse. En couleurs forcées, checkbox et radios retrouvent leur dessin natif.

### Paramètres, thème et enregistrement

Les coordonnées commencent par des lignes de lecture libellé/valeur, de proportion initiale 38/62 ; Modifier ouvre un formulaire borné à 36 rem. La confidentialité sépare textes consultables, date d’adoption, contact et modification. Les informations demandées utilisent des choix directs sans modifier leurs règles. Les aperçus du thème illustrent le rail et le contenu. `settings-studio.css` porte seulement cette composition locale.

`theme-init.js`, script externe compatible CSP exécuté avant React, applique Clair/Sombre/Système. `theme.ts` suit les changements système et d’onglet. Seule la préférence `drivy.web.theme` est en localStorage ; ni compte ni école ni dossier. L’indisponibilité du stockage est signalée. `html[data-theme]` gouverne les composants et le logo ; le repli sans attribut suit le système.

Coordonnées : enregistrement explicite, erreurs associées, état réel et succès seulement après réponse durable. Annuler restaure la dernière valeur confirmée même si la relecture serveur est encore en attente. Confidentialité, consentements, accès et commandes destructives gardent leurs confirmations métier. `useUnsavedChanges` protège les saisies ; les commandes incertaines restent suivies par AP72. Les dialogues du catalogue conservent leurs versions et la relecture avant écriture.

La barre `editor-save-bar` peut rester en bas quand largeur et hauteur dépassent 40 rem ; elle revient dans le flux sur écran étroit ou bas. Les formulaires locaux de paramètres restent dans le flux. Une action persistante ne doit masquer ni champ ni erreur.

### Accessibilité et vérification

Liens de navigation réels, noms accessibles, focus visible, lien d’évitement et dialogues HTML natifs avec restitution de focus. Mouvement réduit, contraste accru et couleurs forcées restent pris en charge. Pas d’action au seul survol. Les routes et cibles de recherche sont conservées ; la préférence personnelle dispose d’un retour interne validé.

Les preuves du 13 octobre décrivent les passes précédentes ; la palette claire, la police et les composants ont changé et doivent être requalifiés. Le [document Studio](docs/implementation/web-studio-20261014.md) distingue la provenance des références, les premiers pilotes et la campagne de vérification à compléter. Un reflow géométrique n’atteste pas un zoom natif à 200 %. Calculs et tests automatiques ne constituent ni une certification WCAG ni une validation sur lecteur d’écran physique.

## Apple · Cartographie native conservée

**Portée du reste de ce document : client natif Apple.** Les valeurs structurées de l’en-tête et les anciennes correspondances iOS/web ci-dessous décrivent le système natif conservé et l’harmonisation historique du 25 septembre ; elles ne prescrivent plus le thème web. Source native : dossier de conception et `apps/ios/Drivy/UI/DrivyTheme.swift`. Ne pas modifier les tokens du dossier livré pour implémenter une décision récente.

**Statut natif.** Cartographie native est prolongée par La trace : un rail, des repères annelés et le symbole du kit du 6 octobre. Un token `rail` est ajouté aux tokens 3.8 ; il est décoratif et ne porte jamais seul une information. Durées, dimensions de panneaux et comportement physique restent soumis à qualification sur appareil.

## Overview

**Le trajet devient le support de l’explication.** Interface lumineuse, carte fonctionnelle, bleu franc, hiérarchie de texte précise. L’identité vient de la relation entre séance, moment observé et prochaine étape, pas de décor routier. La direction vaut pour le moniteur comme pour l’élève ; la densité dépend de la tâche.

Cinq règles d’expression, à appliquer à chaque écran :

1. **Une zone de décision dominante.** Un seul geste suivant évident par vue (préparation : commencer la bonne séance ; capture : signaler en gardant l’arrêt accessible ; replay : revoir une observation ; web : trouver le dossier et agir sous les bons droits). Une seule action primaire par vue.
2. **Bleu intentionnel.** `accent` signale action, sélection et trace, chacun dans son rôle. Il ne colore pas toutes les icônes, titres et surfaces. Une limite de places ou un refus GPS n’est pas une alerte rouge.
3. **Surfaces calmes.** Fond clair, panneaux opaques, encre sombre. Ombre uniquement pour une superposition. Une liste n’a pas besoin d’une carte arrondie par ligne.
4. **Le texte utile, pas le texte accumulé.** Titres alignés à gauche, labels permanents, montants et heures alignés. Aucune phrase promotionnelle à la place du prochain rendez-vous.
5. **Natif sans imitation.** SwiftUI et les contrôles Apple fournissent navigation, feuilles, formulaires et barres. Le web a sa propre navigation clavier ; Android futur aura son langage. On traduit des rôles, pas des pixels.

## Colors

Toujours consommer une couleur par son rôle (`DrivyTheme.*` en Swift, `var(--*)` en CSS). Jamais de `Color` littérale, de `.gray`/`.secondary`, ni d’hexadécimal dans une vue.

| Rôle | Usage |
|---|---|
| `canvas` | Fond des formulaires et listes groupés. |
| `surface` | Fond des pages de lecture ; cartes web. |
| `surface-card` | Fond de `DrivyCard`, `DrivyPanel`, carte de sélection, champ de code. |
| `surface-raised` | Bloc posé sur une page ou sur la carte : panneau, bannière, marqueur, rangée de formulaire, champ guidé. |
| `surface-muted` | Remplissage neutre ou interactif : bouton secondaire, pastille neutre, avatar, ligne pressée. |
| `text` / `muted` / `text-tertiary` | Encre principale / métadonnées, aides, icônes de ligne / chevrons décoratifs. |
| `accent` | Liens, symboles, contour de sélection, teinte système. |
| `accent-fill` / `accent-pressed` / `on-accent` | Aplat de l’action primaire ; état pressé ; texte sur l’aplat. |
| `accent-soft` | Fond de sélection et de pastille d’accent, bouton secondaire pressé. |
| `success`, `warning`, `danger` + `*-surface` | Texte et fond d’un état ; toujours avec symbole et libellé. |
| `*-signal` | L’appréciation d’un signalement **dessinée** (pictogramme, anneau, pastille, repère de frise) : plus claire que l’encre, jamais pour du texte. |
| `border` / `control-border` | Séparateur décoratif doux / contour d’un contrôle interactif (champ, marque de sélection vide). |
| `disabled-text` / `disabled-surface` | Contrôle indisponible. |
| `route` / `route-halo` | Trace mesurée sur la carte et son halo (5 pt + halo 9 pt de référence). |

Les couleurs de fond de carte du prototype (`mapCanvas`, `mapPark`, `mapWater`) sont schématiques : MapKit dessine le vrai fond.

## Themes

Le sombre est **Soft Charcoal** : un anthracite neutre où un bloc est plus clair que la page qui le porte. Ce n’est pas une inversion du clair, dont les valeurs ne changent pas. Décisions, références et mesures : [dark-soft-charcoal-20261011.md](docs/implementation/dark-soft-charcoal-20261011.md).

| Token | Clair | Sombre | Sombre dans une feuille |
|---|---|---|---|
| canvas | #F7F8FA | #17191C | #1D1F23 |
| surface | #FFFFFF | #17191C | #1D1F23 |
| surface-card | #F7F8FA | #272A2E | #2A2D31 |
| surface-raised | #FFFFFF | #272A2E | #2A2D31 |
| surface-muted | #EEF2F7 | #34383D | #373B40 |
| text | #18212B | #F4F5F6 | |
| muted | #536174 | #A1A5AD | |
| text-tertiary | #536174 | #8E939C | |
| accent | #245BD6 | #86ABF8 | |
| accent-fill | #245BD6 | #3D70E2 | |
| accent-pressed | #1947AD | #325FC4 | |
| on-accent | #FFFFFF | #FFFFFF | |
| accent-soft | #EAF0FE | #2F3B54 | |
| success / success-surface | #17633D / #E9F5EE | #7CCFA0 / #2B423B | |
| warning / warning-surface | #7A4D00 / #FFF3D6 | #E5BE7A / #453E30 | |
| danger / danger-surface | #B02B37 / #FDECEF | #FF9DA3 / #473338 | |
| success-signal / warning-signal / danger-signal | #26A058 / #D1760E / #E5484D | #7CCFA0 / #E5BE7A / #FF9DA3 | Appréciation dessinée : 3:1 minimum, jamais pour du texte. |
| border / control-border | #D9E0E9 / #78869A | #3A3E44 / #82878F | |
| rail | #C3CDD9 | #454A51 | |
| disabled-text / disabled-surface | #5D6A7C / #E8EDF3 | #7A7F87 / #303338 | |
| route / route-halo | #245BD6 / #FFFFFF | #4D80EB / #17191C | |

- En sombre, le bleu a trois rôles : `accent` pour l’encre (liens, symboles, teinte système), `accent-fill` pour un aplat qui porte `on-accent`, `route` pour le tracé (le bleu de référence `#4D80EB`).
- Une feuille ou un popover prend le niveau système « elevated » : la page et ses blocs montent d’un cran sans code dans la vue.
- Contraste accru, en sombre : `muted` `#C2C6CD`, `text-tertiary` `#A1A5AD`, `accent` `#A8C3FB`, `border` `#5C616A`, `control-border` `#A1A5AD`.
- Le web garde ses propres tokens (section Web) ; les valeurs natives ne s’y recopient pas.

## Typography

Police système uniquement, aucune police embarquée. Les tailles de la frontmatter sont des **références** : sur Apple, on utilise les styles de texte Dynamic Type, jamais une taille en points.

| Rôle | Swift | Web | Usage |
|---|---|---|---|
| Titre d’écran | `.drivyScreenTitle` (largeTitle bold) | `h1` | Nom ou date en tête d’un écran de détail. |
| Titre | `.drivyTitle` (title2 bold) | `h2` | Titre d’une feuille ou d’une carte dominante. |
| Section | `.drivySection` (title3 semibold), via `DrivySectionHeader` | `h2`/`h3` de section | Titre de section, trait d’en-tête accessible. |
| Titre de ligne | `.headline` | `h3`, `strong` | Première ligne d’une rangée. |
| Corps | `.body` | `p` (16 px, interligne 1,6) | Lecture. |
| Méta | `.subheadline` | `.muted`, 0,875–0,9375 rem | Détail, école, lieu. |
| Aide | `.footnote`, `.caption` | `.caption`, `.small-label` | Aide, légende, pastille. |

- Chiffres, heures, durées et montants : `.monospacedDigit()` / `font-variant-numeric: tabular-nums`.
- Paragraphe web limité à environ 65 caractères ; `text-wrap: balance` pour les titres, `pretty` pour les paragraphes.
- Graisses autorisées : 400, 500, 600, 700.

## Layout

**Deux types de page, jamais mélangés :**

- **Page de lecture** (`ScrollView`) : fond `DrivyTheme.surface`, contenu dans `.drivyPageContent()` (marge horizontale `l`, largeur de lecture 720 pt centrée sur iPad). Les blocs groupés y sont des `DrivyPanel`/`DrivyCard`, remplis par `surfaceCard`.
- **Formulaire ou liste groupés natifs** (`Form`/`List`) : `.scrollContentBackground(.hidden)` + `.background(DrivyTheme.canvas)` ; sections natives, pas de cartes maison. `drivyFormRows()` pose `drivyRowContext = .grouped` : les lignes partagées y prennent le rythme des Réglages (corps, 44 pt, surbrillance et chevron système), comme un `NavigationLink` voisin. Un en-tête de compte se pose sur le fond (`drivyClearRow()`), pas dans une cellule.

**Titres de navigation :** titre large uniquement sur les écrans de premier niveau (onglets Agenda, Élèves, Profil) ; Aujourd’hui, posé sur la carte, est en titre inline ; tout écran poussé ou feuille est en titre inline.

**Feuilles :** « Fermer » (ou « Annuler » s’il y a une saisie à abandonner) toujours en `.cancellationAction` ; la droite est réservée à la confirmation.

**Cible tactile :** `DrivyLayout.tapTarget` (44), jamais le littéral.

**Rythme :** `s` (12) dans un groupe, `l` (24) entre sujets, padding de bloc `m` (16). Marge de page : 24 en compact, 32 en régulier (`DrivySpacing.page`). Aucune valeur magique hors échelle.

**Adaptation :** en taille d’accessibilité, les rangées horizontales basculent en vertical (`AnyLayout` HStack → VStack) au lieu de tronquer ou de réduire une cible. Pas de hauteur fixe tirée d’une maquette à une ligne.

**Web :** colonne principale `min(820px, 100%)`, marges 2 rem puis 1,25 rem sous 600 px ; boutons empilés en mobile ; aucun défilement horizontal à 320 px.

**iPad et carte (proposition) :** panneau de capture de 320 à 400 pt à côté de la carte en largeur régulière, en bas sur téléphone ; points de rupture logiques 600 et 1024.

## Elevation & Depth

- Surfaces de lecture, formulaires, montants et coordonnées : **opaques**. Hiérarchie par surface (page, puis `surfaceCard`/`surfaceRaised`, puis `surfaceMuted`) et filet `border` de 0,5 pt, pas par ombre. En sombre, chaque marche éclaircit d’environ 1,2:1.
- Un fond de page s’écrit `.background(DrivyTheme.surface)` ou `canvas` ; un bloc posé dessus (forme arrondie, rangée, marqueur) prend `surfaceCard` ou `surfaceRaised`, jamais la couleur de page.
- Sur la carte, un panneau flottant garde son ombre (`drivyShadow`, plus dense en sombre) et reçoit en sombre un filet `border`.
- **Liquid Glass** uniquement pour les commandes qui flottent sur une carte (suivre, voir tout le trajet, pastilles d’origine), via `.drivyMapControl(in:)`, regroupées dans un `GlassEffectContainer`. Jamais de thème vitre global, jamais de vitre sur un formulaire ou un texte long.
- Le chrome système (barres, onglets, feuilles) garde le matériau natif de la plateforme.
- Web : une seule ombre très légère sur `.card` en clair, aucune en sombre.

## Shapes

- `field` (12) : champs, messages en ligne, bouton Réessayer, ligne pressée.
- `content` (16) : boutons, cartes de sélection, notices d’erreur.
- `map-panel` (24) : panneaux sur carte ; cartes web.
- Toujours `RoundedRectangle(..., style: .continuous)`. Rayons concentriques : `DrivyCard`/`DrivyPanel` = `content` + padding.
- Les contrôles système gardent leur géométrie.

## Components

Réutiliser avant de créer. Un motif partagé manquant se crée dans un nouveau fichier `apps/ios/Drivy/UI/DrivyComponents+<Périmètre>.swift`, préfixé `Drivy`.

| Composant iOS | Usage | Équivalent web |
|---|---|---|
| `DrivyPrimaryButtonStyle` | L’unique action dominante de la vue (52 pt, pressé 0,96). | `.button.primary` (≥ 48 px) |
| `DrivySecondaryButtonStyle` | Action alternative. | `.button.secondary` ; `.button.quiet` pour une action texte |
| `DrivyStatusBadge(title:symbol:tone:)` | Tout statut (En cours, Partagé, Privé…). Pas un bouton. | — (à créer au besoin avec les mêmes rôles) |
| `DrivyStatusDot` | État vivant court (« GPS actif »). | — |
| `DrivySectionHeader(title:actionTitle:action:)` | Titre de section, action texte facultative (44 pt). | `.section-heading` |
| `DrivyNavigationRow` | Ligne qui ouvre un détail : ≥ 64 pt et titre de ligne sur une page de lecture, 44 pt et corps dans une liste groupée. Chevron `DrivyRowChevron`. | `.school-list li` |
| `.buttonStyle(.drivyText)` | L’unique action en texte (accent, sous-titre semi-gras, 44 pt). | `.button.quiet` |
| `DrivyRowGroup(title:)` | Lignes séparées par des filets, sans carte par ligne. | liste à filets `border-top` |
| `DrivyRowButtonStyle` | Retour d’appui d’une ligne. | `:active` |
| `DrivyTimeColumn` | Heure de début/fin alignée. | `tabular-nums` |
| `DrivyAvatar` | Initiales sur cercle neutre ; jamais photo factice ni faux logo. | `.symbol` |
| `DrivyEmptyState` | Vide dans une section, avec une action. `ContentUnavailableView` pour un écran entier vide. | `.empty-state` |
| `DrivyCard` | Bloc de la décision dominante (prochaine séance, leçon en cours). | `.card` |
| `DrivyPanel` | Bloc groupé sur page blanche. | `.card` |
| `DrivyContextHeader` | Ligne de contexte (école, date) sous la barre. | `.eyebrow`, `.identity-strip` |
| `DrivyInlineMessage(text:tone:)` | Succès ou alerte près de l’action, hors `Form`. | `.notice.success` / `.warning` |
| `SchoolErrorNotice(message:retry:)` + `DrivyRetryButton` | Erreur avec reprise. | `.notice.error` + bouton |
| `DrivySelectionCardStyle(isSelected:)` + `DrivySelectionMark` | **Unique** motif de sélection (fond `accent-soft`, contour accent, coche). | `input` natif `accent-color` |
| `DrivyTileButtonStyle` | Grandes tuiles du signalement (catégorie, statut). | — |
| `.drivyMapControl(in:)` | Commande flottante sur carte (Liquid Glass). | — |
| `DrivyRouteGlyph` | Illustration schématique ; jamais une position enregistrée. | `.brand-symbol` |

Une même action n’a pas deux versions concurrentes ; des actions différentes (naviguer, sélectionner, enregistrer, publier) ne se déguisent pas en contrôle identique. Chevron = ouvrir ; coche = inclure ; aucun accessoire = lire ; un statut d’enregistrement immédiat n’a pas de chevron.

## États

Chaque vue couvre ses états, fondés sur le résultat réel du service, jamais sur un délai d’animation.

| État | Règle | iOS | Web |
|---|---|---|---|
| Chargement | Un texte nomme l’opération (« Ouverture des séances… »). | `ProgressView` + libellé | `.loading` + `.spinner`, `aria-busy`, `.skeleton-card` |
| Vide | Explique le prochain geste et propose une action ; zéro n’est pas une erreur masquée. | `DrivyEmptyState` / `ContentUnavailableView` | `.empty-state` |
| Erreur | Près de la cause, conséquence, saisie conservée, reprise. | `SchoolErrorNotice` + `DrivyRetryButton` | `.notice.error` |
| Succès | Bref, seulement après écriture durable ; pas de toast comme seule preuve. | `DrivyInlineMessage(tone: .success)` | `.notice.success` |
| Désactivé | Toujours expliquer pourquoi, près du contrôle. | `.disabled` + texte | `:disabled` + `.caption` |
| Demande incertaine | Distinguer confirmé, refusé et **résultat inconnu** ; l’inconnu garde l’intention sans réserver ni libérer. Un 202 n’est pas « Inscrit ». | badge `warning` + texte | `.notice.warning` |

Statut = symbole + texte + couleur (`DrivyTone` : neutral, accent, success, warning, danger). Donnée absente autorisée : « Non renseigné » ; donnée interdite : omise.

## Mouvement et haptique

| Motion | Valeur | Usage |
|---|---|---|
| `DrivyMotion.press` | ressort 0,18 s sans rebond | Appui (échelle 0,96), interrompable. |
| `DrivyMotion.feedback` | ease-out 0,12 s (120 ms) | Changement d’état provoqué par le système. |
| `DrivyMotion.context` | snappy 0,18 s (180 ms) | Changement de contexte d’un panneau. |
| Web | 120–140 ms, `cubic-bezier(.2, 0, 0, 1)` | Bouton, bordure. |

- Toutes les animations maison sont nulles sous Réduire les animations (`prefers-reduced-motion`). Les transitions système ne sont pas surchargées.
- Haptique de sélection sur le choix d’une catégorie de signalement ; haptique de **succès uniquement après l’écriture locale durable** de l’observation. Aucune animation ne bloque une commande de capture.
- Survol web limité à `(hover: hover) and (pointer: fine)` ; retour d’appui sur `:active`.

## Accessibilité

- Cibles ≥ 44 pt/px, ≥ 48 pour les actions primaires et critiques (Arrêter, Signaler). Grand texte : on empile, on ne réduit pas.
- Dynamic Type complet, aucun texte tronqué (`fixedSize(horizontal: false, vertical: true)` sur les textes multilignes).
- Icône seule = label accessible ; icônes décoratives masquées ; rangées combinées ; titres de section avec trait d’en-tête.
- Ne jamais modifier un `accessibilityIdentifier` existant (tests UI).
- Web : lien d’évitement, `:focus-visible` 3 px avec décalage, focus restitué, erreurs associées au champ, `forced-colors` pris en charge.
- Contraste vérifié sur les surfaces réelles, en clair, sombre et contraste accru ; aucune conformité WCAG globale annoncée depuis un calcul de palette.

## Écriture UX

Français clair, phrases courtes, verbes précis. Côté personnel : libellés d’action impersonnels (« Publier le bilan »). Côté élève : tutoiement proposé. Titres qui décrivent la tâche (« Prochaine leçon », « À travailler ensuite »). Pas de slogan, faux encouragement, jargon technique ni promesse inventée. Ne jamais altérer le sens juridique, de consentement ou de confidentialité d’un texte. Heures en 24 h, dates explicites, CHF.

**Glossaire des termes stables**

| Terme | Sens et limite |
|---|---|
| Séance | Moment de conduite ; aussi l’onglet principal (« Séance », majuscule en destination). |
| trajet | Tracé GPS mesuré d’une séance ; « Trajet indisponible » s’il est retiré. |
| leçon | Rendez-vous de formation planifié par l’école. |
| observation | Moment pédagogique signalé (thème + statut) ; jamais un nombre de fautes. |
| bilan | Synthèse : travaillé, constat, prochaine étape ; « Bilan partagé » seulement après publication confirmée. |
| Permis B | Catégorie de formation, écrite telle quelle. |
| Signaler | Ajouter une observation pendant la capture ; « Le choix enregistre. » |
| Privé / Partagé | Visibilité réelle ; jamais « Sauvegardé » sans destination. |
| GPS actif / en pause / arrêté, Sans GPS | État réel de la capture ; « Synchronisé » n’est jamais le seul état. |
| Sur cet appareil · non partagé | Brouillon local. |
| Non observé | Absence de niveau, pas une note zéro. |
| Disponible · Non inscrit / Inscrit | Offre vue / inscription confirmée par le serveur. |
| Moniteur, Élève, Administration | Rôles affichés dans l’école. |

## Do's and Don'ts

- Ne pas utiliser de dégradé (ni géant à l’accueil, ni décoratif).
- Ne pas mettre d’effet vitre sur les formulaires ni de thème vitre global.
- Ne pas afficher de score de conduite dérivé du GPS, de pourcentage de profil ou de progression inventée.
- Ne pas montrer de fausse donnée : position inventée, carte factice, fausse présence, publication ou inscription obtenue pour la démonstration, faux logo d’école réelle.
- Ne pas relier deux segments séparés par une lacune ; « Aucune position mesurée pendant cette interruption. »
- Pas de mascotte, de confetti, de mosaïque de cartes statistiques sans tâche.
- Pas de commande cachée dans un seul geste de balayage.
- Pas de succès avant écriture durable ; pas d’erreur réseau affichée comme « zéro dossier ».
- Pas de rouge pour un état normal (Complet, Sans GPS, refus GPS).
- Faire : une action primaire par vue, statut symbole + texte + couleur, tokens partout.

## Vérification

1. Relire le code : aucun littéral de couleur, taille en points, rayon ou espacement hors tokens ; une seule action primaire par vue.
2. Captures simulateur (harnais DEBUG `JourneyVisualReview` / `SchoolVisualReview`, données synthétiques ; pièces jointes des `.xcresult` du workflow `refonte-ios.yml`) en **clair et sombre**, puis en **grande taille d’accessibilité** : rien de tronqué, rangées empilées.
3. Contraste accru, Réduire les animations et Réduire la transparence : commandes identiques et lisibles.
4. Web : 320 px, clavier seul, sombre, `prefers-contrast: more`, `forced-colors`.
5. **Appareil physique** pour VoiceOver, GPS, haptique, batterie et Liquid Glass sur carte réelle : aucun de ces résultats ne se déduit du simulateur.
6. Consigner ce qui a été exécuté dans `docs/implementation/STATUS.md` et `docs/implementation/design-system.md`.
