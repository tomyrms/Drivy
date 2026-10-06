# Territoire B — « L'instrument »

## Idée centrale
Drivy est l'instrument de bord de la leçon. Un seul mécanisme : **la graduation** (crans réguliers, un repère majeur, une valeur lue exactement). Elle produit le logo, les chiffres, les jauges et le mouvement. Élément fort unique : le **chiffre tabulaire lu sur une règle**. Tout le reste se tait.

## Personnalité
Exact, calme, professionnel, sans emphase. L'instrument relève, le moniteur explique.

## Principes graphiques
1. Une valeur = un chiffre + une étiquette + (si utile) une règle. Jamais de graphique décoratif.
2. Une graduation mesure toujours quelque chose de vrai (temps, niveau, heure). Sinon elle n'existe pas.
3. Un seul index cobalt par écran.

## Formes caractéristiques
Cran mineur (1 pt), cran majeur (1,5 pt, plus long), index (3 pt, cobalt). Déclinaisons : règle de leçon, jauge à 4 crans, ligne de temps, rail d'agenda.

## Palette
Rien n'est ajouté ; les rôles changent.
- Cobalt `#245BD6` / sombre `#91B5FF` : **gardé**. Devient l'index (et l'action principale).
- Encre `#10151C`, surface `#19222E`, texte `#F2F5FA` : le canvas sombre existant devient la matière des panneaux d'instrument.
- Clairs gardés : `#F7F8FA`, `#FFFFFF`, `#EEF2F7`, `#18212B`, `#536174`, `#D9E0E9`.
- Une seule valeur nouvelle, icône uniquement : `#4479F2` (cobalt plein sur encre : 3,09:1 calculé ; `#4479F2` : 4,59:1).
- **Ambre écarté** comme couleur de marque : deux aiguilles font un tableau de bord, et l'ambre signifie déjà « Attention ». Il reste sémantique.

## Traitement de la couleur
Aplats. Cobalt = index, sélection, trace, action primaire, rien d'autre. Les crans sont neutres. Les sémantiques n'apparaissent que sur les repères d'observation.

## Typographie
SF Pro conservé. Traitement propre :
- **Relevés** (chrono, compteurs, heures) : chiffres tabulaires, semibold, grands (40–52 pt), `.fontWidth(.expanded)` à valider à l'œil.
- **Étiquettes** : 11 pt semibold, capitales, interlettrage +0,09 em, via `.textCase(.uppercase)` (VoiceOver intact), trois mots au plus.
- Corps inchangé. **SF Mono écarté** (connotation éditeur de code). **Condensed écarté** (lisibilité en conduite).

## Iconographie
SF Symbols monochromes et les 12 pictogrammes gardés tels quels ; aucun nouveau jeu.

## Style cartographique
`MapStyle.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)`. Trace `MapPolyline` cobalt 6 pt + halo blanc 11 pt, inchangée. **Crans de minute** : `Annotation` posées sur les échantillons GPS réels à chaque minute pleine (trait encre 20 × 2 pt). Chiffres (1′, 2′) seulement au replay. **Écarté** : crans par motif de tirets — l'espacement serait en points d'écran, donc une fausse mesure.

## Surfaces et cartes
Clair : filets 0,5 pt, pas d'ombre, relevés séparés par un filet vertical. Pendant la leçon : panneaux encre (rayon 24, ombre conservée) posés sur carte atténuée. **Correction de la piste « cockpit sombre »** : la carte reste claire de jour (reflets au soleil) ; seuls les panneaux sont encre. Mode sombre système la nuit.

## Mouvement
« Caler » : une valeur arrive sur son cran et s'arrête. `.snappy(duration: 0.22, extraBounce: 0)`, `.contentTransition(.numericText())` pour les chiffres, `sensoryFeedback(.selection)` au passage d'un cran en scrub. Aucun mouvement continu : l'index de leçon avance d'un cran par minute.

## Philosophie du logo
Six idées :
1. Vernier : deux rangées de traits, une seule coïncidence — *construit, rejeté : lu comme égaliseur ou touches de piano.*
2. Rangée de crans avec un repère majeur — code-barres.
3. Arc gradué — compteur de vitesse, interdit de fait.
4. Trait coiffé d'une pastille (repère d'observation) — épingle GPS.
5. Wordmark « drivy » dont le point du i est un cran — détail trop faible seul.
6. **Le d repère** : un d minuscule dont la hampe est le repère majeur d'une graduation ; quatre crans mineurs s'alignent sur sa ligne de tête. — *retenu.*

Il garde le d du 4 octobre et lui donne l'idée qui manquait.

## Philosophie de l'App Icon
Une face d'instrument, pas un logo dans un carré : fond encre, graduation blanche qui déborde sur tout le bord supérieur, hampe cobalt qui part du bord, panse blanche agrandie.

## L'identité dans l'app
1. Leçon active : chrono 52 pt + règle 0–50 min, index cobalt.
2. Trace : crans de minute.
3. Replay : piste graduée (10 s / 1 min), lacune en pointillé, index au lieu du pouce rond.
4. Progression : relevés « 1 · AVEC ACCOMPAGNEMENT » et jauge à 4 crans à la place des trois points (qui ne montraient pas « pas encore vue »).
5. Agenda : rail horaire gradué.
6. Écran de lancement : la graduation seule, l'index se cale.

## Risques et limites
- **Froideur pour l'élève** : réel. Parade : aucun chiffre ne note l'élève ; les phrases du moniteur restent en corps normal, premières.
- **Tableau de bord SaaS** : capitales + gros chiffres en sont le vocabulaire. Tenu seulement si chaque règle mesure du vrai et s'il n'y a qu'un index.
- **Cliché compteur** : évité (aucun arc, aucune aiguille pivotante).
- Les crans du logo fusionnent en bande grise à 16 px : il reste un d.
- Jauge à crans moins immédiate que trois points ; à tester avec un moniteur.
- Capitales fragiles en Dynamic Type XXL.

## Test « capture sans logo »
Leçon active : **oui** (panneau encre, grand chrono sur règle, crans sur la trace). Replay : oui. Progression : **partiel** — relevés et jauge distinguent, mais une liste reste une liste. Profil, formulaires : non, assumé.
