# Icônes et signalement — 4 octobre 2026

## Demande et méthode

Le porteur demande cinq propositions pour l’image de l’application et cinq icônes pour chaque catégorie de « Signaler », puis une sélection cohérente et une interface plus sobre. Il demande ensuite de peaufiner les icônes retenues.

**65 propositions originales conservées** : cinq images d’application générées indépendamment avec ImageGen ; cinq dessins SVG originaux pour chacun des onze thèmes de signalement et pour l’action « Marquer un moment ». Les pictogrammes vectoriels restent nets dans le catalogue natif. Le raffinement ultérieur de la proposition d’application retenue n’est pas compté comme une sixième proposition initiale.

Les fichiers sont dans [assets/native-icons-20261004](assets/native-icons-20261004). Les prompts de l’application, les cinq propositions par thème, les raisons de sélection et les comparaisons optiques sont conservés. Les fichiers `selected/` correspondent aux imagesets de l’application. Aucun changement du référentiel de compétences ou du contrat serveur.

## Choix

| Usage | Choix | Motif |
|---|---|---|
| Application et accueil | 01, d routier blanc sur cobalt, puis raffiné | Monogramme compact et distinctif ; les propositions 2 et 3 étaient plus génériques, 4 pouvait se lire comme un 5, 5 comportait trop de courbes fines. |
| Maîtrise du véhicule | 04, volant | Relation directe avec les commandes ; centre simplifié pendant la finition. |
| Observation | 01, œil | Silhouette lisible sans détails accessoires. |
| Priorité à droite | 03, intersection et arrivée de droite | La direction porte le sens ; évite de confondre ce thème avec le cédez-le-passage. |
| Signalisation | 05, panneau directionnel | Un seul signe suffit à exprimer la signalisation. |
| Cédez-le-passage | 01, triangle inversé | Reconnaissable sans texte ni second contour. |
| Intersections | 01, giratoire et îlot | L’îlot distingue la chaussée d’une commande d’actualisation. |
| Vitesse | 01, compteur | Représente la maîtrise de la vitesse sans imposer une limite chiffrée. |
| Placement | 01, voiture dans sa voie | Relation claire entre le véhicule et les limites de voie. |
| Manœuvres | 01, entrée dans une place | Voiture et déplacement, avec espace entre flèche et carrosserie. |
| Autoroute | 01, chaussée et pont | Silhouette distincte du simple placement. |
| Anticipation et partage | 02, voiture et piéton | Deux usagers identifiables, séparés optiquement. |
| Marquer un moment | 02, signet | Un repère à retrouver ; n’implique pas une position GPS disponible. |

Les formes partagent un canevas 64 × 64, un trait 3,2 à extrémités et raccords arrondis et un fond transparent. Le catalogue les teinte avec les couleurs sémantiques existantes. La comparaison porte sur les silhouettes à 96, 40 et 24 pixels, puis sur les captures Apple ; aucune perfection n’est déduite du seul contrôle des bornes SVG.

## Interface

« Signaler » présente les thèmes sur une grille aérée avec pictogramme et libellé, sans disque ni bordure permanente par case. L’appui reçoit une réponse discrète, compatible avec Réduire les animations. Les grandes tailles d’accessibilité passent à une colonne et les textes gardent leur hauteur.

« Marquer un moment » est une action distincte sous la grille. Après choix du thème, les trois appréciations restent explicites et non présélectionnées. Le thème choisi et son icône sont dans le contenu défilant ; le titre de feuille reste « Signaler ». La confirmation « Ajouté à la leçon » apparaît uniquement après l’écriture durable déjà contrôlée par le parcours.

L’icône de l’application et son image d’accueil utilisent la même exportation PNG 1024 × 1024 opaque. Les originaux ImageGen sont conservés à leur résolution de sortie ; l’export ne change que les dimensions.

## Skills et vérification

Imagegen : création bitmap pour l’identité de l’application et raffinement par édition du candidat sélectionné ; pictogrammes natifs dessinés en vectoriel. UI Skills, Impeccable `polish`, `quieter`, `distill`, `ios` et `craft-floor` : cohérence avec les tokens et les composants existants, retrait des cadres inutiles, ajustements optiques. SwiftUI UI patterns, Interaction design et Better accessibility : appui, défilement, grand texte, libellés accessibles et Réduire les animations.

Les candidats ont été relus par deux agents puis sélectionnés à l’intégration. Une seconde critique optique a recherché les amas de traits, les raccords serrés et les différences de gabarit des voitures. Les planches avant/après conservent la comparaison ; les propositions originales ne sont pas écrasées.

Résultats Apple et limites finales : voir [la revue native](native-ui-review-20261004.md) et [STATUS](STATUS.md). Aucun résultat VoiceOver physique, GPS routier ou batterie n’est inféré des captures.
