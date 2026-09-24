# Carte, capture et replay · Grammaire visuelle

> Référence 3.16 · [Accueil design](README.md) · [Règles GPS canoniques](../03-fonctionnel/gps-replay.md).

**Référence visuelle courante :** [carte et replay privé](LECON.html). La carte schématique de cet atelier est une fixture distincte, jamais un fond Apple ni une trace mesurée. Une observation sélectionnée lie son moment à la carte ; déplacer ou zoomer manuellement la carte ne met pas la lecture en pause. Le recentrage reste explicite et ne remet pas le temps à zéro. Les règles de segments et d’absence de mesure de ce document restent obligatoires dans l’application : l’atelier simplifié ne couvre pas leurs variantes.


## Observations privées accessibles pendant la leçon

E23/iPad expose « Signaler », le raccourci « Marquer un moment » et la liste privée. Le signalement ouvre des catégories puis des lignes de statut dans un même panneau ; la précision textuelle reste facultative et au second niveau. La qualification s’utilise dans des conditions adaptées ; aucun bouton photo. Avant la première mesure, pendant une lacune ou sans GPS, aucun point n’est inventé. L’heure et l’état « Sur cet appareil · envoi en attente » restent distincts du partage. E04 sans GPS conserve les mêmes observations textuelles ; E08/E24 les retrouvent sans note automatique. La couleur ne porte jamais seule le statut. Les libellés et gestes sont une proposition à qualifier, non une validation de sécurité en mouvement. Voir [spécification](../03-fonctionnel/gps-replay.md#saisie-pendant-lecon).

## Trois couches et trois responsabilités

**Fond géographique :** MapKit proposé directement sur Apple, avec ses labels, style adapté au mode système et attributions préservées. Le fond ne doit pas être recoloré manuellement pour reproduire les parcs des maquettes. Les cartes web/Android nécessitent leurs fournisseurs et conditions propres.

**Données Drivy :** seuls les points mesurés admis, les segments, les observations autorisées et les repères de préparation. La représentation distingue leur origine. Pas de navigation guidée, de trafic ou d’itinéraire idéal ajouté au périmètre sous couvert de design.

**Commandes :** contexte et panneau superposés sans couvrir inutilement les passages utiles. L’état de collecte est visible même si la carte ne charge pas. Les commandes système peuvent employer leurs matériaux qualifiés ; le panneau de lecture reste opaque.

La carte des maquettes est volontairement schématique, fictive et sans coordonnées. Ses routes et noms de quartier n’illustrent ni un trajet réel ni une sortie de MapKit. [Maquettes](MAQUETTES.html).

## Vocabulaire de tracé

| Élément | Rendu de référence | Sens exact | Alternative textuelle |
|---|---|---|---|
| Trace mesurée | Trait `route` 5 pt, halo `routeHalo` 9 pt | Positions effectivement retenues dans le segment | Temps et liste des observations |
| Début / fin | Formes et labels distincts, pas vert/rouge seuls | Première/dernière mesure admissible du segment | « Début du segment », « Fin du segment » |
| Position de replay | Point plein cerclé ; taille visuelle 16–20 | Position du curseur dans les données disponibles | Instant sélectionné et numéro d’observation |
| Observation située | Pastille de statut compacte ; thème et symbole de statut pour le seul point sélectionné ; zone active >=48 | Renvoi par identifiant vers une observation autorisée, jamais fusionnée avec une voisine | Même thème, statut écrit et instant dans le panneau/la liste ; numéro réservé aux anciennes scènes de galerie |
| Repère prévu | Losange/contour et label « Prévu » | Lieu manuel envisagé avant la leçon, pas preuve de passage | Liste ordonnée des repères préparés |
| Lacune | Segments séparés, aucune ligne entre extrémités | Mesures absentes ou rejetées | Intervalle « Position indisponible » |
| Trace retirée | Aucun tracé ni vignette géographique résiduelle | Accès retiré ou effacement selon la projection | « Trajet indisponible », bilan autonome autorisé |

La couleur de la route et la couleur de marque coïncident dans A, mais leurs tokens sont distincts. Modifier ultérieurement l’identité d’une école ne recolore pas automatiquement le trajet ou les niveaux pédagogiques. Ne pas représenter une erreur de conduite en rouge à partir d’une simple mesure GPS.

Le halo aide à séparer le tracé du fond ; son ratio calculé ne garantit pas tous les fonds de MapKit. Tester centre urbain dense, routes claires, parcs, mode sombre, grand texte et contraste accru. Les labels et contrôles utilisent des surfaces stables. Un tracé décoratif peut rester fin ; ses points interactifs conservent leur cible tactile.

## Capture sur iPhone

Contexte supérieur compact : fermeture à gauche, prénom/nom, état de collecte et durée de séance. La fermeture retourne à la séance sans arrêter la collecte, selon l’état réel. L’atelier montre la durée de séance fictive ; elle n’est ni un temps GPS mesuré ni une base de facturation. L’action Signaler et les observations occupent le panneau inférieur. Pause/reprise/arrêt et fin de leçon sont dans le menu de séance de la proposition courante, avec arbitrage d’accès encore ouvert dans E23. L’objectif détaillé est secondaire. Le nombre de points n’est pas l’indicateur principal pour le moniteur.

Le détail de transfert est secondaire mais honnête : « Sur cet appareil · envoi en attente » lorsque c’est le cas. « Non partagé » reste distingué du transfert. Arrêter la collecte ne termine ni ne facture la leçon. La commande locale ne doit pas être bloquée derrière une confirmation réseau ou une série de dialogues. Pour les gestes sûrs, préparer avant et consulter à l’arrêt ; aucune saisie obligatoire en mouvement.

L’attente de la première mesure n’affiche pas une ancienne position comme départ. Une perte de permission produit une explication, la conservation réellement connue et une alternative sans capture. Pas de pulsation rouge permanente pour simuler l’activité.

## Replay

À l’ouverture, ajuster une fois tout le trajet disponible en tenant compte des panneaux et safe areas. Ensuite, distinguer deux contrôles : **lecture** et **suivi de caméra**. Pincer/déplacer la carte ne met pas automatiquement le temps en pause et ne recentre pas immédiatement la caméra. Le bouton Recentrer réactive un suivi visible.

À x1, la chronologie suit les durées enregistrées, pas une vitesse d’animation choisie arbitrairement. x2/x4 accélèrent l’aperçu, avec libellé accessible. Une lacune reste signalée ; son franchissement ne dessine pas un trajet interpolé considéré comme mesuré. Les animations de déplacement à l’intérieur d’un segment ne changent pas les données canoniques.

La chronologie dispose d’un curseur temps, de boutons d’observation précédente/suivante et d’une liste. Le thème du repère sélectionné correspond au panneau, son statut possède un symbole et un libellé écrit, et la sélection reste lisible sans couleur. Les identifiants distincts restent consultables séparément, y compris à horodatage égal ; la liste et précédent/suivant ne sautent aucune observation. La proximité visuelle ne crée ni fusion pédagogique ni nouvelle donnée. La gestion native des collisions de marqueurs reste à qualifier. Le lecteur d’écran annonce l’observation et son moment, pas chaque latitude/longitude.

Avec Réduire les animations, préférer des positions discrètes ou des mises à jour réduites et proposer la liste textuelle ; ne pas supprimer le replay. Une seule capture par bilan publié reste la limite du contrat courant. La maquette n’assemble pas discrètement plusieurs captures.

## Sans enregistrement

Ne pas ouvrir E23 comme une grande carte grisée. La séance E04/E22 présente nom, durée prévue, objectifs et accès au bilan. Un petit état neutre « Sans enregistrement GPS » suffit. Le refus ne déclenche ni avertissement culpabilisant ni baisse d’un taux de complétude.

Les observations textuelles autonomes conservent leur parcours de publication. Revoir un bilan publié ne demande jamais la localisation actuelle de l’élève. Les règles de choix et autorisations demeurent distinctes de cette apparence.

## Tablette et redimensionnement

Au moins 480 unités utiles pour la carte plus un panneau 320–400 lorsque la fenêtre le permet ; sinon passer au panneau inférieur ou à un détail lisible. Le seuil se mesure dans la fenêtre, pas selon le nom de l’iPad. À grande taille de texte, la colonne peut devenir pleine largeur sans perdre l’état local ni la commande d’arrêt.

Conserver capture, sélection, brouillon et contrôles au passage portrait/paysage. Le service Swift appartient à l’application, non à la vue. Le prototype de 1 180 unités illustre la composition large ; la recette inclut aussi fenêtre étroite et clavier. [Architecture Swift](../04-technique/architecture-client-swift.md).

## Rendu et performance à qualifier

L’atelier propose deux fonds **fictifs** : sobre et dense. Le second augmente rues, bâtiments, libellés et repères de contexte ; aucune tuile distante, coordonnée géographique ou licence MapKit n’est utilisée. Quatre observations optionnelles rapprochées permettent d’éprouver la lisibilité et l’accès par liste. Leurs cercles peuvent se chevaucher : ce test révèle une limite à traiter nativement, il ne démontre pas un système de regroupement spatial réussi. Les commandes de revue sont hors de l’application simulée. La prochaine vérification sur fond réel, avec attributions et comportement du SDK, reste NON EXÉCUTÉE.

Ne pas promettre un nombre de FPS ou une consommation depuis la maquette. Mesurer longs trajets, densité d’observations et pagination sur iPhone/iPad cibles. Une simplification de géométrie de rendu ne réécrit pas la géométrie publiée ni ne relie les trous. Les identifiants d’observation restent stables lorsque la liste recycle ses cellules.

L’état privé/partagé doit rester visible dans la fiche ; un outil administratif ne reçoit pas une carte privée simplement parce qu’il a davantage d’espace. Aucune capture de localisation réelle n’est effectuée par le prototype design.

<a id="temps-du-replay-et-réouverture-référence-v39"></a>
## Temps du replay et réouverture
Chaque observation localisée est reliée à un segment et à une mesure admissible. Le temps de lecture se traduit dans le même segment ; un trait de 30 % de la distance totale ne représente pas nécessairement 30 % du temps. Le point sélectionné et le repère de l’observation doivent coïncider selon les données canoniques, indépendamment du cadrage.

Une lacune temporelle n’a pas de position interpolée. Les segments sont dessinés séparément, sans ligne recouverte par un masque décoratif. À cet instant, masquer le curseur et afficher l’interruption ; conserver l’accès aux observations et aux temps connus. Les premières/dernières mesures des segments restent consultables. Avant la première annotation, ne pas présenter celle-ci comme l’observation courante.

La [fixture de dessin](replay-fictif.json) contient des coordonnées **de canvas**, des temps et deux annotations entièrement fictives. Elle sert uniquement à vérifier la correspondance visuelle. Ce n’est ni un trajet GPS, ni un calcul de qualité, ni le format HTTP de positions. La vérification attend notamment le repère 2 au temps 1 490 s, à (575, 230) dans ce canvas, et aucun point à 550 s dans le scénario lacunaire 480–620 s.

Revenir à la séance pendant une capture affiche « Retrouver la capture ». Aucune nouvelle autorisation, aucun nouveau `captureId`, aucun nouveau flux ne découle de la navigation. Passer à « Sans GPS » ne supprime pas la capture : arrêter d’abord la collecte, conserver les mesures acquises et poursuivre la leçon. Les commandes d’arrêt restent immédiates localement selon [F15](../03-fonctionnel/gps-replay.md#f15), sans confirmation réseau obligatoire.

Dans la galerie seulement, lecture basée sur le temps monotone du navigateur, suspendue lorsque le document devient invisible ; cela n’énonce pas le cycle de vie natif de la collecte. La caméra peut être manipulée indépendamment et la réduction des animations reste à éprouver sur appareil.
