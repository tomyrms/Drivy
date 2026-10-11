# Thème sombre « Soft Charcoal » — 11 octobre 2026

Demande du porteur : refaire le thème sombre de l’app native, sans rien changer au thème clair. Direction imposée : anthracite neutre, doux, sobre. Périmètre : couleurs et design system chromatique de l’app iOS. Le web, la logique métier et les parcours ne sont pas touchés.

Branche `claude/dark-soft-charcoal-20261011`, partie de `claude/rideau-depart-fluide-20261010` (PR #10).

## Ce qui n’allait pas

Constats lus dans le code puis vus sur les captures du simulateur avant modification (run `38156084240`).

1. **Teinte bleu marine.** Tous les neutres sombres étaient des ardoises bleutées (`#10151C`, `#19222E`, `#222E3E`, filet `#34445A`).
2. **Hiérarchie inversée.** La page de lecture prenait `surface` et la carte `canvas`. En clair, cela donne une carte gris très pâle sur page blanche. En sombre, la carte devenait plus sombre que la page : un creux, pas un bloc. C’est ce qui donnait l’impression d’un thème clair retourné.
3. **Accent pastel en aplat.** Le bouton principal était bleu pâle `#91B5FF` avec un texte bleu nuit : lisible, mais délavé, et sans rapport avec le cobalt du clair.
4. **Un seul bleu pour tout.** Lien, aplat, tracé et teinte système partageaient la même valeur, alors qu’un texte et un aplat n’ont pas les mêmes besoins de contraste sur fond sombre.
5. **Désactivé invisible.** `disabledText` valait `muted` : un contrôle indisponible ne se distinguait pas d’une métadonnée.
6. **Ombres sans effet.** Les panneaux posés sur la carte comptaient sur une ombre à 10–12 %, invisible sur une carte sombre, et n’avaient aucun filet.
7. **Feuilles au même niveau que la page.** Une feuille ne se détachait pas de l’écran qui la présente.
8. **Écran de lancement noir pur**, puis fond ardoise au premier écran.

Ce qui était déjà sain : aucune couleur littérale dans les vues, les rangées de formulaire passent par `drivyFormRows()`, le chrome système (barres, onglets, menus, alertes) reste natif.

## Références

Recherche documentaire du 11 octobre. Aucune application n’a été observée directement : les faits viennent de pages lues.

| Référence | Ce qui est sourcé | Source |
|---|---|---|
| Apple, Dark Mode | Deux jeux de fonds, « base » qui recule et « elevated » qui avance ; contraste minimal 4,5:1 ; tester Contraste accru et Réduire la transparence. | developer.apple.com/design/human-interface-guidelines/dark-mode |
| Apple, Materials | Liquid Glass pour les commandes et la navigation, pas pour le contenu. | developer.apple.com/design/human-interface-guidelines/materials |
| Apple, Maps | Carte en emphase atténuée pour faire ressortir le contenu ; commande posée sur la carte avec filet fin ou ombre légère. | developer.apple.com/design/human-interface-guidelines/maps |
| Apple, Accessibility | 4,5:1 jusqu’à 17 pt, 3:1 à partir de 18 pt ou en gras. | developer.apple.com/design/human-interface-guidelines/accessibility |
| Linear | Thèmes dérivés en LCH depuis une base, un accent et un contraste ; élévation par la clarté. | linear.app/now/how-we-redesigned-the-linear-ui |
| Things 3 | Deux thèmes sombres distincts, gris foncé et noir. | culturedcode.com/things/blog/2018/12/dark-mode-for-ios |
| Material 2 | Gris foncé plutôt que noir ; élévation par voile blanc de 5 à 16 %. | m2.material.io/design/color/dark-theme |
| WCAG 1.4.11 | 3:1 pour un composant d’interface ou un graphique. | w3.org/WAI/WCAG22/Understanding/non-text-contrast |

Non vérifié : l’aspect réel de Plans, Wallet, Fitness, Flighty, Spotify et Arc en sombre (couleurs, matériaux, liseré d’itinéraire). Les valeurs qui circulent pour Linear et Spotify sont des reconstructions de tiers.

Principes retenus pour Drivy :

- élévation par la clarté, trois niveaux, une marche d’environ 1,2:1 ;
- une feuille monte d’un niveau ;
- filets discrets, jamais porteurs d’un état ;
- ombre réservée à ce qui flotte sur la carte, doublée d’un filet ;
- un bleu pour l’encre, un autre pour l’aplat ;
- variante Contraste accru pour le texte secondaire, l’accent et les filets ;
- tracé en deux traits : liseré de la couleur de la page, trait bleu au-dessus.

## Palette

| Rôle | Valeur | Écart avec la palette de référence du porteur |
|---|---|---|
| Fond principal (`canvas`, `surface`) | `#17191C` | identique |
| Surface principale (`surfaceCard`, `surfaceRaised`) | `#272A2E` | identique |
| Surface interactive (`surfaceMuted`) | `#34383D` | identique |
| Texte principal | `#F4F5F6` | identique |
| Texte secondaire | `#A1A5AD` | identique |
| Bleu de référence | `#4D80EB` | gardé tel quel pour le tracé (`route`) |
| Bleu d’encre (`accent`) | `#86ABF8` | éclairci : `#4D80EB` en texte ne fait que 3,85:1 sur une carte |
| Bleu d’aplat (`accentFill`) | `#3D70E2` | assombri : le blanc sur `#4D80EB` ne fait que 3,75:1, il fait 4,55:1 ici |

Les autres valeurs sont dans [`DESIGN.md`](../../DESIGN.md#themes). Les fonds d’état (succès, alerte, erreur, sélection) sont la teinte mêlée à 16–20 % dans la surface principale, pour rester dans l’anthracite.

## Tokens

Ajoutés. Leur valeur claire est celle du token qu’ils précisent, donc le clair ne bouge pas.

| Token | Rôle | Clair | Remplace, là où il s’applique |
|---|---|---|---|
| `surfaceCard` | Fond de carte, panneau, carte de sélection, champ de lien | `#F7F8FA` | `canvas` |
| `surfaceRaised` | Bloc posé sur une page ou sur la carte, rangée de formulaire, champ guidé | `#FFFFFF` | `surface` |
| `accentFill` | Aplat qui porte `onAccent` | `#245BD6` | `accent` |
| `textTertiary` | Chevrons décoratifs | `#536174` | `muted` |
| `scrim` | Voile derrière la palette de signalement | encre à 16 % | `shadow.opacity(0.16)` |

Inchangés de rôle : `canvas` et `surface` restent les deux fonds de page. Une vue écrite selon la règle existante (`.background(DrivyTheme.surface)` pour une page de lecture) reste donc juste.

`adaptive(clair, sombre, elevated:, darkHighContrast:)` : la branche claire ne lit ni le niveau ni le contraste. En sombre, `elevated` s’applique dans une feuille ou un popover (niveau système), `darkHighContrast` sous Contraste accru.

## Composants modifiés

- `DrivyTheme` : valeurs sombres, nouveaux tokens, variantes.
- `drivyShadow` : couches à 45 % et 38 % en sombre, inchangées en clair.
- `DrivyPrimaryButtonStyle`, jour sélectionné de l’agenda, épingle sélectionnée et bouton de lecture du replay : `accentFill`.
- `DrivyGroupedSurface` (`DrivyCard`, `DrivyPanel`), `DrivySelectionCardStyle`, champ de lien : `surfaceCard`.
- `drivyFormRows`, `drivyMapPanel`, `drivyLegibleMapControl`, marqueurs de carte, pouce du replay, bannière d’annulation, champ guidé, avatar sélectionné : `surfaceRaised`.
- `DrivyMapPanelModifier` : filet `border` conservé en sombre, même quand le panneau flotte.
- `DrivyNavigationRow`, `DrivyEntityRow`, rangée d’agenda : chevron en `textTertiary`.
- Écran de lancement : couleur `LaunchBackground` (blanc en clair, `#17191C` en sombre).
- Galerie du design system : pastilles des nouveaux tokens.

## Carte et GPS

- Tracé `#4D80EB` sur liseré `#17191C` (4,70:1 entre les deux).
- Marqueurs et position : pastille `#272A2E`, anneau de la couleur de la page.
- Panneaux : `#272A2E`, filet et ombre dense.
- Commandes en Liquid Glass teinté par la surface, inchangées dans leur principe.
- Style de carte inchangé (`standard`, relief plat, emphase atténuée) : MapKit choisit son propre fond sombre.

Aucune logique de localisation ou d’enregistrement n’est modifiée.

## Pour l’intégration avec la PR #10

Fichiers touchés hors `UI/` : une ligne ou deux dans `SchoolAgendaView`, `SchoolStartNowView`, `SchoolCaptureLiveView`, `SchoolMapCourse`, `SchoolMapTraceStyle`, `SchoolObservationUndoBanner`, `SchoolRecordingChoiceInline`, `SchoolRecordingChoiceView`, `SchoolJoinView`, plus `Info.plist`. Ce sont des substitutions de token, sans changement de structure.

Règle pour le code écrit en parallèle : un fond de page garde `surface` ou `canvas` ; un bloc dessiné avec une forme (`in: RoundedRectangle…`, `Circle()`, `listRowBackground`) prend `surfaceCard` ou `surfaceRaised` ; un aplat bleu qui porte du texte prend `accentFill`.

## Vérification

### Exécuté

- **Contrastes** : `python3 scripts/ios/theme-contrast.py` lit `DrivyTheme.swift` et contrôle 47 couples dans quatre états (clair, sombre, sombre dans une feuille, sombre en Contraste accru). Les 141 couples sombres passent leur seuil : 4,5:1 pour un texte, 3:1 pour un élément d’interface. [Mesures](proofs/dark-soft-charcoal-contrast-20261011.json). C’est un calcul sur les valeurs déclarées, pas sur les pixels rendus.
- **Valeurs claires** : le même script échoue si une valeur claire s’écarte de la référence. Les 27 tokens sont inchangés.
- **Compilation** : IPA d’essai compilée sur `73bd0ec` (run `38158333100`). L’IPA ne compile pas la cible de tests.
- **Tests métier** : 455 tests passent sur `73bd0ec` (run `38158334944`). Les parcours UI n’ont pas été rejoués.
- **Captures du simulateur**, iPhone, clair et sombre, 28 écrans avant (`88914a3`, run `38156084240`) et après (`4810967`, run `38156670509`), puis 5 écrans de contrôle sur `73bd0ec` (run `38158336642`).

### Thème clair, avant et après

Comparaison pixel à pixel des 28 captures claires.

| Résultat | Écrans |
|---|---|
| Identiques au pixel près (23) | agenda, capture-preparation, dossier, gps-choice, home-tabs, invitations, join-code, learner-home, learner, learner-progress, learners, lesson-finish, lesson, lesson-observations, observations, onboarding-formation, profile, profile-tab, progression, replay, sign-in, signal, start-now |
| Différence attendue | design-system : la galerie affiche les nouveaux tokens |
| Différence sans rapport avec le thème | planning (heure courante affichée), live (chronomètre), skeletons (phase du balayage), lessons-history (champ de recherche système saisi en cours d’animation) |

Sur `73bd0ec`, les écrans learners, learner, dossier et profile-tab restent identiques au pixel près.

### Thème sombre, relu sur captures

Moniteur : Aujourd’hui, Agenda, Élèves, dossier, démarrage, planification, leçon, observations, fin de leçon, historique, leçon en cours sur carte, replay, palette Signaler, choix du GPS, préparation du trajet, invitations, Profil. Élève : Leçons, Progression, accueil dans l’école, mes informations, code d’invitation. Transversal : connexion, galerie du design system, squelettes.

Planches avant et après : [accueil, agenda, dossier, leçon](assets/dark-soft-charcoal-20261011/apres-accueil-agenda-dossier-lecon.jpg) ([avant](assets/dark-soft-charcoal-20261011/avant-accueil-agenda-dossier-lecon.jpg)) ; [carte, replay, Signaler, profil](assets/dark-soft-charcoal-20261011/apres-live-replay-signaler-profil.jpg) ([avant](assets/dark-soft-charcoal-20261011/avant-live-replay-signaler-profil.jpg)).

Corrigé après la première relecture : la liste d’élèves, pleine largeur, formait une dalle plus claire que la page. Ses rangées gardent maintenant la couleur de la page (`drivyPlainRows`).

### Reste à qualifier

- **Sur appareil** : le rendu réel de la carte sombre (le simulateur de la CI n’affiche qu’un aplat sous le replay), le Liquid Glass des commandes sur carte, l’ombre des panneaux, le passage clair/sombre à chaud, VoiceOver.
- **Jamais rendus** : Contraste accru, Réduire la transparence, grandes tailles de texte, iPad, paysage. Les variantes de Contraste accru sont calculées, pas vues.
- **Écrans non capturés en sombre** : réglages de planification, création et détail d’invitation, erreurs de connexion, verrouillage de l’app, choix d’école, étapes d’accueil autres que la formation, feuille de tarif, leçon annulée.
- **Contrôles système teintés** : la teinte système est `accent` (`#86ABF8`), choisie pour le texte des barres et des liens. Un interrupteur activé et le jour courant sélectionné dans un sélecteur de date prennent donc ce bleu clair sous un élément blanc. À voir sur appareil ; le correctif serait une teinte `accentFill` posée sur ces contrôles.
- **Bouton principal** : `#3D70E2` au lieu du `#4D80EB` demandé, pour que le libellé blanc atteigne 4,5:1. À valider à l’œil par le porteur.
- **Web** : son thème sombre garde l’ardoise bleutée. Hors périmètre de cette passe.
- **Écran de lancement** : la couleur `LaunchBackground` n’a pas été vue ; iOS met en cache l’écran de lancement, un redémarrage de l’appareil peut être nécessaire pour la voir.
