# Territoire C — « Côte à côte »

## Idée centrale
Apprendre à conduire, c'est deux personnes dans une voiture, jusqu'à ce que l'une continue seule. Deux présences accolées, séparées par un joint constant, dont l'une dépasse l'autre : ce motif donne la marque, la paire de couleurs et la lecture de la progression (le niveau = l'écart).

## Personnalité
Professionnelle, patiente. Elle montre qui a fait quoi ; elle ne félicite pas.

## Principes graphiques
1. Toujours deux, jamais trois. 2. Le joint (2–3 pt de fond) sépare, rien ne fusionne. 3. La longueur dit le niveau, la couleur dit qui. 4. Hors de la paire, l'écran reste neutre.

## Formes caractéristiques
Jauge à deux voies ; double filet vertical ; avatars accolés ; flèche de position fendue. Écarté comme pictogramme : deux capsules verticales (« pause », « histogramme »).

## Palette
Gardés tels quels : cobalt #245BD6 / sombre #91B5FF, neutres ardoise, sémantiques. Ajout unique : vermillon #DB5A2A / sombre #F5774A. Pourquoi cette teinte : la complémentaire du cobalt tombe sur l'ambre déjà pris par « Attention » ; 16° est le seul créneau chaud libre entre ambre (38°) et danger (355°), et il s'en écarte par la clarté (les sémantiques sont sombres). Mesuré : 3,8:1 sur blanc, 6,7:1 sur canvas sombre — assez pour une forme, pas pour du texte. Neutres non réchauffés : c'est le fond froid qui rend un seul trait chaud intentionnel.

## Traitement de la couleur
Cobalt = action, sélection, trace, et la voie du moniteur. Vermillon = l'élève, uniquement : sa voie, son anneau d'avatar, sa moitié de flèche, son filet. Jamais de texte, de bouton, de fond ni d'état en vermillon ; jamais seul porteur du sens (position et libellé doublent). Plafond : quatre occurrences par écran.

## Typographie
SF Pro, deux graisses seulement (Regular, Semibold), Bold réservé au chronomètre. Chiffres tabulaires. Titres en Semibold serré (−0,3 pt), sans capitales.

## Iconographie
SF Symbols et les 12 pictogrammes restent monochromes ; seule la flèche de position est bicolore.

## Style cartographique
`MapStyle.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll)`. Trace inchangée (deux `MapPolyline` : halo blanc 11 pt, cobalt 6 pt). Trace doublée écartée : pas de décalage latéral dans MapPolyline, et aucune donnée ne dit quand le moniteur intervient. Position (`Annotation`) : disque blanc 34 pt, flèche fendue, moitié gauche vermillon (place du conducteur), droite cobalt. Repères d'observation inchangés.

## Surfaces et cartes
Filets, rayons et ombres inchangés. Seul ajout : le double filet (3 pt cobalt + 3 pt vermillon, joint 3 pt) à gauche de tout bloc visible par l'élève ; filet cobalt seul pour ce que le moniteur garde privé.

## Mouvement
Deux gestes, une fois chacun. Rejoindre : la voie de l'élève s'allonge jusqu'à celle du moniteur (0,28 s, sans rebond). Lâcher : elle la dépasse, l'autre ne bouge pas. Au changement de niveau seulement. Reduce Motion : fondu.

## Philosophie du logo
Six idées :
1. Deux capsules verticales inégales, bases alignées.
2. Les mêmes, inclinées à 15°.
3. Deux capsules égales décalées, l'une en avance.
4. Un d dont la panse (demi-disque) longe la hampe sans la toucher, la hampe continuant au-dessus.
5. Un U aux branches inégales : même origine, une seule poursuit.
6. Deux arcs concentriques dont l'extérieur se prolonge.

Construites et regardées : 1 lit « histogramme », 2 « barre oblique » (et voisine de monday.com), 3 « pause décalée » ; 5 fusionne les deux présences ; 6 retombe dans le « virage partagé » déjà refusé. Retenue : 4. On lit un d, puis deux formes côte à côte. Tient en noir et à 16 px (joint de 20/256). Trois passes : v1 tout rond, v2 base plate et congés de 8, v3 panse abaissée et joint élargi.

## Philosophie de l'App Icon
Fond clair, pas de carré bleu. La panse cobalt est posée dans le cadre ; la hampe vermillon sort par le haut : elle continue hors de l'icône.

## L'identité dans l'app
1. Progression : jauge à deux voies à la place des trois points.
2. Bilan et « Prochaine étape » : double filet.
3. Note privée : filet seul.
4. Dossier et listes : anneau vermillon sur l'avatar d'un élève.
5. Agenda (web surtout) : avatars moniteur + élève accolés.
6. Carte : flèche fendue, reprise dans « GPS actif ».
7. Lancement : le symbole seul, immobile.

## Risques et limites
- Le logo reste un « d » : l'idée existe, mais elle se découvre au second regard ; disque + barre rappelle la famille Patreon. Recherche d'antériorité non faite.
- Leçon en cours : presque rien ne change, et c'est voulu (lisibilité). Sur cet écran le territoire ne se reconnaît pas.
- La jauge code deux informations ; sans libellé elle demande un apprentissage, et un administrateur peut y lire deux séries de données.
- Vermillon proche du danger pour un protanope : d'où l'interdiction d'en faire un signal.
- Double filet : à 3 pt il ne lit pas « pause », mais c'est à vérifier sur appareil.

## Test « capture sans logo »
Réussi sur Progression, bilan et agenda : deux voies, deux filets, une seule teinte chaude sur fond froid. Échoué, honnêtement, sur la leçon en cours et le signalement.
