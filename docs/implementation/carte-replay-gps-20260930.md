# Carte active, replay et signalements — 30 septembre 2026

## Demande et périmètre

Suivre le point et son sens de déplacement dans la carte active et le replay ; reprendre ce suivi avec le bouton de recentrage ; afficher les signalements pendant la leçon ; retirer le compteur de positions ; pouvoir annuler depuis le panneau sans établir de bilan. La clarification du porteur réserve la nouvelle direction artistique générale au **web**. Les couleurs, polices et composants natifs existants restent ceux de Drivy.

Références lues : `COMMENCER_ICI.md`, R15 et R41–R47, `gps-replay.md`, contrat AP154/AP156/AP157/AP161–AP164, scénarios T423–T434, `integration-ios-ipados.md` et décisions du 28 septembre. L’ouverture du replay en suivi explicite demandé le 30 septembre précise R45, dont le cadrage global initial était la proposition précédente. Le partage automatique du 28 septembre demeure applicable.

## Diagnostic dans le code

- Les cartes recentraient une `MKCoordinateRegion`, sans cap. Le replay démarrait avec son suivi désactivé. Le déplacement était figuré par un disque sans direction.
- La collecte utilisait déjà `kCLDistanceFilterNone`, `.automotiveNavigation`, sans pause automatique. Elle conserve chaque mesure admissible après commit SQLCipher ; aucun échantillonnage logiciel n’écartait un point sur deux ou ne réduisait une courbe à ses extrémités. Une impression de faible densité ne suffit donc pas à établir un défaut du capteur depuis Windows.
- La carte reconstruisait les tableaux de coordonnées au rafraîchissement. Le contrôle de caméra et le tracé pouvaient se disputer le travail pendant les animations.
- Les observations live envoyaient toujours une ancre nulle et n’étaient pas fournies à la carte active. Leur apparition ultérieure ne prouvait pas que le panneau avait mémorisé le point disponible à l’ouverture.
- L’annulation serveur accepte une leçon `PLANNED`, avec version et motif, sans imposer de bilan. Cette commande était accessible depuis le détail mais absente du panneau de capture.

## Changements réalisés dans les sources

### Suivi et direction

Le replay commence en mode suivi. Les deux cartes utilisent une `MapCamera` centrée sur le dernier point enregistré, avec le cap du déplacement. Une flèche remplace le disque lorsque ce cap est disponible. Sa rotation tient compte de celle de la carte, y compris en exploration manuelle.

Le cap est calculé entre **mesures existantes**, sans fabriquer une position. Une petite dérive à l’arrêt ne change pas la direction : le seuil est compris entre 3 et 15 mètres selon la précision enregistrée. Un nouveau segment ou un silence supérieur à 15 secondes réinitialise le cap. Ce seuil est un choix d’implémentation à éprouver, pas une précision garantie du GPS.

Un déplacement ou zoom manuel suspend le suivi. Le bouton de recentrage le réactive avec orientation ; le bouton de vue d’ensemble reste distinct. La distance de caméra choisie en exploration est reprise dans une plage de 180 à 2 500 mètres. Les transitions de caméra sont brèves et désactivées avec Réduire les animations. La lecture du replay ne demande aucune localisation actuelle.

Sélectionner un repère sur la carte déplace aussi la chronologie à son instant, comme la sélection depuis la liste. Cela ne réactive pas le suivi si la carte avait été déplacée à la main.

Les `MKPolyline` restent en mémoire entre les changements de caméra et de curseur. Les fragments live fermés sont réutilisés ; la direction live ne recalcule que les nouveaux points. Un silence supérieur à 15 secondes sépare également les traits affichés : aucune ligne pleine ne traverse cette lacune. Le curseur replay disparaît entre deux fragments ou dans une lacune connue, même si le précédent point a moins de 15 secondes.

### Collecte et fournisseur cartographique

Le flux reste Core Location, sans filtre de distance et sans pause automatique. La précision passe à `kCLLocationAccuracyBestForNavigation` lorsque l’appareil est alimenté (`charging`/`full`) et conserve `kCLLocationAccuracyBest` sur batterie. Le branchement ou débranchement actualise ce réglage pendant le trajet. Apple documente l’utilisation de capteurs supplémentaires pour la précision navigation et recommande de la réserver à l’alimentation externe. Aucune fréquence de réception ni autonomie mesurée n’est revendiquée. [Apple — précision navigation](https://developer.apple.com/documentation/corelocation/kcllocationaccuracybestfornavigation), [Apple — distanceFilter](https://developer.apple.com/documentation/corelocation/cllocationmanager/distancefilter).

MapKit fournit déjà la caméra avec cap, distance et centre nécessaires au suivi demandé. C’est le choix retenu pour ce correctif. [Apple — MapCamera](https://developer.apple.com/documentation/mapkit/mapcamera).

Mapbox Map Matching répond à un besoin différent : rapprocher une trace GPS du réseau routier. Il requiert un jeton et reçoit les coordonnées ; sa réponse est une géométrie calculée. Remplacer simplement le fond MapKit ne rendrait pas le capteur plus précis. Si un recalage routier est retenu ensuite, il devra rester une couche distincte des mesures, conserver les lacunes et permettre de relire la source. Aucun SDK Mapbox, jeton, abonnement ou envoi de coordonnées à ce service n’est introduit ici. [Mapbox — Map Matching API](https://docs.mapbox.com/api/navigation/map-matching/).

### Signalements immédiats et durables

1. « Signaler » fige l’heure et la référence capture/segment/séquence du dernier point **déjà durable**, au plus vieux de 15 secondes, dans le segment actif. Sans point, en pause ou avec une position ancienne, l’observation reste temporelle.
2. Choisir un statut ou marquer un moment écrit la commande dans l’outbox chiffrée. Le marqueur n’est ajouté qu’après cette écriture ; un échec de stockage n’ajoute rien à la carte.
3. Un marqueur en attente a un contour discontinu et un libellé accessible « envoi en attente ». Le contour devient continu après l’accusé serveur et le retrait réussi de l’outbox. La disparition du panneau ne dépend pas de cet accusé.
4. Avant l’envoi d’une observation ancrée, le journal produit le chunk contenant les points déjà stockés, y compris un chunk incomplet, puis le transfert l’acquitte. Cette opération ne termine pas le segment et ne crée aucune mesure. Les clés d’opération restent identiques lors d’un renvoi.
5. Un changement de capture, pause, révocation connue ou expiration avant confirmation invalide l’ancre proposée : l’app demande de rouvrir le signalement. Elle ne déplace pas silencieusement l’observation vers une autre position.

Le marqueur d’une commande encore en attente est reconstructible depuis cette commande chiffrée. Les observations confirmées restent en mémoire du contrôleur tant que la capture est affichée. Une relance ne restaure pas automatiquement un collecteur actif, conformément au comportement existant.

### Panneau et annulation

Le compteur de positions est supprimé du panneau et de la valeur accessible de la carte. Les messages d’erreur, perte de signal et transfert incomplet restent visibles.

« Annuler la leçon » ouvre le formulaire d’annulation existant avec motif. L’ouverture ne stoppe pas le trajet. Après confirmation, le callback `beforeCancellation` arrête la collecte et attend sa sauvegarde locale, puis le formulaire émet la commande versionnée d’annulation. Aucun `CompleteLesson` ni bilan n’est créé. La navigation revient à la leçon annulée seulement après confirmation du serveur. Un échec réseau garde la commande dans la file existante ; un échec de sauvegarde GPS bloque l’annulation distante et conserve l’erreur de capture.

La fermeture s’appuie sur le reçu durable de la commande et le retrait réussi de l’outbox, y compris lors d’une vérification ultérieure, sans dépendre du rechargement de la leçon. Une coupure après le reçu ne laisse donc pas la capture affichée comme encore à terminer. La pile de navigation Profil est identifiée par compte, école, adhésion et droits : changer d’école ferme ses préférences et recrée leur modèle dans la nouvelle portée.

## Guides UI consultés et traduction concrète

| Guide lu | Application au périmètre |
|---|---|
| `ui-skills-root`, catalogue CLI frameworks/interactions | Identification du parcours SwiftUI et sélection des guides natifs/mouvement. Le corpus a été élargi à la demande explicite du porteur. |
| `swiftui-ui-patterns` | État caméra local, service GPS détenu par l’app, feuille d’annulation pilotée par un modèle identifiable, pas de deuxième collecteur. |
| `interaction-design`, `animation-systems` | Animation servant uniquement à suivre le déplacement ; interruption au geste ; retour immédiat après persistance. Aucun mouvement décoratif ajouté. |
| `accessible-animation` | Préférence système Réduire les animations respectée ; les mêmes commandes et la même direction restent disponibles sans transition. |
| `60fps-animation` | Principe de limiter le travail par frame transposé au natif : géométrie MapKit retenue et calcul incrémental du cap. Aucun chiffre de FPS prétendument mesuré. |
| `interactive-hit-areas`, `better-accessibility` | Cibles natives 48 pt des commandes carte conservées ; symboles et libellés d’état accessibles ; marqueurs non interactifs distincts des boutons. |
| `better-writing` | Compteur technique retiré, verbes concrets pour annuler/recentrer, texte supplémentaire réservé aux erreurs et états inhabituels. |
| `apple-design-hig`, `apple-hig` | Instructions principales lues. Leurs dossiers de références ne sont pas livrés dans `.claude/skills` ; aucune valeur attribuée à une page HIG absente. Les API utilisées sont vérifiées dans les sources Apple ci-dessus. |

## Vérifications et reste à qualifier

Exécuté sur ce poste : lecture des sources, contrôle `git diff --check` ciblé, consultation des documentations officielles Apple/Mapbox. Le poste Windows ne possède ni `swift` ni Xcode : **compilation et tests Swift non exécutés dans ce chantier**.

Tests ajoutés pour le runner Apple :

- `SchoolMapCourseTests` : cap Est/Nord/Ouest, stabilité avec faible dérive, réinitialisation après silence, passage de l’antiméridien, coordonnées mesurées inchangées, aucune ligne ni curseur à travers une lacune.
- `SchoolLiveObservationRecorderTests` : marqueur après écriture seulement, absence en cas d’échec de stockage, restauration de l’intention, ancre et heure figées, refus d’une ancre invalidée.
- `SchoolCaptureLifecycleTests` : aucune ancre avant commit, rejet d’un point ancien/futur ou d’un GPS en pause, flush idempotent d’un chunk partiel sans pause ni nouveau segment.
- `SchoolPlanningDefaultsTests` : clôture confirmée malgré échec de la lecture suivante, absence de confirmation sans reçu et reprise par vérification du reçu sans second envoi.

À exécuter sur iPhone/iPad : suivi en virage et à l’arrêt, pan/zoom/recentrage pendant lecture, signalement puis réseau coupé, annulation avec sauvegarde et erreur réseau, rotation et fenêtre étroite, VoiceOver et Réduire les animations. Pour la collecte réelle : trajet comprenant intersections, giratoires, tunnel, verrouillage, arrêt prolongé, branchement/débranchement, mesures de précision/intervalle et batterie. Utiliser une trace d’essai autorisée ; ne jamais joindre coordonnées ou données de personnes aux logs/artefacts CI. Le profil matériel reste `NOT_QUALIFIED`.
