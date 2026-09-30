---
version: alpha
name: Drivy · Web et Apple
description: Deux directions par surface. Web bureau sobre depuis le 30 septembre 2026 ; Apple Cartographie native conservée. Les tokens structurés de cet en-tête concernent Apple uniquement ; les tokens web figurent dans la section Web.
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

La refonte de direction artistique du 30 septembre 2026 concerne **uniquement le web**, y compris son rendu sur téléphone et tablette. L’identité native iPhone/iPad est conservée. Les ajustements fonctionnels ciblés de l’app (carte, bilan, compétences) ne donnent pas mandat pour changer son thème.

Le dossier `Drivy_Conception_v3_17_2026-09-20` reste une livraison conservée. La première passe est consignée dans [web-direction-20260930.md](docs/implementation/web-direction-20260930.md), puis remplacée par [l’architecture des parcours web](docs/implementation/web-architecture-20260930.md) et [la passe esthétique encre et papier](docs/implementation/web-craft-20260930.md). La référence native détaillée reste ci-dessous et dans [la grille iOS](docs/implementation/DESIGN.md).

## Web · Bureau

Choix utilisateur : « Sobre et précise : listes compactes, carte dominante, peu de cartes décoratives, couleurs discrètes. » Le web organise le travail administratif ; le trajet garde son rôle dans l’app terrain. Une carte n’est pas ajoutée artificiellement à un écran sans données cartographiques.

### Composition

- Cinq espaces stables : Planning, Élèves, Équipe, Formations et tarifs, Réglages. Chaque espace expose deux ou trois destinations locales ; le fil d’Ariane garde la hiérarchie visible. Les compétences, procédures et conditions commerciales s’ouvrent depuis la formation ou le tarif concerné.
- Desktop : rail de 228 px sur fond perle et une seule surface de travail blanche, légèrement bordée. La liste et le dossier utilisent deux colonnes quand elles disposent de leur largeur utile. Le détail a un fond légèrement distinct et un en-tête ; ses actions ferment le panneau après son contenu.
- Sur écran étroit, ouvrir un dossier remplace la liste par le détail et un retour visible. Le retour restaure le focus dans la liste. La sélection et les filtres de navigation autorisés vivent dans l’URL ; les brouillons restent uniquement en mémoire, par personne, école et époque d’accès.
- Jusqu’à 1024 px : le bouton Menu ouvre les mêmes destinations dans le flux. Il remplace le ruban horizontal de toutes les rubriques. Sélectionner une destination ferme le menu ; Échap depuis la navigation restitue le focus au bouton.
- L’école active ouvre sur Planning. La préparation appartient à Réglages et sert d’entrée pour l’école DRAFT. Les coordonnées et capacités ne sont plus répétées dans un tableau de bord quotidien. Le hub Formations regroupe les enseignements, compétences, procédures et tarifs par catégorie, avec liens vers leurs références exactes.
- Les tableaux alignent les données, avec en-tête discret et repère latéral pour la ligne sélectionnée. Les heures, montants et dates utilisent les chiffres tabulaires. L’agenda se lit du jour vers l’horaire puis l’élève ; une leçon est une seule cible. Les catégories enseignées ont une identité typographique commune, reliée aux compétences, procédures et tarifs. Une couleur de surface sert une sélection, un contrôle ou un message.
- Le fil d’Ariane apparaît dans les sous-pages. À la racine d’un espace, la navigation principale, l’onglet courant et le titre suffisent. Les petits contextes qui répétaient le nom de l’espace sont retirés.
- Les formulaires composés adaptent leurs colonnes à leur conteneur. Un champ à l’intérieur d’un dossier ne dépend pas de la largeur totale de l’écran.

### Tokens web

Source d’exécution : `apps/web/client/styles.css`. Les hexadécimaux sont nommés par rôle, sans deuxième système de couleur. Le thème suit `prefers-color-scheme`.

| Rôle | Clair | Sombre |
|---|---|---|
| canvas | `#F2F4F7` | `#141920` |
| surface | `#FFFFFF` | `#1C232D` |
| surface-muted | `#E9EDF3` | `#293341` |
| surface-inset | `#F8F9FC` | `#171E28` |
| surface-detail | `#FAFBFE` | `#202934` |
| text | `#202936` | `#EEF2F8` |
| muted | `#596579` | `#AFBBCD` |
| accent | `#285CC4` | `#9ABEFF` |
| accent-pressed | `#1C479D` | `#B6CFFF` |
| on-accent | `#FFFFFF` | `#132A50` |
| accent-soft | `#EEF3FD` | `#283A55` |
| border | `#DFE4EC` | `#344050` |
| control-border | `#7E899B` | `#8491A5` |

Les couleurs sémantiques succès, alerte et erreur restent dans leurs rôles existants. Le bleu signale les actions, liens et sélections. Une réussite reçoit un texte ou symbole explicite. Les statuts courants restent du texte ; les badges servent les états inhabituels.

Source Sans 3 variable auto-hébergée (fichier officiel Adobe sous OFL, sans requête à un hébergeur de polices), puis police système en repli. Titres principaux 28–30 px/650, titres de détail 22 px/650, sections 18 px/600, lignes 15 px et métadonnées 13–14 px. Les champs passent à 16 px sur petit écran ou pointeur tactile pour éviter le zoom de saisie Safari. Les textes utiles restent sélectionnables.

Rayons web : champ et commande 6 px, détail et surface de travail 12 px, panneau d’entrée 16 px. Les contrôles de gestion gardent au moins 44 px de hauteur. Une seule action primaire par vue ; secondaires blancs avec contour et ombre légère, actions discrètes en texte. L’ombre distingue une commande ou la surface de travail ; les séparations internes restent des traits. Les menus déroulants gardent leur comportement HTML natif. Les couleurs et rayons web ne doivent pas être recopiés dans `DrivyTheme.swift`.

### Accessibilité et états

Liens pour les destinations, boutons pour les actions, labels permanents, `aria-current` pour la rubrique active, `aria-expanded` et `aria-controls` pour le menu. Chaque panneau de détail possède un identifiant de titre unique. L’indicateur de focus de 3 px, le mouvement réduit et les couleurs forcées restent pris en charge. Les badges peuvent se replier sur plusieurs lignes.

Conserver les refus serveur, les erreurs, la saisie et la demande incertaine. Un succès ne s’affiche qu’après la confirmation durable. Un style compact ne cache jamais une action nécessaire, un prix modifié ou un refus d’accès.

Contrastes calculés depuis les tokens : texte sur surface 14,67:1 clair / 14,08:1 sombre ; secondaire 5,90:1 / 8,14:1 ; action primaire 6,14:1 / 7,58:1 ; contour sur fond de champ 3,36:1 / 5,25:1. Les 52 couples vérifiés passent leurs seuils. [Mesures](docs/implementation/proofs/web-craft-contrast-20260930.json). La lecture VoiceOver/NVDA, le zoom navigateur à 200 % et les essais physiques restent à qualifier.

## Apple · Cartographie native conservée

**Portée du reste de ce document : client natif Apple.** Les valeurs structurées de l’en-tête et les anciennes correspondances iOS/web ci-dessous décrivent le système natif conservé et l’harmonisation historique du 25 septembre ; elles ne prescrivent plus le thème web. Source native : dossier de conception et `apps/ios/Drivy/UI/DrivyTheme.swift`. Ne pas modifier les tokens du dossier livré pour implémenter une décision récente.

**Statut natif.** Direction A validée, tokens 3.8 conservés. Durées, dimensions de panneaux et comportement physique restent soumis à qualification. Le petit signe de trajet n’est pas un logo approuvé.

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
| `canvas` | Fond des formulaires/listes groupés ; fond intérieur de `DrivyCard`/`DrivyPanel` sur page blanche. |
| `surface` | Fond des pages de lecture ; cartes web. |
| `surface-muted` | Remplissage neutre : bouton secondaire, pastille neutre, avatar, ligne pressée. |
| `text` / `muted` | Encre principale / métadonnées, aides, chevrons, icônes de ligne. |
| `accent` / `accent-pressed` / `on-accent` | Action primaire, liens, sélection ; état pressé ; texte sur accent. |
| `accent-soft` | Fond de sélection et de pastille d’accent, bouton secondaire pressé. |
| `success`, `warning`, `danger` + `*-surface` | Texte et fond d’un état ; toujours avec symbole et libellé. |
| `border` / `control-border` | Séparateur décoratif doux / contour d’un contrôle interactif (champ, marque de sélection vide). |
| `disabled-text` / `disabled-surface` | Contrôle indisponible. |
| `route` / `route-halo` | Trace mesurée sur la carte et son halo (5 pt + halo 9 pt de référence). |

Les couleurs de fond de carte du prototype (`mapCanvas`, `mapPark`, `mapWater`) sont schématiques : MapKit dessine le vrai fond.

## Themes

Le sombre est composé (ardoise + bleu éclairci), pas une inversion. Valeurs sombres exactes :

| Token | Clair | Sombre |
|---|---|---|
| canvas | #F7F8FA | #10151C |
| surface | #FFFFFF | #19222E |
| surface-muted | #EEF2F7 | #222E3E |
| text | #18212B | #F2F5FA |
| muted | #536174 | #B0BCCC |
| accent | #245BD6 | #91B5FF |
| accent-pressed | #1947AD | #B4CCFF |
| on-accent | #FFFFFF | #10264D |
| accent-soft | #EAF0FE | #233859 |
| success / success-surface | #17633D / #E9F5EE | #98DBB4 / #18372A |
| warning / warning-surface | #7A4D00 / #FFF3D6 | #F2CB83 / #382D19 |
| danger / danger-surface | #B02B37 / #FDECEF | #FFADB4 / #40252D |
| border / control-border | #D9E0E9 / #78869A | #34445A / #71849D |
| disabled-text / disabled-surface | #5D6A7C / #E8EDF3 | #B0BCCC / #222E3E |
| route / route-halo | #245BD6 / #FFFFFF | #91B5FF / #10151C |

Web : mêmes valeurs sous `@media (prefers-color-scheme: dark)`, `theme-color` par apparence ; `prefers-contrast: more` renforce `border` et `control-border`.

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

- **Page de lecture** (`ScrollView`) : fond `DrivyTheme.surface`, contenu dans `.drivyPageContent()` (marge horizontale `l`, largeur de lecture 720 pt centrée sur iPad). Les blocs groupés y sont des `DrivyPanel`/`DrivyCard` sur `canvas`.
- **Formulaire ou liste groupés natifs** (`Form`/`List`) : `.scrollContentBackground(.hidden)` + `.background(DrivyTheme.canvas)` ; sections natives, pas de cartes maison.

**Titres de navigation :** titre large uniquement sur les écrans de premier niveau (onglets Séance, Agenda, Élèves/Mon dossier, École) ; tout écran poussé ou feuille est en titre inline.

**Rythme :** `s` (12) dans un groupe, `l` (24) entre sujets, padding de bloc `m` (16). Marge de page : 24 en compact, 32 en régulier (`DrivySpacing.page`). Aucune valeur magique hors échelle.

**Adaptation :** en taille d’accessibilité, les rangées horizontales basculent en vertical (`AnyLayout` HStack → VStack) au lieu de tronquer ou de réduire une cible. Pas de hauteur fixe tirée d’une maquette à une ligne.

**Web :** colonne principale `min(820px, 100%)`, marges 2 rem puis 1,25 rem sous 600 px ; boutons empilés en mobile ; aucun défilement horizontal à 320 px.

**iPad et carte (proposition) :** panneau de capture de 320 à 400 pt à côté de la carte en largeur régulière, en bas sur téléphone ; points de rupture logiques 600 et 1024.

## Elevation & Depth

- Surfaces de lecture, formulaires, montants et coordonnées : **opaques**. Hiérarchie par surface (`surface` / `canvas`) et filet `border` de 0,5 pt, pas par ombre.
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
| `DrivyNavigationRow` | Ligne qui ouvre un détail (chevron, ≥ 64 pt). | `.school-list li` |
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
