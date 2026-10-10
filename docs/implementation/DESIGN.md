---
version: alpha
name: Drivy iOS · Cartographie native
description: Grille de cohérence visuelle de l’app iOS/iPadOS Drivy (terrain moniteur et élève), tirée de DrivyTheme.swift et des composants partagés. Valeurs du thème clair ; le sombre est dans la section Themes.
colors:
  canvas: "#F7F8FA"
  surface: "#FFFFFF"
  surfaceMuted: "#EEF2F7"
  text: "#18212B"
  muted: "#536174"
  accent: "#245BD6"
  accentPressed: "#1947AD"
  onAccent: "#FFFFFF"
  accentSoft: "#EAF0FE"
  success: "#17633D"
  successSurface: "#E9F5EE"
  warning: "#7A4D00"
  warningSurface: "#FFF3D6"
  danger: "#B02B37"
  dangerSurface: "#FDECEF"
  border: "#D9E0E9"
  controlBorder: "#78869A"
  disabledText: "#5D6A7C"
  disabledSurface: "#E8EDF3"
  route: "#245BD6"
  routeHalo: "#FFFFFF"
typography:
  drivyScreenTitle:
    fontFamily: system-ui
    fontWeight: 700
  drivyTitle:
    fontFamily: system-ui
    fontWeight: 700
  drivySection:
    fontFamily: system-ui
    fontWeight: 600
rounded:
  field: 12px
  content: 16px
  mapPanel: 24px
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
    textColor: "{colors.onAccent}"
    rounded: "{rounded.content}"
    height: 52px
  button-primary-pressed:
    backgroundColor: "{colors.accentPressed}"
    textColor: "{colors.onAccent}"
  button-primary-disabled:
    backgroundColor: "{colors.disabledSurface}"
    textColor: "{colors.disabledText}"
  button-secondary:
    backgroundColor: "{colors.surfaceMuted}"
    textColor: "{colors.accent}"
    rounded: "{rounded.content}"
    height: 52px
  button-secondary-pressed:
    backgroundColor: "{colors.accentSoft}"
  button-danger:
    backgroundColor: "{colors.dangerSurface}"
    textColor: "{colors.danger}"
    rounded: "{rounded.content}"
    height: 52px
  selection-card:
    backgroundColor: "{colors.canvas}"
    rounded: "{rounded.content}"
    padding: "{spacing.m}"
  selection-card-selected:
    backgroundColor: "{colors.accentSoft}"
  grouped-surface:
    backgroundColor: "{colors.canvas}"
    padding: "{spacing.m}"
  inline-message:
    rounded: "{rounded.field}"
    padding: "{spacing.s}"
  error-notice:
    backgroundColor: "{colors.dangerSurface}"
    textColor: "{colors.danger}"
    rounded: "{rounded.content}"
    padding: "{spacing.m}"
  map-panel:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.mapPanel}"
    padding: "{spacing.m}"
---

# Drivy iOS · Cartographie native

Document de référence pour les agents qui revoient un écran de l’app native (`apps/ios/Drivy`). Il complète le `DESIGN.md` racine (commun iOS et web) pour le seul client Apple et intègre les décisions du porteur du 28 septembre 2026 (`decisions-2026-09-28.md`), qui priment sur toute règle contraire. Les noms de tokens sont ceux de Swift (`DrivyTheme.surfaceMuted`, `DrivySpacing.m`, `DrivyRadius.mapPanel`). Chaque constat de revue se juge contre ce document ; la dernière section liste les écarts déjà relevés au 29 septembre 2026.

## Overview

Drivy est l’outil de terrain d’une auto-école : le moniteur prépare, conduit, signale et rédige le bilan d’une leçon ; l’élève retrouve ses leçons, son trajet et sa progression. La direction « Cartographie native », validée par le porteur, fait du trajet le support de l’explication : interface claire, carte fonctionnelle, bleu franc réservé à l’action, contrôles Apple natifs.

Principes qui gouvernent chaque écran :

1. **Terrain, pas bureau.** L’app sert la séance, le trajet, le bilan, l’agenda et les élèves (moniteur), les leçons et la progression (élève). Configuration de l’école, catalogue, tarifs, équipe, disponibilités et champs du profil vivent sur le web. Le moniteur garde dans l’app « Inviter un élève » et « Planifier ». Un écran d’administration qui réapparaît sur iPhone est un écart.
2. **Un trajet part toujours d’un élève**, depuis sa leçon ou en choisissant l’élève. Aucun trajet personnel, aucun laboratoire local, aucune position inventée.
3. **Peu de texte à l’écran.** Un titre sans sous-titre explicatif ; pas de note sous les sections ; un badge seulement pour l’inhabituel ; une explication seulement en cas d’erreur, avec ce qu’il faut faire. Les mots de l’auto-école (terminer, bilan, leçon, tarif), pas ceux du serveur (constat, brouillon, révision, prestation).
4. **Une zone de décision dominante** et une seule action primaire visible à la fois.
5. **Rien n’est annoncé avant d’être écrit.** Succès, compteur, haptique de succès et fermeture suivent l’écriture durable ; un résultat inconnu reste « Demande à vérifier ».
6. **Partage automatique avec l’élève.** Trajet, observations, bilan et objectifs d’une leçon réalisée lui sont visibles sans publication ; seul ce que le moniteur marque « Pour moi » reste privé. Aucun texte ne promet le contraire.
7. **Natif sans imitation.** `TabView`, `NavigationStack`, `NavigationSplitView`, feuilles, `Form`, `confirmationDialog` et barres système sont habillés par les tokens, jamais reconstruits.

## Règles de priorité pour les agents

- Lire `AGENTS.md`, `docs/implementation/decisions-2026-09-28.md`, puis ce document avant de toucher un écran.
- Accessibilité et vie privée de l’élève priment sur l’esthétique : une cible de 44 pt, un libellé VoiceOver, un contraste de 4,5:1 ou une donnée gardée « Pour moi » ne se sacrifient jamais à une composition plus jolie.
- Un rôle, pas une valeur : `DrivyTheme`, `DrivySpacing`, `DrivyRadius`, `DrivyMotion` et les composants `Drivy*` avant tout littéral ou toute vue locale.
- Réutiliser un composant existant avant d’en créer un ; un nouveau motif partagé va dans `UI/DrivyComponents+<Périmètre>.swift`.
- Moins de texte : retirer une phrase explicative plutôt qu’en ajouter une ; une explication n’apparaît qu’en cas d’erreur.
- Ne jamais annoncer un succès, un partage ou une position que le service n’a pas confirmés.
- Un écart constaté hors du lot en cours se signale (section « Écarts constatés ») ; il ne se corrige pas en passant.
- Une règle marquée « à arbitrer par le porteur » ne s’applique pas d’autorité : proposer, ne pas imposer.

### Arbitrage entre sources

Ordre de préséance, du plus fort au plus faible :

1. `AGENTS.md` et `docs/implementation/decisions-2026-09-28.md` (décisions du porteur ; elles remplacent explicitement certaines règles du dossier 3.17).
2. Dossier de conception `Drivy_Conception_v3_17_2026-09-20/` (livraison conservée, non modifiée), en particulier `DESIGN/01-direction-artistique.md` à `06-livraison-validation.md` et la charte `02-experience/qualite-ui-ux-anti-slop.md`.
3. `docs/implementation/design-system.md`, ce `DESIGN.md` et le `DESIGN.md` racine (iOS et web).
4. Le code existant, qui constate un état, pas une intention.

- En cas de tension, l’accessibilité et la vie privée de l’élève l’emportent sur la fidélité visuelle à une maquette ou à un rendu existant.
- Une répétition dans le code ne devient pas une règle : elle reste un constat tant qu’aucune source de rang 1 à 3 ne la porte.
- Entre ce document et le `DESIGN.md` racine, pour l’app iOS, la version conforme aux décisions du 28 septembre prévaut ; la hiérarchie formelle entre les deux fichiers est à arbitrer par le porteur.

## Sources de vérité

| Surface | Fichier qui fait foi | Remarque |
|---|---|---|
| Couleurs, typographie, espacements, rayons, mouvement, boutons primaire et secondaire, panneau | `apps/ios/Drivy/UI/DrivyTheme.swift` | Couleurs codées en Swift (`adaptive`) ; `Assets.xcassets` ne contient que `AppIcon`, aucun jeu de couleurs. |
| Tons, badges, lignes, états, surfaces, messages, sélection | `apps/ios/Drivy/UI/DrivyComponents.swift` | |
| Accueil guidé et champs sur page | `apps/ios/Drivy/UI/DrivyComponents+Accueil.swift` | |
| États de leçon et de bilan, ligne de leçon, corps de bilan, barre d’action basse | `apps/ios/Drivy/UI/DrivyComponents+Agenda.swift` | |
| Barre d’outils des onglets, lignes d’entité, formulaires, demande incertaine | `apps/ios/Drivy/UI/DrivyComponents+Ecole.swift` | |
| Carte, trajet en cours, replay, bouton danger, gabarits de carte | `apps/ios/Drivy/UI/DrivyComponents+Seance.swift` | `DrivyMapLayout` porte les seuils de carte. |
| Tons des appréciations d’observation, tuiles de signalement | `apps/ios/Drivy/UI/DrivyObservationStyle.swift` | Libellés dans `SchoolObservationAPI/SchoolObservationModels.swift` et `Core/CaptureSupport.swift`. |
| Dates et heures des écrans de terrain | `apps/ios/Drivy/SchoolAgendaUI/SchoolDateFormat.swift` | Prix : `SchoolCatalogFormatting.price` (`SchoolCatalogAPI/SchoolCatalogModels.swift`). |
| Textes système (autorisations, langue) | `apps/ios/Drivy/Info.plist` | `CFBundleDevelopmentRegion` et `CFBundleLocalizations` : `fr` seulement. Aucun `Localizable.strings` ni catalogue `.xcstrings` : les textes sont en dur dans les vues. |
| Catalogue visuel | `apps/ios/Drivy/UI/DrivyDesignSystemGallery.swift` | DEBUG et simulateur seulement ; écran de capture `design-system`. |
| Captures de revue | `scripts/ios/capture-screens.sh` (appelé par `.github/workflows/refonte-ios.yml`) | Données fictives ; iPhone/iPad, clair/sombre, portrait/paysage. Ne qualifie ni GPS, ni VoiceOver, ni appareil physique. |
| Projet Xcode | `apps/ios/project.yml` (XcodeGen 2.46) | Le `.xcodeproj` est généré en CI ; aucun `project.pbxproj` n’est versionné. |

### Pour les agents

- Lire un token, jamais écrire un littéral de couleur, de taille de police, d’espacement ou de rayon.
- Un nouveau fichier Swift placé sous `apps/ios/Drivy/` est inclus automatiquement par `project.yml` (`sources: path: Drivy`) : pas d’entrée manuelle dans un `project.pbxproj`. La consigne des « 4 entrées » vient de l’ancien dépôt et ne s’applique pas ici.
- Garder chaque `accessibilityIdentifier` existant : tests UI et script de captures en dépendent.
- Tout nouvel état d’écran utile à la revue s’ajoute comme variante de capture (`SchoolVisualReview`, liste des écrans de `capture-screens.sh`), avec données fictives.
- Ne jamais placer de donnée réelle de personne, de jeton ou de position dans une capture, un log ou un artefact de CI.

## Publics et parcours types

### Publics

- **Moniteur** : au volant ou à côté de l’élève, lecture d’un coup d’œil, une main libre. Onglets Aujourd’hui, Agenda, Élèves, Trajets. Besoins : démarrer la bonne leçon, signaler en deux gestes, garder l’arrêt accessible, terminer et rédiger le bilan. Grandes cibles, temps écoulé en plus grand texte, action dominante en bas.
- **Élève** : consulte après coup, souvent seul. Onglets Leçons et Progression. Voit automatiquement trajet, observations, bilan et objectifs de ses leçons réalisées, jamais ce que le moniteur garde « Pour moi ». Aucun score ni pourcentage.
- **Administration de l’école** : travaille au bureau, sur le web (`apps/web`). Hors de l’app, sauf un administrateur qui enseigne et utilise alors l’app comme moniteur.

### Parcours 1 — Leçon avec trajet (moniteur)

| Étape | Écran | Composants |
|---|---|---|
| 1. Voir la leçon qui compte | `SchoolUI/SchoolTodayView.swift` (onglet Aujourd’hui) | Carte + panneau ; résumé de leçon ; `DrivyPrimaryButtonStyle` « Démarrer » ou « Terminer la leçon » si une leçon passée reste sans résultat ; sans leçon : « Démarrer une leçon » vers `SchoolAgendaUI/SchoolStartNowView.swift` (élève, lieu). |
| 2. Préparer le trajet | `SchoolCaptureUI/SchoolCapturePreparationView.swift` (feuille) | Un seul état visible : progression (`DrivyPanel` + `ProgressView` nommé) ou blocage expliqué avec son action ; « Démarrer le trajet ». |
| 3. Accord GPS si absent | `SchoolCaptureUI/SchoolRecordingChoiceView.swift` | Avec GPS / Sans GPS enregistrent puis ferment ; documents complets sur demande. |
| 4. Trajet en cours | `SchoolCaptureUI/SchoolCaptureLiveView.swift` | `DrivyLiveTopBar` (temps, état GPS, `DrivyMapStopButton`), carte ou `DrivyMapPlaceholder`, `DrivyMapControls`, `DrivyMapDock` avec « Signaler » en action dominante ; panneau latéral en largeur régulière. |
| 5. Signaler | `SchoolCaptureUI/SchoolLiveObservationSheet.swift` (feuille partielle sur iPhone, popover ancré sur iPad) | L’instant est figé à l’ouverture ; grille de thèmes (`DrivyTileButtonStyle`, haptique de sélection) ; puis appréciation explicite (Attention, À retravailler, Point positif) ; écriture chiffrée, haptique de succès, fermeture automatique. |
| 6. Terminer | Même écran, « Terminer la leçon » | Arrêt durable puis synchronisation ; une panne garde « Réessayer » ; ouverture de la leçon en mode fin. |
| 7. Bilan | `SchoolLessonReportUI/SchoolLessonReportView.swift` (feuille `.page`) | Travail réalisé, À retenir, Prochaine étape ; niveaux par compétence (`Picker` menu) ; « Pour moi » / « Visible par l’élève » ; deux colonnes dès 900 pt. |

### Parcours 2 — Rejoindre une école par code (élève ou moniteur invité)

| Étape | Écran | Composants |
|---|---|---|
| 1. Point d’entrée | `SchoolUI/SchoolSignInLanding.swift` ou écran sans école (`SchoolJoinUI/SchoolCodeJoinView.swift`, `SchoolWithoutSchoolView`) | « J’ai un code » en action primaire. |
| 2. Saisir le code | `SchoolCodeJoinView` | Libellé permanent « Code d’invitation », champ `XXXX-XXXX` à chiffres monospaces, `PasteButton` ; « Continuer » (`DrivyBusyLabel`). |
| 3. Relire l’aperçu | `SchoolCodeJoinView` | Nom d’école (`.drivyTitle`), rôles, permis ; « Rejoindre l’école ». |
| 4. Résultat | `SchoolCodeJoinView` | Confirmé : « Ouvrir mon école » ; incertain : « Vérifier auprès de l’école ». |
| 5. Accueil guidé | `SchoolProfileUI/SchoolOnboardingView.swift` | `DrivyStepProgress`, informations, formation, choix GPS, relecture, prêt. Écran encore trop bavard (voir Écarts). |

### Parcours 3 — Consulter sa progression (élève)

| Étape | Écran | Composants |
|---|---|---|
| 1. Onglet Leçons | `SchoolHomeView.learnerTab(.lessons)` → `SchoolTrainingScreen` | `DrivyLessonRow` ; filtre par permis en tête de page si plusieurs formations (aucun avec une, segmenté avec deux, menu au-delà), « Tous » par défaut. |
| 2. Ouvrir une leçon réalisée | Leçon en lecture | Trajet, observations visibles par l’élève, `DrivyReportBody` (« Prochaine étape » en tête). |
| 3. Onglet Progression | `SchoolTrainingScreen` section `.progress` | Liste de `DrivyCompetencyNote` : compétence, niveau en badge, contexte, date ; « Pas encore vu » en neutre ; jamais de score global. |

## Colors

Toujours consommer une couleur par son rôle `DrivyTheme.*`. Interdit dans une vue : `Color` littérale, `.gray`, `.secondary`, `.primary`, `Color(.systemBackground)`, hexadécimal. Les tons d’état passent par `DrivyTone` (`neutral`, `accent`, `success`, `warning`, `danger`), qui fournit `foreground` et `background`.

| Token Swift | Rôle |
|---|---|
| `canvas` | Fond des `Form` et `List` groupés ; intérieur de `DrivyPanel` et `DrivyCard` ; fond d’un écran de remplacement de carte. |
| `surface` | Fond d’une page de lecture (`ScrollView`) ; panneaux posés sur la carte ; barre d’action basse ; lignes de `List` non sélectionnées. |
| `surfaceMuted` | Remplissage neutre : bouton secondaire, avatar, cercle de symbole, ligne pressée, bouton rond de carte. |
| `text` / `muted` | Encre principale / métadonnées, chevrons, icônes de ligne. |
| `accent` / `accentPressed` / `onAccent` | Action primaire, lien, sélection, trace ; état pressé ; texte sur accent. Jamais pour des titres ou des icônes décoratives. |
| `accentSoft` | Fond de sélection (ligne, carte, avatar), bloc « Prochaine étape », bouton secondaire pressé. |
| `success`, `warning`, `danger` et leurs `*Surface` | Texte et fond d’un état, toujours avec symbole et libellé. |
| `border` / `controlBorder` | Filet décoratif de 0,5 pt / contour d’un contrôle interactif (champ, marque de sélection vide) et filet en Contraste accru. |
| `disabledText` / `disabledSurface` | Contrôle indisponible ; jamais une simple opacité. |
| `route` / `routeHalo` | Trace mesurée sur la carte et son halo. |

Règles de ton :

- Refus ou interruption GPS, leçon « À terminer » : `warning`, jamais `danger`. Une leçon annulée ou manquée est un fait clos : encre `muted`, sans couleur d’alerte.
- Observation : « Attention » en `warning`, « À retravailler » en `danger`, « Point positif » en `success` (`ObservationStatus.tone`), avec les symboles `exclamationmark`, `xmark`, `checkmark`.
- Leçon et bilan : `DrivyLessonState` et `DrivyReportState` fixent titre, symbole et ton ; une vue ne les redéfinit pas. Une leçon planifiée n’a pas de badge en ligne (`rowBadge`).
- `.tint(DrivyTheme.accent)` sur chaque racine de navigation et de feuille, pour que les contrôles système prennent l’accent.

## Themes

Le sombre est composé (ardoise et bleu éclairci) par `DrivyTheme.adaptive(clair, sombre)` ; aucune vue ne teste `colorScheme` pour choisir une couleur.

| Token Swift | Clair | Sombre |
|---|---|---|
| canvas | #F7F8FA | #10151C |
| surface | #FFFFFF | #19222E |
| surfaceMuted | #EEF2F7 | #222E3E |
| text | #18212B | #F2F5FA |
| muted | #536174 | #B0BCCC |
| accent | #245BD6 | #91B5FF |
| accentPressed | #1947AD | #B4CCFF |
| onAccent | #FFFFFF | #10264D |
| accentSoft | #EAF0FE | #233859 |
| success / successSurface | #17633D / #E9F5EE | #98DBB4 / #18372A |
| warning / warningSurface | #7A4D00 / #FFF3D6 | #F2CB83 / #382D19 |
| danger / dangerSurface | #B02B37 / #FDECEF | #FFADB4 / #40252D |
| border / controlBorder | #D9E0E9 / #78869A | #34445A / #71849D |
| disabledText / disabledSurface | #5D6A7C / #E8EDF3 | #B0BCCC / #222E3E |
| route / routeHalo | #245BD6 / #FFFFFF | #91B5FF / #10151C |

En Contraste accru (`colorSchemeContrast == .increased`), surfaces groupées, cartes de sélection, boutons secondaires et champs guidés passent de `border` à `controlBorder` en 1 pt. Tout nouveau conteneur à filet suit la même bascule.

## Typography

Police système uniquement, styles Dynamic Type uniquement. Aucune taille en points (`.font(.system(size:))`) sauf un glyphe dont la taille suit une `@ScaledMetric` (code d’invitation, emblème d’observation) ; ce cas reste exceptionnel et se déclare dans un composant.

| Rôle | Swift | Usage |
|---|---|---|
| Titre d’écran | `.drivyScreenTitle` (largeTitle, gras) | Nom ou date en tête d’un contenu de page. Un seul par vue. |
| Titre | `.drivyTitle` (title2, gras) | Tête d’une feuille, d’une carte dominante, d’un écran de remplacement (`DrivyMapPlaceholder`). |
| Section | `.drivySection` (title3, semi-gras), via `DrivySectionHeader` | Titre de section d’une page de lecture, avec trait d’en-tête. |
| Titre de ligne | `.headline` | Première ligne d’une rangée, titre d’un bloc dans un panneau. |
| Corps | `.body` | Lecture, valeurs, champs. |
| Méta | `.subheadline` | Détail, lieu, horaire secondaire, action texte (`.subheadline.weight(.semibold)`). |
| Aide et état | `.footnote`, `.caption` | Note d’action (`DrivyActionNote`), pastille (`.caption.weight(.semibold)`), heure de fin. |

- Graisses autorisées : regular, medium, semibold, bold. Pas de `.heavy` ni `.black`.
- Heures, durées, compteurs, montants : `.monospacedDigit()` (`DrivyTimeColumn`, `DrivyKeyValueRow(numeric: true)`).
- Titres de navigation : `.large` seulement sur les racines d’onglet à liste (Agenda, Élèves, Trajets, Leçons, Progression) ; `.inline` pour Aujourd’hui (écran carte), tout écran poussé et toute feuille.
- Tout texte multiligne porte `.fixedSize(horizontal: false, vertical: true)` ; aucune troncature à la taille courante, aucun `lineLimit` sans relâchement aux tailles d’accessibilité.
- Le nom de l’élève en tête d’une feuille de leçon est un seul rôle typographique ; deux styles coexistent aujourd’hui (voir Écarts), le choix est à arbitrer une fois pour toutes.

## Layout

### Deux types de page, jamais mélangés

- **Page de lecture** : `ScrollView` sur `DrivyTheme.surface`, contenu dans `.drivyPageContent()` (marge `DrivySpacing.page` : 24 pt en compact, 32 pt en régulier ; colonne de 720 pt centrée). Les blocs y sont des `DrivyPanel`.
- **Formulaire ou liste native** : `Form` ou `List` avec `.scrollContentBackground(.hidden)` et `.background(DrivyTheme.canvas)` ; sections natives, pas de cartes maison. Colonne bornée sur iPad (valeur observée : 820 pt, à nommer).
- **Écran carte** : carte plein cadre, panneaux opaques en `safeAreaInset` (jamais de hauteur de panneau codée en dur ni d’`ignoresSafeArea` qui contourne ces insets), commandes flottantes en Liquid Glass.

### Rythme

`DrivySpacing` uniquement : `xxs` 4 · `xs` 8 · `s` 12 · `m` 16 · `l` 24 · `xl` 32 · `xxl` 48. `s` entre éléments d’un groupe, `l` entre sujets, `m` de padding de bloc. Aucune valeur numérique d’espacement dans une vue.

### iPhone et iPad, portrait et paysage

La composition dépend de la largeur réellement accordée (`GeometryReader`, `horizontalSizeClass`), jamais du nom de l’appareil. Fenêtre étroite ou taille d’accessibilité : flux vertical unique.

| Surface | Compact / étroit | Large |
|---|---|---|
| Écrans carte (trajet, replay) | Panneau en bas | Panneau latéral dès `DrivyMapLayout.sidebarBreakpoint` (760 pt), largeur `sidebarWidth` (380 pt) |
| Aujourd’hui | Carte + panneau bas (hauteur au plus 66 %) | Panneau latéral de 380 pt dès 960 pt |
| Agenda | Flux unique, 800 pt max | Semaine et filtre en colonne de 388 pt dès 1000 pt, liste du jour à côté |
| Élèves, Invitations | Pile de navigation | `NavigationSplitView`, liste plafonnée (360 / 380 pt), détail dans la largeur restante |
| Leçon réalisée avec bilan | Formulaire unique | Contexte et trajet en 380 pt, bilan à côté dès 900 pt ; feuille en `.page` |
| Formulaires courts, code créé | Pleine largeur | Colonne bornée, centrée |

- Aux tailles d’accessibilité, les rangées horizontales basculent en vertical par `AnyLayout` (HStack vers VStack), les pictogrammes de tête de ligne disparaissent, le nom d’école de la barre devient un symbole. On empile, on ne réduit pas.
- La semaine de l’agenda garde ses sept jours tant que chaque cible fait 44 pt ; sinon le sélecteur de date natif prend le relais.
- Seuils et largeurs de colonne se déclarent comme constantes nommées (modèle : `DrivyMapLayout`) ; un littéral répété dans deux écrans est un écart.

### Barre d’outils des onglets

`DrivySchoolToolbarItem` à gauche (école, ouvre le choix d’école), `DrivyAccountToolbarItem` en dernier à droite (initiales). Onglets moniteur : Aujourd’hui (`map`), Agenda (`calendar`), Élèves (`person.2`), Trajets. Onglets élève : Leçons (`calendar`), Progression (`chart.line.uptrend.xyaxis`).

## Elevation & Depth

- Surfaces de lecture, formulaires, valeurs et coordonnées : opaques. La hiérarchie vient du couple `surface` / `canvas` et du filet `border` de 0,5 pt (`DrivyGroupedSurface`), pas d’une ombre.
- Ombre douce à deux couches (`drivyShadow`, teinte `DrivyTheme.shadow`, jamais de noir en dur) uniquement pour une superposition sur la carte, et seulement via `.drivyMapPanel()` (panneau flottant ; hors carte, le filet remplace l’ombre) ou les repères du replay. Aucune ombre sur une carte de page, une ligne ou un bouton.
- Liquid Glass uniquement pour les commandes flottant sur la carte : `.drivyLegibleMapControl(in:)` (teinte `surface`), regroupées dans `GlassEffectContainer` (`DrivyMapControls`). Jamais de vitre sur un formulaire, un texte long ou un thème global.
- Aucun dégradé : aplat de marque, profondeur par filet ou ombre de superposition.

## Shapes

- `DrivyRadius.field` (12) : champs, messages en ligne, bouton Réessayer, ligne pressée, pastille à deux lignes.
- `DrivyRadius.content` (16) : boutons, cartes de sélection, notice d’erreur, bloc « Prochaine étape ».
- `DrivyRadius.mapPanel` (24) : panneaux et dock posés sur la carte.
- Toujours `RoundedRectangle(cornerRadius:style: .continuous)`. Rayons concentriques : `DrivyPanel` et `DrivyCard` valent `content` + padding.
- Pastille : `Capsule` ; cercles pour avatars (44 pt, 32 dans la barre), symboles de ligne (44 pt) et boutons ronds de carte (48 pt).
- Les contrôles système gardent leur géométrie.

### Icônes

SF Symbols uniquement, sans asset distant. Un symbole accompagne un texte ; seul, il porte un `accessibilityLabel`, sinon `accessibilityHidden(true)`. Couleur `muted` pour un symbole de ligne, `accent` seulement quand le symbole est l’action ou la sélection. Symboles stables : chevron `chevron.right` (ouvrir), `checkmark.circle.fill` / `circle` (sélection), `arrow.clockwise` (réessayer), `exclamationmark.triangle.fill` (erreur, alerte), `clock.arrow.circlepath` (demande à vérifier), `lock.fill` (privé), `stop.fill` (arrêter), `location.fill` / `location.slash` (GPS actif / absent), `mappin` (lieu).

## Components

Réutiliser avant de créer. Un motif partagé manquant se crée dans `apps/ios/Drivy/UI/DrivyComponents+<Périmètre>.swift`, préfixé `Drivy`, jamais dans le fichier d’un écran. Chevron = ouvrir ; coche = inclure ; aucun accessoire = lire.

### Boutons

| Besoin | Composant | Règle |
|---|---|---|
| Action dominante | `DrivyPrimaryButtonStyle` | Une seule visible à la fois ; pleine largeur, 52 pt, appui 0,96. |
| Action alternative | `DrivySecondaryButtonStyle` | À côté ou sous la primaire ; aussi « Vérifier auprès de l’école ». |
| Action destructive pleine largeur (révoquer, retirer) | `DrivyDangerButtonStyle` (alias `DrivyDestructiveButtonStyle`) + `role: .destructive` | Toujours précédée d’une confirmation. |
| Destructive en fin de groupe de lignes | `DrivyDestructiveRow` | « Se déconnecter ». |
| Arrêt d’un trajet | `DrivyMapStopButton` | Capsule 52 pt, `danger`, confirmée par l’appelant, loin de Signaler. |
| Reprise après erreur | `DrivyRetryButton` (dans `SchoolErrorNotice`) | Libellé « Réessayer », contour `danger`, 44 pt. |
| Action texte de section ou d’état vide | `DrivySectionHeader(actionTitle:)`, `DrivyEmptyState(actionTitle:)` | `.subheadline` semi-gras, `accent`, cadre 44 pt. |
| Écriture en cours | `DrivyBusyLabel` | Spinner + verbe au présent progressif (« Enregistrement… »). |
| Grandes tuiles du signalement | `DrivyTileButtonStyle` | Appui 0,96 ; haptique de sélection. |
| Fermer / Annuler une feuille | Bouton de barre système (`.cancellationAction` / `.confirmationAction`) | Pas de `.bordered` maison. |

Les styles système `.borderedProminent`, `.bordered` et `.controlSize` ne remplacent pas ces styles.

### Lignes et listes

- Listes sans `List` sur une page de lecture : `DrivyRowGroup(title:)` (filets `border` entre lignes, pas de carte par ligne), avec `DrivyNavigationRow` (ouvre un détail, 64 pt, chevron), `DrivyEntityRow` (personne ou enregistrement : avatar ou symbole, titre, méta, badge, 56 pt), `DrivyLessonRow` (heure, élève, méta, badge d’état), `DrivyContactRow` et `DrivyKeyValueRow` (lecture seule, valeur sélectionnable ou alignée à droite).
- `List` seulement pour une sélection maître/détail (`NavigationSplitView`) ou une liste paginée native ; sélection en `listRowBackground(accentSoft)`, séparateurs `border`.
- Retour d’appui d’une ligne : `DrivyRowButtonStyle`.
- Aucune commande accessible uniquement par balayage. Le dépôt n’a pas de `drivySwipeActions` ni de `.contextMenu` : une action secondaire de ligne vit dans le détail ou dans un menu visible.

### Surfaces

- `DrivyPanel` : bloc groupé sur page blanche (canvas + filet, rayon concentrique).
- `DrivyCard` : bloc de la décision dominante (même anatomie). Un panneau posé sur la carte utilise `DrivyMapDock` / `.drivyMapPanel()`, pas une reconstruction locale.
- `DrivySelectionCardStyle(isSelected:)` + `DrivySelectionMark` : unique motif de sélection (fond `accentSoft`, contour `accent` 1,5 pt, coche), 72 pt minimum, trait `isSelected`.

### En-têtes

- `DrivySectionHeader` pour toute section de page de lecture (trait `.isHeader`, action facultative qui passe dessous en grand texte).
- En `Form`, en-tête de `Section` natif stylé par `.drivyFormSectionHeader()` ; pas de `footer` explicatif.
- `DrivyStepProgress` seulement pour l’accueil guidé.

### États

| État | Composant | Règle |
|---|---|---|
| Chargement dans une section | `DrivyLoadingState(title:)` | Le texte nomme l’opération ; un `ProgressView()` seul n’est jamais acceptable. |
| Chargement plein écran | `ProgressView("…")` centré sur `canvas` | Même texte nommé. |
| Vide dans une section | `DrivyEmptyState` | Titre, une action si elle existe ; pas de paragraphe. Titre seul (liste vide) : glyphe `largeTitle` centré dans l’espace disponible (168 pt au moins), sans texte ajouté ; en tailles d’accessibilité, disposition empilée habituelle. |
| Écran entier vide ou accès perdu | `ContentUnavailableView` | Titre, courte description de la marche à suivre, action. |
| Erreur | `SchoolErrorNotice(message:retry:)` | Fond `dangerSurface`, symbole aligné sur la première ligne du message (pas au centre du bloc), message qui dit quoi faire, `DrivyRetryButton`. Saisie conservée. |
| Succès ou alerte hors `Form` | `DrivyInlineMessage(text:tone:)` | Près de l’action, après écriture durable. |
| Succès ou alerte dans un `Form` | `DrivyFormMessage` | Même vocabulaire. |
| Action désactivée ou échec près du bouton bas | `DrivyStickyActionBar` / `DrivyFormActionBar` + `DrivyActionNote` | Une ligne qui dit pourquoi, au-dessus de l’action. Sur une page courte centrée (connexion `SchoolSignInLanding`, verrou `AppLock`), la barre suit la colonne du contenu : `maxWidth: DrivyLayout.narrowColumn`. |
| Résultat inconnu | `DrivyPendingRequest` | « Demande à vérifier » → « Vérifier auprès de l’école » → « Renvoyer la même demande » → référence repliée. |
| Carte sans position | `DrivyMapPlaceholder` | Jamais une carte vide, jamais une vue de pays. Aujourd’hui : sans autorisation de localisation, le placeholder remplace la carte ; la caméra se replie sur `.automatic`, plus sur une région de pays. Le point de rendez-vous d’une leçon est un texte, pas une coordonnée : aucune région n’en est déduite. |
| Statut | `DrivyStatusBadge(title:symbol:tone:)` | Seulement pour l’inhabituel ; symbole + texte + couleur. Jamais pour l’état d’une leçon ou d’un trajet dans une ligne : voir `DrivyRowNote`. |

### Composants partagés de la passe du 29–30/09/2026

| Composant | Rôle |
|---|---|
| `DrivyLayout` | Largeurs communes : `readingColumn` 720, `formColumn` 820, `narrowColumn` 600, `compactColumn` 560, `splitListMin/Ideal/MaxWidth` 280/320/360. Aucun littéral local équivalent. |
| `DrivyPress.scale` | Échelle d’appui unique, 0,96, pour bouton, tuile et carte de sélection ; supprimée sous Réduire les animations. |
| `DrivyButtonSize` | `.regular` (corps semi-gras, 52 pt) et `.field` (title3 gras, 64 pt), variante terrain pour `DrivyPrimaryButtonStyle(size:)` et `DrivySecondaryButtonStyle(size:)`. |
| `drivyFormRows(isSelected:)` | Fond des lignes de Form et de List (surface) ; remplace les `listRowBackground(DrivyTheme.surface)` locaux. Les fonds spéciaux (danger, clair) restent. |
| `DrivyPrivacyMark(isPrivate:)` | Cadenas privé/partagé, teinte `muted` : le privé n’est jamais alarmant. |
| `drivyFormSectionHeader()` | En-tête de `Section` de Form et de List : subheadline semi-gras, `muted`, casse d’écriture (`textCase(nil)`). Appliqué à tous les en-têtes natifs ; les `Section("Titre")` deviennent `Section { } header: { Text(...).drivyFormSectionHeader() }`. |
| `DrivyLessonRow` | L’état inhabituel est un mot de texte semi-gras en tête de la ligne de détail (`state:` pour une leçon, `note:` sinon, `DrivyRowNote`), sans pastille : « À terminer » en encre `warning`, « Annulée » et « Absence » en `muted` avec heure et titre en retrait, heures barrées pour l’annulation. Planifiée, en cours, terminée : aucun libellé. Le séparateur de List démarre sur la colonne du texte (`listRowSeparatorLeading`). |
| `DrivyReplayTransport` | Une seule rangée dans une colonne de 380 pt : boutons de 48 pt (lecture 60 pt), espacement 4 pt, 276 pt au total ; repli sur deux rangées seulement en dessous. |
| `DrivyMapPlaceholder(isSearching:)` | Emplacement GPS sans position inventée ; pulsation pendant la recherche, fixe sous Réduire les animations. |
| `DrivyElevation` et `drivyShadow` | Ombre douce à deux couches issue de `DrivyTheme.shadow`. |

Décisions du porteur du 29/09/2026, reportées ici : tutoiement ; « Quitter sans enregistrer » ; « Pas encore vu » ; appui 0,96 ; en pause du trajet, « Reprendre » domine et « Signaler » est secondaire ; le privé reste en teinte `muted` ; vocabulaire « Pour moi » (privé au moniteur), « Visible par l’élève », « Bilan précédent ». Ce DESIGN.md fait foi pour l’iOS.

### Carte

`DrivyLiveTopBar` (temps écoulé en plus grand, état GPS, arrêt), `DrivyMapHeader` (replay), `DrivyMapDock` (action dominante en dernier), `DrivyMapControls`, `DrivyReplayScrubber`, `DrivyReplayTransport` (cibles de 48 pt, visibles même désactivées), `DrivyMapStatus` pour le vocabulaire GPS.

## États d’interaction

Un contrôle réagit sans changer d’identité : même taille de libellé, même forme, même place.

| État | Règle | Source |
|---|---|---|
| Appui | Échelle 0,96 animée par `DrivyMotion.press` (ressort 0,18 s, sans rebond) pour les boutons primaire, secondaire, danger, les tuiles et l’arrêt ; la couleur passe à `accentPressed` (primaire) ou `accentSoft` (secondaire). Une ligne ne se déforme pas : un fond `surfaceMuted` apparaît derrière elle (`DrivyRowButtonStyle`). Aucune opacité globale sur un bouton : elle a déjà fait passer `danger` sous 4,5:1. | `DrivyTheme.swift:100`, `:133` ; `DrivyComponents+Seance.swift:398` ; `DrivyObservationStyle.swift:32` ; `DrivyComponents.swift:218` |
| Appui d’une carte de sélection | Aujourd’hui 0,98 (`DrivyComponents.swift:455`). Proposition : 0,96 comme les autres, à arbitrer par le porteur. | Revue des composants du 29 septembre (point LOW ouvert) |
| Désactivé | `disabledSurface` + `disabledText` ; le bouton garde sa forme visible (y compris les commandes de lecture de 48 pt). La raison s’écrit juste au-dessus avec `DrivyActionNote` ou `DrivyFormActionBar(hint:)`. | `DrivyTheme.swift`, `DrivyComponents+Agenda.swift:275` |
| En cours | Libellé remplacé par `DrivyBusyLabel` (spinner + verbe : « Enregistrement… », « Création… », « Vérification… ») ; champs gelés ; fermeture interactive bloquée (`interactiveDismissDisabled(model.isBusy)`) ; bouton « Fermer » désactivé. Un chargement de contenu utilise `DrivyLoadingState(title:)`. | `DrivyComponents+Ecole.swift:306`, écrans d’invitation, d’observation, de profil |
| Sélectionné | Fond `accentSoft`, contour `accent` 1,5 pt, `DrivySelectionMark` (coche pleine / cercle `controlBorder`), trait `.isSelected`. En `List`, `listRowBackground(accentSoft)` et titre qui reste en `text` (`DrivyEntityRow(isSelected:)` : le fond `accentSoft` et l’avatar portent la sélection, contraste 12:1 au lieu de 5,4:1). Suivi de position sur la carte : symbole plein en `accent` et trait `.isSelected`. | `DrivyComponents.swift:438-471`, `DrivyComponents+Seance.swift:309` |
| Focus VoiceOver | Après le choix d’un thème de signalement, le focus va au titre du thème (`@AccessibilityFocusState`). Aucun anneau de focus personnalisé : le focus clavier iPad est celui du système et reste à vérifier sur appareil. | `SchoolLiveObservationSheet.swift:14`, `:171` |
| Retour haptique | `.sensoryFeedback(.selection)` au choix d’un thème ; `.success` seulement après l’écriture chiffrée de l’observation ; `.success` à la copie d’un code d’invitation. Aucun autre retour haptique n’est établi. | `SchoolLiveObservationSheet.swift:50-51`, `SchoolInvitationsView.swift:436` |
| Réduire les animations | `DrivyMotion.*` renvoie `nil` : plus d’échelle d’appui ni d’animation de contexte ; le panneau de signalement se ferme après 120 ms au lieu de 280 ms. L’état change quand même, immédiatement. | `DrivyTheme.swift:72-78`, `SchoolLiveObservationSheet.swift:56` |
| Contraste accru | Filets `border` remplacés par `controlBorder` en 1 pt ; bouton secondaire entouré d’un contour. | `DrivyGroupedSurface`, `DrivySecondaryButtonStyle` |

## Accessibilité

- **Cibles** : 44 × 44 pt minimum pour toute commande ; 48 pt pour les commandes de carte et de lecture ; 52 pt pour les boutons pleine largeur et l’arrêt. Une icône de 36 ou 40 pt reste dans un cadre tactile de 44 pt.
- **Dynamic Type** : styles système partout ; aux tailles d’accessibilité, empiler (`AnyLayout`), retirer les pictogrammes de tête, laisser les badges passer sur deux lignes. `.dynamicTypeSize(...)` borné seulement pour un avatar de barre ou un repère de carte.
- **VoiceOver** : icône seule = `accessibilityLabel` ; icône décorative = `accessibilityHidden(true)` ; rangée = un élément (`.combine`) ; libellé/valeur = `accessibilityLabel` + `accessibilityValue` ; titres de section avec `.isHeader` ; sélection avec `.isSelected` ; chronologie du replay = un élément ajustable. Les erreurs d’un champ sont un élément lisible, pas seulement un indice.
- Ne jamais renommer un `accessibilityIdentifier` existant (tests UI).
- **Contraste** : paires de tokens calculées au 29 septembre (`proofs/ui-shared-contrast-20260929.json`) : texte 4,5:1, contrôle graphique 3:1. Pas d’opacité appliquée à un texte ou à un bouton entier (elle a déjà fait passer `danger` sous 4,5:1). Contraste réel sur Liquid Glass : non vérifié.
- Couleur jamais seule : un état porte toujours son mot ; un badge ajoute symbole et couleur, une ligne de leçon se contente du mot et de son encre.
- Aucun résultat VoiceOver, GPS ou haptique ne se déduit du simulateur ; il se qualifie sur appareil et se consigne dans `STATUS.md`.

## Mouvement

| Token | Valeur | Usage |
|---|---|---|
| `DrivyMotion.press` | ressort 0,18 s sans rebond | Retour d’appui (échelle 0,96), interrompable. |
| `DrivyMotion.feedback` | ease-out 0,12 s | Changement d’état provoqué par le système (sélection, succès). |
| `DrivyMotion.context` | snappy 0,18 s | Changement de contexte d’un panneau. |

- Toutes ces fonctions renvoient `nil` sous Réduire les animations ; toute animation maison passe par elles. Les transitions système ne sont pas surchargées.
- Aucune animation ne précède ni ne remplace le résultat du service ; aucune ne bloque une commande de capture.
- Haptique de sélection au choix d’un thème de signalement ; haptique de succès seulement après l’écriture locale durable.

## Rédaction

- Français, phrases courtes ; identifiants de code en anglais. Heures en 24 h, dates explicites avec capitale initiale seule (`capitalizedFirst`), montants en CHF.
- Tutoiement pour le moniteur comme pour l’élève (décision du 29/09/2026), verbes à l’infinitif sur les boutons. Les messages d’erreur des clients `School*API`, `IdentityVault` et des workspaces sont au tutoiement (« Vérifie ta connexion et réessaie. »).
- Boutons : un verbe précis et son objet (« Terminer la leçon », « Planifier une leçon », « Inviter un élève », « Démarrer le trajet », « Créer le code »). « Fermer » pour quitter une feuille sans effet ; « Annuler » dans une feuille qui a une saisie ; « Réessayer » pour reprendre une lecture échouée ; « Renvoyer la même demande » pour un résultat inconnu. Pas de « OK » ni « Valider » quand un verbe précis existe ; « Terminé » reste réservé au bouton de confirmation de la barre système.
- Abandon d’une saisie : « Quitter sans enregistrer », seul libellé (décision du 29/09/2026). Renvoi d’une demande incertaine : « Renvoyer la même demande ».
- Chargement : nom de l’opération au présent progressif avec points de suspension (« Chargement de l’agenda… »).
- Erreur : ce qui s’est passé, puis ce qu’il faut faire ; saisie conservée ; jamais d’erreur réseau présentée comme une liste vide.
- Vocabulaire stable : leçon, trajet, observation, bilan, Prochaine étape, Travail réalisé, À retenir, Signaler, Pour moi / Visible par l’élève, GPS actif / en pause / arrêté, Sans GPS, Demande à vérifier, Moniteur, Élève, Administration, Permis B.
- Pas de slogan, de félicitations, de faux encouragement, de score ou de progression inventés.

## Libellés et vocabulaire

**Mots de l’auto-école, à employer tels quels**

| Terme | Emploi | Source |
|---|---|---|
| leçon | Rendez-vous de formation ; états « Planifiée », « En cours », « À terminer », « Terminée », « Annulée », « Absence », « À vérifier ». | `DrivyLessonState` |
| trajet | Tracé GPS d’une leçon ; « Démarrer le trajet », « Trajet en cours », « Trajet partiel ». | écrans de capture |
| Signaler | Ajouter une observation pendant le trajet ; titre du panneau et bouton du dock. | `SchoolCaptureLiveView`, `SchoolLiveObservationSheet` |
| observation | Moment noté par le moniteur : un thème puis une appréciation. | `SchoolObservationModels` |
| Attention · À retravailler · Point positif | Les trois appréciations exactes d’une observation, avec `exclamationmark` / `xmark` / `checkmark`. | `SchoolObservationStatus.label`, `ObservationStatus.label` |
| Thèmes de signalement | Priorité à droite, Signalisation, Céder le passage, Vitesse, Stationnement, Observation, Anticipation, Giratoire : noms dérivés du référentiel de l’école, jamais inventés. | `SchoolCaptureLiveObservations.swift:10-30` |
| bilan | Travail réalisé, À retenir, Prochaine étape. | `DrivyReportBody` |
| Niveaux d’une compétence | En découverte, Avec accompagnement, En autonomie ; absence : « Pas encore vu » partout (décision du 29/09/2026, remplace « Non observé »). | `SchoolReportObservation.levelLabel`, `SchoolLessonReportView.swift:607`, `SchoolTrainingView.swift:221` |
| Pour moi · Visible par l’élève | Visibilité d’un élément de leçon. | `SchoolLessonReportView.swift:513` |
| élève · moniteur · Administration | Rôles affichés. | `SchoolPresentation.roles` |
| Permis B | Formation, écrite « Permis » + catégorie. | `SchoolHomeView` |
| GPS actif · En attente de position · GPS interrompu · GPS non autorisé · Sans GPS | État réel de la position. | `GPSStatus.label` |
| Demande à vérifier | Résultat inconnu d’un envoi. | `DrivyPendingRequest` |

**Vocabulaire serveur interdit à l’écran** (décision du 28 septembre) : brouillon, brouillon privé, version historique, révision, constat, prestation, publication, et tout code d’API (`PLANNED`, `TO_REWORK`, `LIVE`, `MARKER`). Formulations relevées à remplacer : « Brouillon privé », « Version historique », « Observation privée enregistrée. » (voir Écarts). Tant que le porteur n’a pas choisi leurs remplaçants, ne pas en introduire de nouvelles.

**Verbes des boutons** : infinitif, verbe + objet quand l’objet n’est pas évident (« Terminer la leçon », « Démarrer le trajet », « Planifier une leçon », « Inviter un élève », « Créer le code », « Rejoindre l’école », « Ouvrir mon école », « Signaler »). Première lettre seule en majuscule.

**Un seul libellé par action**

| Action | Libellé | Statut |
|---|---|---|
| Relancer une lecture ou un envoi échoué | « Réessayer » | Établi (`DrivyRetryButton`) ; « Réessayer l’envoi » ou « Réessayer la sauvegarde » quand deux reprises coexistent. |
| Résultat inconnu | « Vérifier auprès de l’école », puis « Renvoyer la même demande » | Établi (`DrivyPendingRequest`). |
| Fermer une feuille sans saisie | « Fermer » (barre, `.cancellationAction`) | Établi (25 emplois). |
| Quitter une feuille avec saisie | « Annuler » dans la barre | Établi dans les formulaires. |
| Confirmer l’abandon d’une saisie | « Quitter sans enregistrer » | Décidé le 29/09/2026 : seul libellé d’abandon de saisie. |
| Confirmer une suppression | Verbe exact de l’effet (« Révoquer », « Retirer », « Annuler la leçon »), rôle destructif | Établi. |

Registre (décidé le 29/09/2026) : tutoiement partout où l’app s’adresse à l’utilisateur, élève ou moniteur (« Saisis le code reçu de ton moniteur. »). Cela vaut pour les textes d’autorisation de `Info.plist`, la boîte de dialogue Face ID de `DrivyApp.swift` et le message d’invitation web (« Ton code pour rejoindre… »). Les espaces avant la ponctuation ne sont pas touchés.

## Localisation française

- **Langue** : `fr` seule langue déclarée (`Info.plist`), environnement `Locale(identifier: "fr_CH")` à la racine (`DrivyApp.swift:34`) et dans chaque formateur. Pas de catalogue de chaînes : textes en dur, en français.
- **Apostrophe** : typographique ’ partout dans le code Swift (plus de 400 occurrences, aucune apostrophe droite dans les textes d’écran). Exception relevée : `Info.plist` (voir Écarts).
- **Guillemets** : « » avec espace intérieure, pour citer un libellé d’interface.
- **Espaces avant ? ! : ;** : le code met une espace ordinaire (« Annuler cette leçon ? », « Quantité : 2 ») ; aucune espace insécable ni fine insécable n’existe dans les sources. Le risque est un retour à la ligne avant le signe en grand texte. Adopter l’insécable (U+00A0) ou la fine (U+202F) est à arbitrer par le porteur.
- **Heures** : 24 h, `HH:mm` (`SchoolDateFormat.time`, `SchoolLessonHubRules`) ; pas de secondes à l’écran.
- **Dates** : gabarit `EEEEdMMMM` (« Lundi 21 septembre », capitale initiale seule par `capitalizedFirst`), `dMMMM` (« 21 septembre »), `EEE d MMM · HH:mm` dans la planification ; styles `.long` / `.medium` ailleurs. Toujours dans le fuseau de l’école de la leçon (`lesson.timeZone`), jamais celui de l’appareil par défaut. Saisie d’une date de naissance : `dd.MM.yyyy`.
- **Durées et plages** : « 90 min » (entier + espace + « min ») ; plage horaire « 14:00 – 15:00 » avec tiret demi-cadratin entouré d’espaces (`SchoolLessonHubRules.schedule`, `SchoolPlanningView`).
- **Montants** : `NumberFormatter` monétaire `fr_CH`, devise CHF (`SchoolCatalogFormatting.price`) ; jamais de montant composé à la main.
- **Nombres et pluriels** : chiffres tabulaires pour heures, durées, compteurs ; pluriel par règle explicite (`DrivySeanceText.observations`, « 1 observation », « 3 observations ») ; `Int.formatted()` pour un compteur seul.
- **Séparateur** : point médian « · » entre deux informations courtes d’une même ligne (« Lundi 28 septembre · 14:00 – 15:00 »).
- **Majuscules** : phrase normale pour titres, boutons et onglets (« Démarrer une leçon », « Accord GPS ») ; sigles en capitales (GPS, CHF) ; noms propres de catégorie tels quels (« Permis B »).

## Do's and Don'ts

- Ne pas créer d’écran d’administration de l’école dans l’app.
- Ne pas afficher de sous-titre explicatif, de note de bas de section ni de badge pour l’état normal.
- Ne pas montrer de position inventée, de carte factice, de score de conduite dérivé du GPS ni de succès avant écriture durable.
- Ne pas relier deux segments séparés par une lacune GPS.
- Ne pas utiliser de dégradé, de thème vitre global ni de vitre sur un formulaire.
- Ne pas cacher une commande dans un seul geste de balayage.
- Ne pas colorer en rouge un état normal (Complet, Sans GPS, refus GPS).
- Faire : tokens partout, une action primaire à la fois, statut toujours écrit en mots (badge avec symbole seulement hors des lignes de leçon), composants `Drivy*` partagés.

## Écarts constatés

Relevé factuel du 29 septembre 2026 sur la branche `codex/revue-integration-20260929` (chemins relatifs à `apps/ios/Drivy/`). Rien n’est corrigé ici. Gravité : **haute** = contredit une décision du porteur ou peut tromper l’utilisateur ; **moyenne** = même besoin traité de plusieurs façons visibles ; **basse** = dette de cohérence peu visible.

### Gravité haute

1. **Promesse de confidentialité contraire au partage automatique.** `SchoolCaptureUI/SchoolCapturePreparationView.swift:421` affiche « Le trajet reste privé. Cette action ne publie ni carte ni bilan. », alors que le trajet d’une leçon réalisée est visible par l’élève sans publication (décision du 28 septembre).
2. **Textes explicatifs superflus (règle « peu de texte »).**
   - Notes de bas de section : `SchoolAgendaUI/SchoolPlanningView.swift:79`, `:250`, `:258-260` ; `SchoolObservationUI/SchoolObservationView.swift:356`, `:415`.
   - Préparation du trajet, paragraphes hors erreur : `SchoolCaptureUI/SchoolCapturePreparationView.swift:220`, `:229`, `:283`, `:302`, `:347`, `:436`.
   - Accueil élève et profil (à alléger selon les décisions) : `SchoolProfileUI/SchoolOnboardingView.swift:219-293` (suite de `DrivyGuidedFact` et `DrivyGuidedStepHeader` avec phrase de justification), `SchoolProfileUI/SchoolProfileView.swift:202`.
   - Composants qui invitent au sous-titre : `DrivyGuidedStepHeader(reason:)` (`UI/DrivyComponents+Accueil.swift:38`) et `DrivyFormIntro(message:)` (`UI/DrivyComponents+Ecole.swift:211`).
3. **Vocabulaire serveur visible.** « Brouillon privé » et « Version historique » (`UI/DrivyComponents+Agenda.swift:78-80`), « Observation privée enregistrée. » (`SchoolObservationUI/SchoolObservationWorkspace.swift:232`), alors que la décision retient « Pour moi » / « Visible par l’élève » (`SchoolLessonReportUI/SchoolLessonReportView.swift:513`).

### Gravité moyenne

4. **Cinq présentations de « Réessayer ».** `DrivyRetryButton` contour danger (dans `SchoolErrorNotice`) ; bouton primaire (`SchoolCaptureUI/SchoolCaptureLiveView.swift:233-235`, `SchoolCaptureUI/SchoolRecordingChoiceView.swift:137-140`, `SchoolUI/SchoolRootView.swift:448-449`) ; secondaire (`SchoolCaptureUI/SchoolCapturePreparationView.swift:154`, `SchoolCaptureUI/SchoolCaptureLiveView.swift:311-313`) ; bouton système sans style (`SchoolCaptureUI/SchoolCaptureLiveView.swift:265`, `SchoolCaptureUI/SchoolLiveObservationSheet.swift:113`, `SchoolUI/SchoolRootView.swift:128`) ; lien d’état vide (`SchoolProfileUI/SchoolOnboardingView.swift:111`).
5. **Trois styles pour une action destructive pleine largeur.** `DrivyDestructiveButtonStyle` (`SchoolInvitationsUI/SchoolInvitationsView.swift:236-239`, `:492-495`) ; ligne de `Form` à rôle destructif, 48 pt (`SchoolAgendaUI/SchoolPlanningView.swift:252-255`) ; `.bordered` + `.controlSize(.large)`, 44 pt (`SchoolObservationUI/SchoolObservationView.swift:373-381`).
6. **Chargements muets** (`ProgressView()` sans texte) : `SchoolInvitationsUI/SchoolInvitationsView.swift:29`, `SchoolAgendaUI/SchoolStartNowView.swift:205`, `SchoolLessonReportUI/SchoolLessonReportView.swift:39`, `:317`, `SchoolTrainingUI/SchoolTrainingView.swift:43`, `:126`, `:228`, `SchoolTripsUI/SchoolTripsView.swift:26`, `SchoolUI/SchoolBrowserView.swift:59`, `:214`, `:303`, `:362`, `SchoolUI/SchoolHomeView.swift:205`, `SchoolUI/SchoolRootView.swift:209`, `:456`, `SchoolUI/SchoolTodayView.swift:129`, `SchoolJoinUI/SchoolCodeJoinView.swift:25`. Ailleurs, `DrivyLoadingState` et `ProgressView("…")` coexistent pour le même cas de section.
7. **Panneau de carte reconstruit.** `SchoolUI/SchoolTodayView.swift:141-143` refait `surface` + `mapPanel` + ombre (rayon 12) au lieu de `.drivyMapPanel()` / `DrivyMapDock` (ombre de rayon 18) ; même rôle, ombre différente.
8. **Même objet, deux typographies.** Code d’invitation : largeTitle gras mis à l’échelle depuis 46 pt (`SchoolInvitationsUI/SchoolInvitationsView.swift:389-396`) contre title semi-gras depuis 32 pt (`SchoolJoinUI/SchoolCodeJoinView.swift:12`, `:58`). Nom de l’élève en tête de feuille de leçon : `.drivyScreenTitle` (`SchoolCaptureUI/SchoolCapturePreparationView.swift:87`, `:408`, `SchoolCaptureUI/SchoolRecordingChoiceView.swift:55`) contre `.drivyTitle` (`SchoolLessonReportUI/SchoolLessonReportView.swift:301`).
9. **Titres de section sans composant ni trait d’en-tête.** `Label(...).font(.drivySection)` sans `.isHeader` : `SchoolCaptureUI/SchoolCapturePreparationView.swift:173`, `:204`, `:277`, `:301`, `:321`. `DrivySectionHeader` n’est utilisé que dans quatre fichiers d’écran.
10. **Formulations concurrentes pour le même geste.** Abandon d’une saisie : « Fermer sans enregistrer » (`SchoolLessonReportUI/SchoolLessonReportView.swift:62`), « Abandonner la saisie » (`SchoolObservationUI/SchoolObservationView.swift:304`), « Quitter sans enregistrer » (`SchoolProfileUI/SchoolOnboardingView.swift:42`), « Quitter le formulaire » (`SchoolProfileUI/SchoolProfileView.swift:26`). Renvoi d’une demande incertaine : « Renvoyer la même demande » (défaut de `DrivyPendingRequest`), « Renvoyer exactement cette demande » (`SchoolObservationUI/SchoolObservationView.swift:411`), « Reprendre cet envoi » (`SchoolCaptureUI/SchoolCapturePreparationView.swift:288`), « Réessayer » (`SchoolCaptureUI/SchoolRecordingChoiceView.swift:137`).
11. **Listes maître/détail de styles différents.** Élèves en `.plain` sur `surface` (`SchoolUI/SchoolBrowserView.swift:109`), Invitations en `.insetGrouped` sur `canvas` (`SchoolInvitationsUI/SchoolInvitationsView.swift:58-60`), pour le même motif `NavigationSplitView`.
12. **Bandeau d’erreur de synchronisation hors composant.** `SchoolUI/SchoolRootView.swift:124-134` : texte `.callout` sans symbole, sans ton ni surface d’erreur, bouton sans style.
13. **Couleurs système hors tokens.** `DrivyApp.swift:84` (`Color(.systemBackground)`) et `:89` (`.secondary`) sur l’écran de masquage.
14. **Plusieurs actions primaires possibles dans une vue.** `SchoolCaptureUI/SchoolCapturePreparationView.swift` déclare six `DrivyPrimaryButtonStyle` (`:119`, `:134`, `:148`, `:226`, `:307`, `:447`) ; vérifier en rendu que le démarrage rapide et le diagnostic ne sont jamais visibles ensemble.

### Gravité basse

15. **Largeurs et seuils en littéraux.** Colonnes de 720 (défaut), 800 (`SchoolAgendaUI/SchoolAgendaView.swift:86`), 820 (`SchoolAgendaUI/SchoolPlanningView.swift:20`, `SchoolAgendaUI/SchoolStartNowView.swift:208`, `SchoolInvitationsUI/SchoolInvitationsView.swift:355`, `:488`), 640 (`SchoolCaptureUI/SchoolCaptureLiveView.swift:71`, `:80`), 600 (`SchoolUI/SchoolTodayView.swift:66`), 560 (`SchoolInvitationsUI/SchoolInvitationsView.swift:425`, `SchoolJoinUI/SchoolCodeJoinView.swift:27`, `:180`, `SchoolCaptureUI/SchoolLiveObservationSheet.swift:35`) et 680 (`UI/DrivyComponents+Agenda.swift:266`). Seuil 760 recopié (`SchoolCaptureUI/SchoolCaptureLiveView.swift:43`) au lieu de `DrivyMapLayout.sidebarBreakpoint` (employé par `SchoolCaptureUI/SchoolCaptureReplayView.swift:163`) ; seuils 960, 1000 et 900 sans nom ; popover figé à 480 × 560 (`SchoolCaptureUI/SchoolCaptureLiveView.swift:257-258`).
16. **Espacements hors échelle.** `spacing: 16` (`SchoolCaptureUI/SchoolCapturePreparationView.swift:428`), `padding(.vertical, 1)` (`SchoolCaptureUI/SchoolCaptureReplayView.swift:376`).
17. **Graisse hors échelle.** `.caption.weight(.heavy)` sur les repères du replay (`SchoolCaptureUI/SchoolCaptureReplayView.swift:391`, `:610`) ; heure de la leçon en `.title3.weight(.bold)` (`SchoolUI/SchoolTodayView.swift:150`), entre `drivySection` et `drivyTitle`.
18. **Ombres en noir littéral.** `UI/DrivyComponents+Seance.swift:65`, `:550`, `SchoolCaptureUI/SchoolCaptureReplayView.swift:615`, `SchoolUI/SchoolTodayView.swift:143` (opacités 0,12 et 0,15, rayons 3, 12 et 18).
19. **Composants partagés inutilisés ou en double.** Sans usage dans les écrans : `DrivyCard`, `DrivyLessonFactRow`, `DrivyStatusDot`, `DrivyTimeColumn`, `DrivyContextHeader`, `StorageCaption` et `InlineErrorView` (`UI/DrivyTheme.swift:155`, `:167`, galerie seulement). `InlineErrorView` double `SchoolErrorNotice`, lui-même défini dans un fichier d’écran (`SchoolUI/SchoolBrowserView.swift:465`) et non dans `UI/`.
20. **Retour d’appui inégal.** Carte de sélection à 0,98 (`UI/DrivyComponents.swift:455`) contre 0,96 pour les boutons et tuiles.
21. **Bouton « Fermer » en `.bordered`** dans l’état vide du trajet (`SchoolCaptureUI/SchoolCaptureLiveView.swift:37`), seul emploi d’un style système pour cette action.
22. **Référence racine en retard sur les décisions.** Le `DESIGN.md` racine décrit encore les onglets Séance et École et des écrans d’administration natifs ; les onglets réels sont Aujourd’hui, Agenda, Élèves, Trajets (moniteur) et Leçons, Progression (élève) (`SchoolUI/SchoolHomeView.swift:78-162`).

### Seconde passe (libellés et localisation)

23. **Haute — textes d’autorisation système périmés.** `Info.plist:25` et `:27` parlent encore de « trajet d’essai » et de « séance d’essai » (laboratoire retiré le 28 septembre) avec une apostrophe droite ; ce sont les textes des alertes de localisation montrées à l’utilisateur. Le moniteur lit une promesse qui ne décrit plus l’usage réel.
24. **Moyenne — deux mots pour l’absence de niveau.** « Non observé » dans le bilan (`SchoolLessonReportUI/SchoolLessonReportView.swift:607`) contre « Pas encore vu » dans la progression (`SchoolTrainingUI/SchoolTrainingView.swift:221`).
25. **Basse — formats de date dispersés.** `SchoolDateFormat` n’est employé que par l’agenda ; les autres écrans créent leur propre `DateFormatter` (`SchoolCaptureUI/SchoolCapturePreparationView.swift:385`, `:391`, `:457`, `SchoolAgendaUI/SchoolPlanningView.swift:330`, `SchoolTrainingUI/SchoolTrainingView.swift:280`, `SchoolObservationUI/SchoolObservationWorkspace.swift:102`) ; ce dernier affiche des secondes (`timeStyle = .medium`, ligne 104).
26. **Moyenne — registre de l’élève (résolu le 29/09/2026).** Tutoiement partout ; les composants partagés, `Info.plist` et le message d’invitation web sont tutoyés, les écrans School* suivent leur passe dédiée.


## Passe du 5 octobre 2026 (soir) — dossier, fiche de leçon, bilan

- **Dossier** : un seul groupe « Leçons » / « Progression » quel que soit le nombre de formations ; les permis se lisent en une ligne sous le nom (« Permis A, B (terminée) »). Le filtre par permis vit dans chaque page ; en Progression, « Tous » aligne une section par permis, sans score global.
- **Fiche de leçon** : le contenu suit le statut. L’état inhabituel est un mot de texte en tête (`lesson-state`), jamais une pastille ni une confirmation verte. Les objectifs prévus restent lisibles après la leçon. Pour le moniteur, une leçon terminée s’ouvre en lecture.
- **Trajet** : la carte porte sa seule commande, un bouton lecture (`play.fill`, 48 pt, vitre des commandes de carte) en bas à droite ; avec plusieurs trajets il ouvre leur liste.
- **Rédaction du bilan** : parcours poussé dans la pile de la fiche, étapes Trajet (ou Observations), Compétences, Bilan ; une étape sans contenu est omise. Titre de l’étape et « 2 sur 3 » dans la barre, retour système, « Continuer » en secondaire, action finale en primaire à la dernière étape seulement. À partir de 900 pt hors grand texte : un écran en deux colonnes, mêmes sections, même bouton.
- **Lignes de compte et de profil** : pas de symbole de tête.