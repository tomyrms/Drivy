# Icônes des catégories de permis — 12 octobre 2026

Demande du porteur : une famille d’icônes propre à Drivy pour les catégories de permis suisses, avec trois propositions par catégorie, une sélection argumentée, des assets vectoriels, un composant SwiftUI central et l’intégration dans les écrans de l’élève et du moniteur. Atelier, planches et notes : [`assets/icones-permis-20261012/`](assets/icones-permis-20261012/).

## Catégories couvertes

La source est l’OAC (RS 741.51), art. 3. Elle compte 16 catégories, toutes dessinées :

| Groupe | Catégories |
|---|---|
| Motocycles et cyclomoteurs | A, A1, M |
| Voitures et véhicules légers | B, B1, BE |
| Véhicules lourds | C, C1, CE, C1E |
| Transport de personnes | D, D1, DE, D1E |
| Catégories spéciales | F, G |

Hors liste, sans icône : la restriction « A limitée à 35 kW », les qualifications professionnelles (OACP, TPP 121), les catégories étrangères (AM, B96) et les offres propres à une école. Le serveur stocke `categoryCode` en texte libre. Un code inconnu reçoit le symbole neutre du permis (`person.text.rectangle`) et n’emprunte jamais le dessin d’une autre catégorie.

F n’a pas de silhouette définie par l’OAC (« véhicules automobiles dont la vitesse maximale n’excède pas 45 km/h »). Le petit utilitaire à pont ouvert est une convention propre à Drivy.

## Démarche

- **logo-design** (skill installé) : une idée par icône, construction par primitives à géométrie calculée (shapely). À chaque tour, rendu regardé à 128, 64, 24, 20 et 16 px, et un défaut nommé par tour. `svg_audit.py` a servi à caler les angles presque nets sur 0/15/45/60/75°. Planches et aperçu rendus avec `render_png.py`.
- **apple-hig / apple-design-hig** : seuls leurs `SKILL.md` sont installés ; leurs fichiers de référence (`distilled/`) manquent dans le dépôt. Les règles appliquées viennent des résumés de ces fichiers : un seul langage visuel, des icônes vectorielles accompagnées d’un libellé, rien porté par la couleur seule, cibles de 44 pt.
- **Grammaire « Signaler »** ([icônes Signaler](icones-signaler-20261012.md)) : la nouvelle famille en est la sœur. Canevas 64, gabarit d’une seule couleur, vrais trous `evenodd`, contre-forme d’au moins 4, bouts ronds.

## Grammaire de la famille

- Véhicule de profil, l’avant à droite, roues posées sur un sol commun.
- Une remorque s’attelle toujours à gauche, timon visible : « E » se reconnaît sans libellé.
- Une sous-catégorie « 1 » garde la silhouette de sa catégorie, plus courte, **à l’échelle de la catégorie mère** : A1 et M à l’échelle de A, B1 à celle de B, C1 à celle de C, D1 à celle de D. F prend l’échelle de B (petit véhicule).
- Couples jumeaux : B/BE, C/CE, C1/C1E, D/DE et D1/D1E réutilisent exactement le même véhicule.

## Trois directions par catégorie

- **A · Natif** : contour d’épaisseur constante, vitres pleines, roues annelées, dans l’esprit d’un SF Symbol.
- **B · Signature** : silhouette pleine arrondie, vitres évidées. Chaque roue est le repère annelé de la marque, mordu dans la caisse comme le repère mord la trace.
- **C · Géométrique** : blocs chanfreinés à 45°, joint entre cabine et caisse, roues pleines.

Toutes les propositions sortent du même modèle de véhicule. Ce sont donc trois rendus d’un même dessin : la sélection ne peut pas casser la famille.

Planche comparative : `planche.png` (la retenue est cerclée et sa note affichée).

## Sélection

Chaque note est sur 5. Pondération : cohérence avec Drivy 30 %, reconnaissance immédiate 25 %, lisibilité à petite taille 20 %, harmonie entre catégories 15 %, qualité esthétique 10 %. `selection.py` calcule les totaux et retient la meilleure proposition. Si les choix individuels divergeaient, il harmoniserait vers la direction majoritaire. Ce n’a pas été nécessaire : **B l’emporte dans les 16 catégories**, avec 4,25 à 4,8 contre 3,15 à 3,65 pour A et 3,2 à 3,45 pour C.

Les notes sont un jugement posé après avoir regardé les rendus, pas une mesure. Raisons principales :

- **A** s’allège trop à 16 pt, et ses contours tranchent avec les aplats de « Signaler » et de la marque. Pour les ensembles, contour du véhicule et contour de la remorque fusionnent.
- **C** reste lisible, mais ses chanfreins disparaissent sous 24 pt et ses roues pleines alourdissent le dessin. Sur un deux-roues, elles deviennent deux pastilles. Ses angles vifs sont étrangers à la trace ronde.
- **B** est la seule direction qui porte la marque (le repère). Ses silhouettes pleines restent nettes à 16 pt.

| Cat. | Pourquoi ce dessin |
|---|---|
| A | Moto lourde : carénage, réservoir et selle d’un seul profil, grandes roues |
| A1 | Le profil de A sans carénage, plus bas, à l’échelle de A |
| M | Cadre de vélo avec pédalier et petit bloc moteur, à l’échelle de A |
| B | La voiture de référence : deux vitres, roues-repères |
| B1 | Voiturette à une vitre, plus haute que longue, à l’échelle de B |
| BE | La voiture de B, timon, remorque à un essieu |
| C | Caisse haute, cabine avancée, essieu arrière tandem |
| C1 | Le camion de C raccourci, un essieu arrière, à l’échelle de C |
| CE / C1E | Le camion de C ou de C1 et une remorque à deux essieux ou à un essieu |
| D | Car : quatre vitres alignées, avant chanfreiné |
| D1 | Minibus : nez court incliné, deux vitres, à l’échelle de D |
| DE / D1E | Le car ou le minibus et une remorque |
| F | Petit utilitaire lent à pont ouvert (convention) |
| G | Tracteur : grande roue arrière sous la cabine, capot bas, échappement |

Planche finale : `planche-finale.png`. Aperçu en contexte, en clair et en Soft Charcoal : `contexte.png` (maquette aux jetons de `DrivyTheme`, pas une capture).

## Production

- Catalogue Xcode : 16 jeux `License-<code>` (`License-b`, `License-c1e`…), un SVG vectoriel chacun. `preserves-vector-representation` assure la netteté de 16 à 48 pt à toutes les densités ; le gabarit (`template-rendering-intent`) prend sa couleur dans `foregroundStyle`, donc dans les jetons clair et sombre. Aucun fond. Taille intrinsèque de 24 pt, celle d’une icône de menu.
- Nomenclature : la clé `license.category.<code>` du brief correspond à l’asset `License-<code>`, dans la convention du catalogue (`Observation-*`).
- Ne pas retoucher ces SVG à la main. Modifier `atelier.py`, puis lancer `python atelier.py && python selection.py && python export.py`.

## Composant

`apps/ios/Drivy/UI/DrivyLicenseIcon.swift` :

- `DrivingLicenseCategory` : seule correspondance code → dessin. Elle tolère la casse, les espaces et les préfixes « Permis » et « Cat. » ; elle renvoie `nil` hors OAC.
- `DrivingLicenseIcon(code:size:relativeTo:emphasis:isDecorative:)` : cadre carré suivi par Dynamic Type, états `normal` (encre atténuée), `selected` (accent) et `disabled` (`disabledText`). L’icône est décorative à côté de son libellé. Seule, VoiceOver la lit (« Permis BE, voiture et remorque »).
- `DrivingLicenseLabel` pour les menus et sélecteurs, `DrivingLicenseValue` pour la valeur d’un `LabeledContent`, `DrivyLicenseTile` pour la pastille en tête de ligne. `DrivyRowLeading.license(code)` met cette pastille dans `DrivyEntityRow`.

## Intégration

| Écran | Rôle | Changement |
|---|---|---|
| Leçons et Progression : filtre de permis | élève, et moniteur dans le dossier | Icône du permis choisi dans le déclencheur (accent) ; icône et libellé dans chaque entrée du menu |
| Progression « Tous les permis » | élève, moniteur | Icône devant le titre de chaque permis |
| Profil : permis suivis | élève | Pastille du véhicule en tête de ligne, masquée en très grand texte |
| Accueil (onboarding) : « Ta formation » | élève | Le symbole `car` générique devient le véhicule du permis (une moto pour A) |
| Planification : formation, sélecteur | moniteur | Icône dans la valeur et dans les choix |
| Commencer maintenant : formation | moniteur | Icône dans les choix |
| Réglages d’agenda : formation par défaut | moniteur | Icône dans les choix |
| Invitation : permis proposés | moniteur | Icône dans chaque bascule, avec les trois états normal, sélectionné et désactivé |

Laissé en texte, volontairement :

- En-tête du dossier élève (« Cat. B (En cours) · Cat. A (En pause) ») : une décision antérieure écrite dans le code refuse une rangée de badges.
- Lignes d’historique de leçon : elles ne nomment le permis que dans une liste mixte, et la ligne est déjà dense.
- Bilan : il ne parle que du permis physique de l’élève, pas d’une catégorie.

Aucune logique métier n’est modifiée : seul l’affichage dépend de `categoryCode`.

## Vérification

- **Exécuté ici** : rendus regardés à chaque tour, `svg_audit.py` (aucun échec, angles calés), planches et aperçu en clair et en sombre.
- **Ajouté** : `DrivingLicenseCategoryTests` vérifie les 16 codes, la tolérance de saisie, le refus des codes hors OAC et la présence d’un asset par catégorie.
- **Compilation et tests Apple** : exécutés sur GitHub Actions, voir [STATUS](STATUS.md).
- **Non qualifiable ici** : rendu sur appareil, VoiceOver, Contraste accru, iPad. Les captures du simulateur des écrans multi-permis (B, A, BE) sont la seule vue réelle disponible.

## Limites

- Les ensembles avec remorque (BE, CE, C1E, DE, D1E) sont larges, donc petits : lisibles à 20 pt, plus difficiles à 16 pt. Le libellé reste toujours écrit à côté.
- A et A1, comme C et C1, se distinguent surtout par la taille et un détail (carénage, essieu tandem). La silhouette dit la famille, le libellé dit la catégorie exacte.
- Les arcs aplatis donnent 300 à 550 points par SVG, comme « Signaler ». C’est sans effet pour une icône d’interface.
