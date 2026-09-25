---
version: alpha
name: Drivy · Cartographie native
description: Système visuel commun du client Apple (SwiftUI) et du web Drivy, dérivé de la direction A « Cartographie native » et des tokens 3.8. Valeurs du thème clair ; le sombre est dans la section Themes.
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

# Drivy · Cartographie native

Référence d’application pour tout agent ou développeur qui touche une interface Drivy. Source canonique : `Drivy_Conception_v3_17_2026-09-20/DESIGN/` et `annexes/tokens-proposition.json` ; code : `apps/ios/Drivy/UI/DrivyTheme.swift`, `apps/ios/Drivy/UI/DrivyComponents.swift`, `apps/web/client/styles.css`. Les décisions d’implémentation et les vérifications vivent dans `docs/implementation/design-system.md`.

**Statut.** Validé par le porteur : la direction A « Cartographie native » (choix accepté) et la passe d’harmonisation du 25 septembre 2026. Encore proposition : les valeurs exactes des tokens 3.8 (« en attente d’acceptation visuelle »), les durées de mouvement, les largeurs de panneau et points de rupture, le nom « Drivy » en police système et le petit signe de trajet (**pas un logo approuvé**). Un changement de token part du JSON canonique, puis `DrivyTheme.swift` et `styles.css` le suivent.

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
