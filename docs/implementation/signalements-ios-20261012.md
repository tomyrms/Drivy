# Signalements configurables — app iOS (12 octobre 2026)

Contrat et décisions communes : [signalements-configurables-20261012.md](signalements-configurables-20261012.md). Cette note ne couvre que `apps/ios`.

**Rien n’est compilé ni vu sur appareil.** Cette machine n’a pas de toolchain Swift : aucun test n’a tourné, aucun écran n’a été rendu. Tout ce qui suit est écrit et relu, pas vérifié.

## Fichiers

Créés :

- `Drivy/SchoolObservationAPI/SchoolObservationThemes.swift` : thème, catalogue embarqué des 18 thèmes, règle de fusion, corps du `PUT`, erreurs typées, client `GET`/`PUT`.
- `Drivy/SchoolObservationAPI/SchoolObservationThemeStore.swift` : copie locale, store par école et par accès, registre des stores.
- `Drivy/SchoolCaptureUI/SchoolSignalGrid.swift` : règle de disposition (`SchoolSignalGridLayout`), contenu d’une tuile, aperçu de la grille.
- `Drivy/SchoolObservationUI/SchoolObservationThemeSettingsView.swift` : écran « Signalements » et feuille « Aperçu ».
- `DrivyTests/SchoolObservationThemeTests.swift`.

Modifiés : `SchoolCaptureLiveObservations.swift` (tuiles, instantané, `themeKey`), `SchoolLiveObservationSheet.swift`, `SchoolCaptureLiveView.swift` (hauteur du volet), `SchoolObservationEmblem.swift`, `DrivyObservationGlyph.swift` (4 cas, résolution par clé), `SchoolObservationModels.swift` et `SchoolCaptureModels.swift` (`themeKey`), `SchoolObservationClient.swift` (champ admis, refus 422), `SchoolAgendaClient.swift`, `SchoolCaptureSessionController.swift`, `SchoolObservationWorkspace.swift`, `SchoolCaptureLiveMap.swift`, `SchoolReplayTimeline.swift`, `DrivyComponents+Agenda.swift`, `DrivyComponents+Seance.swift`, `SchoolHomeView.swift`, `SchoolProfileTabView.swift`, `DrivyDesignSystemGallery.swift`, `SchoolVisualReview.swift`, `SchoolFieldVisualReview.swift`, et les tests `SchoolLiveObservationRecorderTests.swift`, `SchoolObservationPictogramTests.swift`, `DrivyUITests/NativeNavigationTests.swift`.

## Décisions

### Stockage local

Un fichier JSON par école dans Application Support (`SchoolObservationThemes/<école>.json`), en clair : ordre et affichage des thèmes du catalogue, aucune donnée de personne. Il n’a rien de commun avec la file chiffrée et n’écrit jamais le repli embarqué, qui passerait ensuite pour une réponse de l’école. `canManage` n’est pas copié : il ne vient que d’une réponse de l’école pendant la session.

### Pas de file pour l’écriture

L’enregistrement ne passe pas par la file chiffrée (une demande par école, partagée avec les leçons). Le store garde l’état confirmé, montre la proposition pendant l’envoi et y revient en cas d’échec. Un résultat inconnu se rejoue avec le même `operationId` et le même `If-Match` : le serveur le traite comme un rejeu.

### Tuiles

- Titre de tuile = titre du catalogue (« Vitesse », « Anticipation »), pas le libellé de la compétence.
- Une tuile générique est donnée à toute compétence qu’aucun thème n’a prise, y compris quand un référentiel porte à la fois `manoeuvres` et `parking`.
- L’enregistreur accepte un thème masqué (contrôle fait sur tous les thèmes, pas sur les seuls affichés).

### Instantané de la palette

L’enregistreur garde `themeConfiguration`. `openPalette()`, appelé à l’apparition de la palette, y copie le dernier état confirmé du store puis lance une relecture ; son résultat reste dans le store jusqu’à l’ouverture suivante.

### Règle de disposition

| Tuiles | Colonnes voulues |
|---|---|
| 1 à 3 | autant que de tuiles (une rangée de tuiles larges) |
| 4 | 2 |
| 5 à 12 | 3 (inchangé pour 11 et 12) |
| 13 et plus | 4 |

Le nombre voulu est ensuite limité à ce que la largeur permet sans passer sous 100 pt par tuile (148 pt dès la taille XXL). Sur un iPhone, 13 à 15 tuiles donnent donc 5 rangées de 3 et 16 à 18 tuiles 6 rangées de 3 ; sur le popover de l’iPad (480 pt), 4 colonnes, soit 4 ou 5 rangées. La règle ne suppose aucun nombre de thèmes. Tailles d’accessibilité : une colonne. Hauteur minimale de tuile inchangée (80 pt).

Le volet prend la hauteur de son contenu : estimée d’abord (`estimatedPaletteHeight`), puis mesurée (en-tête + grille + appréciations), plafonnée par l’écran. Estimation : 513 pt pour 12 tuiles (ancien budget : 520), 601 pt pour 15, 689 pt pour 16 à 18. Si la place manque, seule la grille défile. Un message passager (erreur, « Envoi précédent en cours… ») n’entre pas dans la mesure, pour ne pas redimensionner le volet sous le doigt.

### Réordonnancement

Liste groupée native (`List` `.insetGrouped`, comme le Profil) en mode d’édition permanent, avec `.onMove` : poignée, soulèvement, défilement automatique et retour haptique du système. La règle « pas de `List` » vise les pages de lecture ; les réglages du Profil sont déjà une liste native. Chaque rangée est un interrupteur ; « Monter » et « Descendre » sont des actions d’accessibilité qui annoncent la nouvelle position.

### Aperçu

Bouton « Aperçu » de la barre : une feuille montre la grille à sa taille réelle. Je ne l’ai pas posé dans la page : douze tuiles occupent environ 350 pt et repousseraient la liste sous l’écran.

### Réinitialisation

« Réinitialiser l’ordre » part sans question. « Rétablir la configuration d’origine » pose une seule question.

### Dernier thème affiché

L’interrupteur n’est pas grisé : le refus s’explique par une phrase (« Au moins un signalement reste affiché. »), seulement quand il se produit.

## Skills

- `write-swift` : types valeur, `@Observable` sur l’acteur principal, une tâche par opération, Swift Testing.
- `swiftui-ui-patterns` : état local, modèle injecté, feuille qui se ferme elle-même.
- `fixing-accessibility` : noms accessibles, actions de déplacement, annonces d’état, rien par la couleur seule.
- `baseline-ui` : erreur près de l’action, une confirmation pour le geste destructif, pas d’animation ajoutée hors retour à l’état confirmé.
- `apple-design` : pas de saut sous le doigt, retour immédiat au geste.
- `ui-skills-root` : n’a servi qu’à choisir les précédents.
- `apple-hig` : chargé, mais ses fiches de référence sont absentes du dépôt ; aucune règle n’en est tirée.

## Écarts et trous à trancher

- **« Priorités » se déplie toujours en trois tuiles.** Avant, seulement si la description de la compétence nommait les trois sous-thèmes. Le contrat ne garde pas cette condition.
- **Référentiel ancien (`parking`, libellé « Stationnement »)** : la tuile s’appelle maintenant « Manœuvres ». Les données de démonstration de l’app sont dans ce cas.
- **Catalogue plus récent côté serveur** : corrigé dans le second lot (voir plus bas).
- **Campagne de captures** : l’écran `observation-themes` existe dans le harnais, mais n’est pas dans `supportedScreens` : il faudrait aussi l’ajouter à `scripts/ios/capture-screens.sh`, hors de mon périmètre (un test Python compare les deux listes). Les captures clair et sombre de l’écran viennent du test UI `testProfileOpensObservationThemesWithItsCounterAndPreview`.
- **`STATUS.md` non mis à jour** (hors périmètre).
- **Transport de démonstration en lecture seule** : dans le harnais, toute modification échoue et montre le retour à l’état confirmé.

## À regarder à la première compilation

1. `SchoolObservationPictogramTests.everyPictogramAndAppraisalHasAnAsset` échoue tant que les imagesets `Observation-indicators`, `-following-distance`, `-braking`, `-lane-change` ne sont pas au catalogue.
2. `SchoolLiveObservationRecorder.init` : `themeConfiguration` (propriété observée sans valeur initiale) est affectée dans l’initialiseur.
3. `SchoolObservationThemeStore` : tuple `uncertain` sous `@ObservationIgnored` ; `static var makeCache` de type `@MainActor () -> any SchoolObservationThemeCache`.
4. `SchoolLiveObservationSheet.swift` : `GeometryReader` à la racine de la palette, `onChange(of:initial:)` sur une hauteur optionnelle, trois `onGeometryChange`.
5. `SchoolObservationThemeSettingsView` : `if case .failed(let message) = …` dans un `@ViewBuilder` ; `.environment(\.editMode, .constant(.active))` ; boutons de réinitialisation en style propre (un bouton au style automatique ne répond pas dans une liste en édition).
6. `SchoolObservationThemeTests.swift` : littéraux multilignes avec `\` de continuation, fermetures finales dans `#expect`.

## À voir à l’œil

- Le volet à 1, 4, 12 et 15 tuiles sur iPhone, et le passage estimation → mesure à la première ouverture (un réglage de quelques points est possible).
- Le détent de la feuille (leçon sans GPS) qui suit la hauteur mesurée.
- La liste en mode d’édition : interrupteur et poignée côte à côte, en clair et en sombre, en grand texte.
- VoiceOver : « Monter », « Descendre », annonce de position, annonce « Enregistré ».
- Le popover de l’iPad, qui raccourcit quand il y a peu de tuiles.

## Mise à jour : 18 thèmes (12 octobre, second lot)

Toujours sans compilation ni rendu.

- **Catalogue** : `moving-off` « Démarrage » (`vehicule`), `bends` « Virages » (`placement`), `eco-driving` « Éco-conduite » (`vehicule`), en fin de liste, masqués à l’origine. Douze thèmes restent affichés à l’origine.
- **Plus de 15 en dur** : compteur, validation du corps, tests, données de démonstration et galerie lisent le catalogue. La galerie montre 1, 12, 15 et 18 tuiles.

### Grille à 16, 17 et 18 tuiles

Calculé, pas vu. Le volet fait la largeur de l’écran moins 32 pt.

| Écran | Volet | Colonnes | Tuile | Rangées | Volet estimé |
|---|---|---|---|---|---|
| 375 pt | 343 pt | 3 | 104 pt | 6 | 689 pt |
| 430 pt | 398 pt | 3 | 122 pt | 6 | 689 pt |

Quatre colonnes demanderaient un volet d’au moins 436 pt : aucun iPhone en portrait. Je n’ai pas réduit la tuile sous 100 pt pour y arriver.

- **430 × 932** : environ 807 pt utiles, tout est visible sans défilement.
- **375 × 812** : environ 696 à 702 pt utiles pour 689 : à la limite. Selon les marges réelles, la dernière rangée peut dépasser de quelques points ; la grille défile alors.
- **375 × 667** (iPhone SE) : environ 615 pt utiles ; la grille défile d’environ 74 pt, soit presque toute la sixième rangée.

Dans tous les cas, seule la grille défile ; l’en-tête et les appréciations restent en place. De 13 à 15 tuiles, rien ne change.

### Pictogrammes

- Trois cas : `movingOff`, `bends`, `ecoDriving`. Mots : « démarrage », « calage » (mot entier : « décalage » n’est pas reconnu), « virage », « éco-conduite », « écoconduite », « eco-drive ».
- **La compétence prime, plus strictement qu’avant** : avec une compétence, le texte n’est plus cherché que parmi les sous-thèmes de cette compétence. Effet de bord : « Clignotant et freinage » rattaché à « Maîtrise du véhicule » donne désormais Freinage (avant : Maîtrise du véhicule).
- Sans compétence, les nouveaux mots sont en fin de liste : ils ne reprennent aucun texte qu’un mot plus ancien reconnaissait (« Démarrage du véhicule » reste Maîtrise du véhicule).

### Catalogue de l’école différent de celui de l’app

- **École plus récente** : les thèmes inconnus de l’app ne sont pas montrés, mais gardés (`foreign`) et renvoyés à chaque `PUT`, replacés après le thème connu qui les précédait, avec leur affichage. Plus de 400 en réordonnant.
- **École plus ancienne** (cas symétrique, non demandé, mais il aurait produit le même 400) : les thèmes que l’école ne liste pas (`unlisted`) restent dans la liste à leur place d’origine, masqués et non réglables ; ils ne sont pas envoyés au `PUT`, et une observation ne porte jamais leur `themeKey`.
- La copie locale garde ces deux listes ; une copie écrite par une version plus ancienne de l’app ne tient pas les nouveaux thèmes pour connus de l’école.

### À regarder à la compilation

- `everyPictogramAndAppraisalHasAnAsset` échoue tant que `Observation-moving-off`, `-bends` et `-eco-driving` ne sont pas au catalogue d’assets.
- `SchoolObservationThemeConfiguration` : deux propriétés à valeur par défaut ajoutées en fin de structure ; les appels à trois arguments doivent rester valides.
- `SchoolObservationPictogram.init` : `self = title.flatMap { … } ?? fromKey` dans un initialiseur faillible.

## Mise à jour : douze tuiles visibles, la suite défile (12 octobre, troisième lot)

Demande du porteur : les douze premiers signalements affichés visibles d’emblée, les suivants dans la même grille en dessous, atteints en la faisant défiler. Ni pagination, ni « Voir plus », ni second écran, ni carrousel. Le volet ne grandit plus avec le nombre de tuiles au-delà de douze.

- **Règle** (`SchoolSignalGridLayout`) : `immediateTileCount = 12`, `visibleRows` = rangées des douze premières, `overflows` quand des tuiles suivent, `windowHeight(tileHeight:)` = rangées visibles + amorce. Le choix des colonnes ne change pas (3 sur iPhone, 4 sur le popover iPad au-delà de 12). Douze se divise par 1, 2, 3 et 4 : la fenêtre finit toujours sur une rangée pleine.
- **Tuiles de hauteur égale** : hors tailles d’accessibilité, chaque libellé réserve deux lignes (`lineLimit(2, reservesSpace: true)`, resserré jusqu’à 85 % avant troncature). À la taille par défaut, la tuile garde ses 80 pt. La palette mesure la première tuile ; la fenêtre s’en déduit, sans lire les tuiles lointaines d’une grille paresseuse.
- **Amorce et fondu** : au-delà de douze, le volet montre 16 pt de la rangée suivante (plus la marge), sous un fondu qui commence exactement sous la dernière rangée de la fenêtre et disparaît en fin de course (`onScrollGeometryChange`). L’indicateur de défilement apparaît un instant à l’ouverture (`scrollIndicatorsFlash(onAppear:)`).
- **Volet** : 513 pt estimés jusqu’à douze tuiles (inchangé), 533 pt au-delà, quel que soit le nombre ; il tient dans un iPhone de 667 pt. Le popover iPad montre trois rangées de quatre.
- **Ordre et masquage** : inchangés. Les tuiles viennent de la configuration de l’école, dans son ordre, sans les masquées ; un thème passé de la 16e à la 2e place est dans la fenêtre à l’ouverture suivante (l’instantané reste pris à l’ouverture, rien ne bouge sous le doigt).
- **Inchangés** : boutons, sélection (fond seul, hauteur constante), écriture, paysage compact (tout le volet défile), tailles d’accessibilité (une colonne, feuille en grand détent).

### Contrôle

- `SchoolSignalGridLayoutTests` : 8, 12, 15, 18 et 24 tuiles sur 288, 343, 361, 398 et 480 pt ; hauteur constante au-delà de douze ; fondu limité à l’amorce.
- Écran de capture `signal-all` : la palette de leçon avec les dix-huit thèmes affichés. La galerie montre 1, 8, 12, 15, 18 et 24 tuiles (au-delà du catalogue, des tuiles génériques).
- La campagne de captures ne connaît qu’un modèle d’iPhone et un d’iPad : les autres tailles d’iPhone ne sont couvertes que par les tests de règle.
- `test_swift_and_shell_supported_screens_match` échouait déjà sur master (cinq écrans du script absents de la liste Swift) ; `signal-all` est ajouté aux deux.

- **Feuille trop haute de la marge du bas (corrigé)** : les captures iPhone montraient environ 34 pt vides sous la grille. Le détent `.height` d’une feuille ne compte pas la marge de sécurité du bas, que la palette ajoutait. La feuille la retire désormais (`countsBottomInset: false`) ; le volet posé sur la carte la garde. Le popover de l’iPad était juste.

### À voir à l’œil

Le fondu en clair et en sombre, l’amorce sur iPhone SE et Pro Max, le défilement à 120 Hz, le geste de défilement qui commence sur une tuile (le système le tranche : pas de sélection si le doigt glisse).

**13 octobre 2026** : la fenêtre passe de douze à **neuf tuiles (3 × 3)**, demande du porteur. Trois colonnes dès cinq tuiles, iPad compris ; au-delà de neuf, la même grille défile dans sa zone, avec l’amorce estompée de la rangée suivante. Six ou huit tuiles s’affichent seules, sans case vide. Ordre et réglages inchangés.
