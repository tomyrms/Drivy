# F15 et F16 : capture volontaire, replay et apprentissage

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; solutions détaillées proposées, à valider. [Index](../README.md).

<a id="f15"></a>
<a id="f16"></a>

## Proposition et périmètre

Le GPS est au cœur de Drivy parce qu’il relie le bilan à des situations vécues. La première version couvre la capture depuis le téléphone ou la tablette native qualifiée du moniteur lors d’une leçon individuelle de voiture, une chronologie fidèle, des observations situées et un replay simple consultable avec le bilan. Pas de navigation vocale, de détection de faute, de suivi permanent ni de capture individuelle d’un groupe moto.

**Règles canoniques :** [R41–R50](regles-etats.md#r41), [R15](regles-etats.md#r15), [R27](regles-etats.md#r27), [R34–R40](regles-etats.md#r34). Les réglages techniques proposés sont des cibles de prototype, pas des performances mesurées.

## F15 : objectif, habilitations et préconditions

Le moniteur actif et affecté à la leçon peut autoriser une capture sur son appareil. L’administrateur sans affectation pédagogique ne peut pas déclencher une capture ni consulter toutes les traces. L’élève peut consulter l’information et enregistrer son refus ; il n’a pas besoin de laisser son téléphone actif pour la collecte réalisée par le moniteur.

Avant départ : choisir la leçon et la bonne formation, vérifier le choix de l’élève, afficher la finalité, les destinataires et la conservation ; vérifier séparément la permission du système. Le mode « Commencer sans enregistrement » doit rester aussi visible que le mode GPS. Le choix peut être changé avant capture ; demander l’arrêt pendant la leçon reste possible sans justification obligatoire.

Le pilote exige une autorisation de capture en ligne avant le départ. Après délivrance, la perte de réseau n’arrête pas nécessairement la collecte locale tant que la borne d’autorisation reste valide. Un départ totalement hors ligne permet la leçon et le bilan, pas une nouvelle capture non autorisée. C’est un compromis proposé de confidentialité et de complexité, à tester sur le terrain, pas une demande explicite du porteur.

## Séquence nominale

1. Préparation : objectifs et dernière séance ; action « Commencer avec enregistrement ».
2. Autorisation : vérifications serveur et attribution d’un captureId unique ; pas de points avant succès et action locale explicite.
3. Capture : état visible RECORDING, stockage chiffré des points par segments et chunks ; émission progressive quand le réseau le permet.
4. Pause : fin du segment courant ; reprise crée un nouveau segment. La lacune reste une lacune.
5. Arrêt : collecteur local arrêté immédiatement, manifeste scellé puis envoi de la clôture. Le réseau n’est pas nécessaire pour stopper.
6. Fin de leçon : heures effectives, notes, consommation/charge normale ; upload éventuel encore en attente.
7. Reconstruction : le serveur vérifie le manifeste, ordonne les mesures et produit une projection complète ou partielle, sans inventer les trous.

## États indépendants

| Dimension | États proposés | Interprétation |
|---|---|---|
| Autorisation serveur | AUTHORIZED, STOPPED, REVOKED, EXPIRED | Autorisation non terminale ou arrêt établi ; pas un état live garanti de l’appareil. |
| Collecteur local | IDLE, RECORDING, PAUSED, STOPPED | État réel connu sur l’appareil collecteur ; conservé lors d’un changement d’écran. |
| Transport | LOCAL_ONLY, UPLOADING, SYNCED, PARTIAL, REJECTED | Données disponibles et preuves de transfert. |
| Publication | PRIVATE, PUBLISHED, WITHDRAWN, DELETED | Qui peut consulter, non la qualité de la mesure. |
| Leçon | PLANNED, COMPLETED, CANCELLED, NO_SHOW | Résultat métier maintenu séparé. |

Sans capture, il n’existe pas de session GPS « vide » obligatoire. L’écran indique « Trajet non enregistré ». Une capture interrompue peut être STOPPED/PARTIAL et être utilisée pédagogiquement, mais reste clairement partielle. SYNCED ne signifie jamais PUBLISHED.

## Interruptions et comportements honnêtes

| Événement | Résultat attendu |
|---|---|
| Autorisation système refusée | Explication, accès immédiat à la leçon sans enregistrement. |
| Réseau perdu | Continuer localement dans l’autorisation bornée ; afficher synchronisation différée. |
| Application tuée par l’utilisateur | Aucune promesse de continuité ; détecter à reprise et afficher la rupture. |
| Téléphone verrouillé | Fonction à qualifier sur appareil avec build natif ; pas conclusion depuis un simulateur. |
| Batterie faible ou espace insuffisant | Avertissement à l’arrêt, stop sûr et trace partielle ; ne pas perdre les chunks déjà acquittés. |
| Mauvaise précision | Conserver accuracyMeters ; qualité visuelle dégradée, pas point artificiellement parfait. |
| Horloge système corrigée | Ordre par segment/séquence, temps monotone relatif conservé ; ne pas calculer une durée négative. |
| Changement de moniteur/appareil | Pas de transfert à chaud au pilote ; arrêter la capture précédente et reprendre une procédure explicite. |
| Refus connu localement | Arrêt et blocage immédiats ; aucune reprise automatique. |
| Révocation serveur, appareil sans réseau | Limite technique documentée : connue à reconnexion ; couper localement à borne d’autorisation, rejeter les points au-delà du cutoff serveur. |

L’intégration Apple de référence est Core Location dans l’app Swift native ; ses possibilités de fond et ses sessions sont documentées par Apple [S73](../06-gouvernance/sources.md#s73), [S99](../06-gouvernance/sources.md#s99). Les paramètres de précision/fréquence et les comportements d’interruption restent à mesurer. Aucune fréquence marketing ni économie de batterie n’est déduite du choix Swift.

<a id="saisie-pendant-lecon"></a>
## Saisie pédagogique pendant la leçon

**Besoin conservé, solution proposée.** Le porteur a demandé de noter dans la Live Map un thème, par exemple « priorité à droite », et un statut « attention », puis de retrouver cette observation dans le bilan. Une refonte du code ou de l’interface n’annule pas ce besoin. L’interface ci-dessous, les trois libellés de statut et les règles de rattachement sont une **proposition de conception à valider en usage**, pas une étude utilisateur réalisée.

### Repère, observation et bilan : trois niveaux distincts

| Niveau | Contenu | Conséquence |
|---|---|---|
| Moment à revoir | Identifiant local stable, instant ; ancre GPS seulement si un point admissible est déjà disponible | Repère privé non qualifié. Aucune faute déduite et aucune note attribuée. |
| Observation qualifiée | Thème du référentiel de la formation, statut choisi, instant et commentaire facultatif | Information pédagogique privée ; plusieurs observations possibles pour le même thème. |
| Évaluation publiée | Compétences finales et sélection d’observations explicitement relues | Snapshot de la révision, visible selon les droits. Aucun calcul de note depuis le nombre de repères ou le statut. |

Les statuts d’événement proposés sont `ATTENTION` (« Attention »), `TO_REWORK` (« À retravailler ») et `POSITIVE` (« Réussi dans ce contexte »). Ils ne remplacent pas les niveaux de compétence de R17 et ne valent ni diagnostic ni résultat d’examen. Une icône et son libellé rendent le sens lisible sans couleur ; pas de tags colorés massifs. Le thème s’appuie sur `CompetencyDefinition` de la formation, pas sur un nouveau catalogue global implicite. Le commentaire peut rester vide dans l’UI : la description envoyée contient alors le libellé explicitement choisi, et non une phrase pédagogique inventée.

### Interaction iPhone, iPad et sans GPS

**Carte dominante, bulle « Signaler » hors de toute zone défilante.** L’identité de l’élève, le statut réel du collecteur, le temps et les commandes GPS restent compacts. Objectifs détaillés, bilan et administration ne prennent pas la moitié de l’écran. Le déclencheur reste entièrement visible dans la zone sûre de la plus petite cellule qualifiée, y compris avec texte agrandi et en fenêtre partagée. La surface de carte et les informations secondaires cèdent avant une commande essentielle ; elles ne sont jamais protégées en réduisant artificiellement la police. La cible de 60 unités logiques du prototype est une proposition, pas une norme ni une preuve de sûreté.

**Signaler → thème → statut choisi.** L’ouverture affiche un panneau compact d’icônes et libellés, en ordre stable : priorité à droite, stationnement, signalisation, giratoire, observation, anticipation dans la fixture. Ce sont des exemples liés aux compétences disponibles pour la formation, pas un nouveau référentiel universel. Le statut n’est jamais présélectionné. Dans la variante proposée, les actions « Attention · enregistrer », « À retravailler · enregistrer » et « Point positif · enregistrer » annoncent explicitement qu’elles valident. Un commentaire n’est pas requis ; « Compléter l’observation » donne accès au détail ultérieurement. Une catégorie indisponible ne devient pas une compétence inventée : proposer le référentiel autorisé ou « Marquer un moment ».

**« Marquer un moment »** reste une alternative temporelle privée sans qualification. Elle ne publie ni erreur, ni note. **« Observations privées (n) »** ouvre les événements conservés ; chacun peut être relu, qualifié, retiré ou retrouvé dans le replay privé selon ses droits. Arrêter/pause/reprise GPS restent accessibles sans valider un formulaire. Arrêter le GPS ne termine pas la leçon. Aucun bouton photo live, aucune saisie obligatoire ni qualification de sûreté implicite par le nombre de gestes.

Le moniteur n’a pas à attendre la fin de la leçon pour identifier un thème et un statut ; la qualification détaillée s’effectue lors d’un arrêt adapté ou à la relecture. L’usage pendant le déplacement reste **NON QUALIFIÉ** : cette conception n’autorise pas à détourner l’attention de la supervision. La copie ne remplace pas une qualification d’usage. Le prototype se teste hors circulation.

Sur iPad, la composition dépend des classes de taille et de l’espace réellement disponible : carte et contexte côte à côte si la carte conserve sa largeur utile, panneau temporaire en largeur compacte ou hauteur contrainte. Split View, fenêtre redimensionnable et rotation ne recréent ni collecteur ni observation. Le panneau de signalement, l’instant figé, la sélection et l’exploration de carte restent stables.

E04 sans GPS offre la même qualification rapide, sans carte vide ni demande de permission. Le signalement conserve l’heure et affiche « Sans position ». Signaler ne démarre jamais une capture ; mettre en pause ou arrêter le GPS n’interdit pas les observations textuelles.

<a id="instant-signalement"></a>
### Instant figé, validation et annulation

| Transition | Comportement normatif proposé | Ce qui n’est pas créé |
|---|---|---|
| Appui « Signaler » | Mémoriser `observedAt` et, seulement si admissible, le triplet capture/segment/séquence du point déjà enregistré à cet instant. Conserver l’heure de mesure du point dans sa source. | Aucune `GeoObservation`, aucune commande serveur, aucune faute ni hausse du compteur. |
| Choix du thème, attente ou redimensionnement | Conserver le même instant et la même ancre candidate, même si de nouveaux points arrivent. | Aucun déplacement au prochain point ; aucune conversion implicite de catégorie en note. |
| Statut explicitement confirmé | Valider le contexte et les droits, écrire l’intention avec une clé stable, puis seulement accuser l’enregistrement local. | Aucune publication ni preuve de synchronisation serveur. |
| Annuler avant confirmation | Abandonner l’intention de formulaire, rendre le focus au déclencheur ; zéro appel métier et zéro repère parasite. | Pas de tombstone nécessaire pour un événement jamais enregistré. |
| Fermer/réouvrir pour reprendre un formulaire non confirmé | Reprendre l’instant d’origine seulement si l’utilisateur reprend explicitement cette intention ; sinon une nouvelle ouverture démarre un nouveau moment. | Pas de réutilisation silencieuse d’un ancien moment pour une nouvelle erreur. |
| Interruption du processus avant enregistrement | Ne pas prétendre qu’un formulaire seulement en mémoire a été conservé. Une éventuelle restauration chiffrée doit être spécifiée et testée séparément. | Pas de promesse de stockage durable depuis une ouverture de panneau. |
| Arrêt/refus/purge survenu avant confirmation | Invalider toute ancre devenue interdite. Conserver les champs autorisés, expliquer et faire confirmer l’enregistrement sans position ou abandonner. | Aucun envoi d’une ancre révoquée ni rattachement à une autre capture. |

Le temps de l’appui n’est pas une preuve certifiée de l’heure réelle de l’erreur. La qualification ne réécrit pas `observedAt` ; une correction explicite en revue utilise les mutations versionnées existantes et ne modifie pas la source mesurée ni une publication. Avant première mesure, pendant une lacune, en pause ou sans GPS : ancre nulle, jamais la dernière position en cache. Aucun géocodage ni mesure supplémentaire n’est déclenché par le panneau.

**Annuler après enregistrement** est une autre opération : avant remise au transport, une annulation locale doit être coordonnée avec l’outbox ; après émission ou résultat incertain, réconcilier l’opération puis retirer via AP164 si nécessaire. L’affichage « Retrait en attente » reste distinct de « Retirée ». Le prototype illustre seulement une suppression en mémoire, pas cette transaction.

<a id="mouvement-signalement"></a>
### Mouvement et retour d’état

L’ouverture du panneau vient du déclencheur ; la fermeture suit le mouvement inverse. Sélection de catégorie et apparition du repère ont un retour discret, sans rebond permanent, clignotement ni vol de marqueur sur toute la carte. Une animation n’attend jamais un réseau et ne bloque ni annulation ni arrêt GPS. Cibles de prototype : transitions de 160 à 240 ms, réglables après essais, sans engagement de performance native. En mode Réduire les animations, retirer translation/échelle et conserver le même contenu et un retour textuel. Aucun haptique n’est prétendu exécuté par le HTML.

L’accusé « Sur cet appareil · envoi en attente » exige une écriture durable réussie dans l’application. L’apparition du repère n’est pas une preuve de synchronisation. Le HTML emploie explicitement « Démo · conservé en mémoire » et ne réalise ni GPS ni persistance ni appel serveur. Les dessins sur la carte sont issus de fixtures en coordonnées de canevas, jamais de positions réelles.

**Sources et distinction :** le signalement Waze est une inspiration d’interaction, pas une API intégrée ni une preuve de sécurité du moniteur ; le choix de figer l’instant appartient à Drivy. Apple recommande adaptation à l’espace disponible et mouvement bref, facultatif et interruptible : [S135](../06-gouvernance/sources.md#s135), [S136](../06-gouvernance/sources.md#s136). Les mesures de la galerie ne qualifient pas UIKit/SwiftUI ni l’utilisation routière.

### Identité et cycle de vie de l’observation

Réutiliser **GeoObservation et AP161–AP164**, sans nouvelle entité ni route. Le nom historique reste valable pour une observation sans coordonnées. `schoolId`, `lessonId`, `trainingId` et l’auteur de session sont contrôlés au serveur. `origin=LIVE` identifie une saisie pendant la leçon ; `origin=REVIEW` une saisie de revue. `observedAt` est l’instant mémorisé, `eventKind` vaut `MARKER` ou `QUALIFIED`, `eventStatus` est nul pour un repère. L’auteur est fixé au serveur, jamais choisi dans la commande.

Avant constat, la leçon conserve son état métier `PLANNED` et l’observation a `draftId=null`. Aucun nouvel état de leçon, compte, résultat ou brouillon de bilan n’est créé par un tap. `CompleteLesson` reste l’unique constat : sous le même verrou de leçon, il crée le brouillon et rattache les observations actives de cet auteur/formation dont le draftId est nul. Leur version augmente ; les nouvelles versions sont relues avant sélection/publication. Une observation d’un autre auteur n’est pas adoptée implicitement.

Après constat, une commande LIVE tardive sans draftId peut rejoindre le brouillon initial **s’il est encore modifiable par le même auteur**. Si un bilan a déjà été publié ou si aucun brouillon admissible n’existe, répondre `409 OBSERVATION_REVIEW_REQUIRED` et conserver l’intention privée en attente de revue. Une correction explicite permet de choisir le nouveau brouillon, de conserver l’instant et de réémettre une nouvelle intention ; elle ne modifie jamais une publication existante. Sur `CANCELLED`/`NO_SHOW`, refuser la création avec `409 LESSON_STATE_CONFLICT`, sans réactiver la leçon ni effacer silencieusement le contenu local encore autorisé.

AP163 utilise `If-Match` sur la version de l’observation ; le passage du draftId nul au brouillon peut donc produire un 412 légitime. Relire et réconcilier, pas réémettre avec une version devinée. AP164 retire une observation privée selon les mêmes droits et conserve une tombstone sans coordonnées dans l’audit. Les opérations de retrait d’une publication demeurent séparées.

### Hors ligne, point absent et concurrence

L’intention est journalisée sous le compte/école/formation avec son operationId avant accusé visuel. La reprise conserve cette clé pour la **même charge utile**. Un changement de thème ou d’ancre constitue une nouvelle mutation versionnée, jamais la réutilisation de la même clé avec un contenu différent. Les leases, chiffrement, purge et révocations de F12 restent applicables ; aucune synchronisation cross-compte.

Une ancre est le triplet complet captureId/segmentId/pointSequence d’une mesure admissible **déjà enregistrée**, pas une nouvelle localisation demandée par le formulaire ni un point extrapolé. Au transfert : envoyer/acquitter les chunks requis avant l’observation ancrée. Si le point n’est pas encore disponible côté serveur, `409 ANCHOR_NOT_READY` laisse la commande en attente réessayable avec sa clé ; point définitivement rejeté ou supprimé : revue explicite et éventuelle conversion sans localisation, jamais déplacement sur une autre route. Ce refus transitoire n’est pas une opération commitée ; le même mécanisme de suivi/idempotence indique sa reprise possible.

Avant la première mesure, pendant une lacune, en pause GPS ou sans autorisation, créer une observation **sans ancre**. Aucun point zéro, ancienne position ou géométrie fictive. Ne pas l’ancrer rétroactivement au prochain point sans choix explicite. `observedAt` reste distinct de l’heure d’envoi ; sa précision est indicative et une correction d’horloge ne réécrit pas l’ordre segment/séquence d’une mesure. L’observation n’est pas une preuve certifiée d’heure, de présence ou de faute.

### Relecture, partage et suppression

E08/E24 présentent les observations existantes, distinguent « à qualifier », « non envoyée » et « privée », et permettent de corriger thème/statut avant publication. AP54 n’accepte un repère `MARKER` dans aucune sélection : retourner `422 OBSERVATION_NOT_QUALIFIED`. L’auteur peut le qualifier ou l’écarter. Toutes les sélections utilisent les versions actuelles ; le rattachement et les ajouts tardifs ne sélectionnent rien automatiquement.

Les champs thème/statut/instant relus sont copiés dans `PublishedGeoObservation` ou `PublishedTextObservation` selon l’ancre. Le snapshot textuel ne contient aucun identifiant de capture, de segment, de point ou de brouillon. L’élève ne voit ni la liste privée AP161, ni le compteur de repères, ni une progression déduite des brouillons. La suppression de géolocalisation couvre aussi les ancres des observations live ; le texte autorisé suit sa propre règle de conservation. Aucune rétention nouvelle n’est validée par cette révision.

**Recette :** [T423–T434](../05-realisation/tests-recette.md#t423) complètent [T407–T422](../05-realisation/tests-recette.md#t407), R15/R17/R46/R47, E04/E08/E23/E24, J12/J13, AP49/AP54/AP161–AP164. Ces scénarios restent NOT_EXECUTED sur l’application. La galerie HTML n’offre qu’une simulation en mémoire ; elle ne prouve ni la persistance native, ni les droits, ni la sécurité en conduite.

## F16 : exploitation pédagogique

Les observations prises pendant la leçon restent disponibles au bilan ; le moniteur n’a pas à les reconstruire de mémoire. Après arrêt, le replay présente la carte, la chronologie et les objectifs, avec la mention de qualité. Il peut parcourir un instant et créer une observation liée à un passage précis, ou écrire une observation sans localisation. Une compétence finale du bilan reste distincte de plusieurs observations situées sur cette compétence.

L’interface recadre l’ensemble au premier affichage. Déplacer/zoomer manuellement désactive le suivi de caméra sans mettre en pause la lecture ; un bouton « Recentrer » réactive explicitement le suivi. Les vitesses de lecture proposées x1, x2 et x4 concernent la chronologie réelle. Une pause d’enregistrement n’est pas une portion accélérée silencieusement.

Le moniteur choisit les observations destinées à l’élève. La publication du bilan peut inclure le trajet disponible avec sa qualité ou omettre le trajet encore en transfert. Il n’y a pas de publication ultérieure automatique d’annotations privées : ajouter un trajet ou de nouvelles notes requiert une révision explicite du bilan. Un élève ne voit jamais les traces d’un camarade.

Les cartes peuvent nécessiter des requêtes à un fournisseur ; fournisseur, conditions de stockage des tuiles et minimisation des données sont à qualifier. Sans fond de carte, conserver chronologie et observations textuelles ; ne pas prétendre offrir une carte hors ligne sous licence sans l’avoir validée.

## Données et validations

CaptureSession relie école, leçon, élève, moniteur, appareil, version d’information, choix enregistré et autorisation. Segment relie des mesures ordonnées. TrackChunk conserve hash et accusé durable ; GeoObservation appartient d’abord à la leçon et à son auteur. Son draftId peut être nul pendant la leçon ; la clôture la rattache au brouillon sans publication automatique. Une révision contient des snapshots relus, jamais une jointure publique sur une observation mutable. CapturePublication lie le trajet à une révision publiée. Les coordonnées ne sont jamais un attribut global du profil élève.

Les limites de coordonnées, points/chunk, durée d’autorisation et taille sont contrôlées par schéma et service. Les points arrivés tard peuvent compléter une capture arrêtée s’ils sont antérieurs au cutoff et acceptés dans la fenêtre de synchronisation ; la borne de trois heures limite **la collecte**, pas le temps disponible pour envoyer des points déjà collectés. Proposition : fenêtre d’envoi de sept jours, sous politique de conservation et droits courants, à valider avant pilote.

Un hash protège la déduplication technique, pas la véracité physique de la conduite. Le GPS d’un appareil n’est pas une preuve certifiée de conducteur, de présence ou de distance facturable.

## Confidentialité et effacement

La finalité est l’explication pédagogique. La conservation brute proposée de 30 jours constitue un point de départ à arbitrer, pas une obligation légale. Géométrie simplifiée, marqueurs et miniatures restent des données de localisation ; leur durée doit être justifiée séparément et ne peut être illimitée par défaut. Les droits F14 s’appliquent aux traces et aux données dérivées.

Une suppression retire les positions des caches et publications ; le bilan non géographique, le résultat de leçon et les écritures financières ne disparaissent pas automatiquement. L’audit garde la décision, pas une copie des positions. Un itinéraire réutilisable est créé séparément après revue ; le simple retrait du nom ne rend pas une trace anonyme.

## Acceptation et limites ouvertes

Les tests couvrent capture volontaire, refus, verrouillage, absence réseau, arrêt, terminaison, quotas, déduplication, arrivée hors ordre, permissions, publication et effacement. G0/G2 qualifient l’implémentation Swift sur iPhone et iPad. Le futur client Android passe ses propres essais à GA0 puis avant lancement. Une preuve obtenue sur Apple ne valide pas Android.

Aucun test de capture n’est exécuté par la rédaction de ce dossier. L’enregistrement entièrement hors ligne au départ, les transformations de trajets en bibliothèque partagée et le suivi individuel multi-appareils de groupe restent à cadrer après le pilote.


## Tablettes : support de premier rang, pas collecte navigateur

L’app native peut enregistrer depuis un **téléphone ou une tablette qualifiée du moniteur**. La cible de lancement proposée est iPhone/iPad plus web ; Android est prévu avec qualification distincte. Ce choix de séquencement est une recommandation liée aux ressources, pas un retrait du besoin tablette. La [matrice de plateformes](../02-experience/plateformes-tablette-web.md) précise chaque surface.

Sur tablette large : carte principale, objectifs et contrôles dans un panneau latéral ; au rétrécissement, passage en panneau repliable sans perte de séance ni redémarrage du collecteur. Pause/arrêt, statut réel et qualité du signal restent visibles. Les commentaires détaillés se saisissent à l’arrêt ou après ; le mode de présentation à l’élève utilise uniquement le bilan/trace publiés. Le replay et tous les autres modules s’adaptent également, pas seulement l’écran de conduite.

Un diagnostic appareil R83/R84 précède le premier usage et est invalidé par changement pertinent. Le GPS/GNSS documenté par Apple sur les modèles iPad Air Wi‑Fi + Cellular n’est pas une propriété de tout iPad [S48](../06-gouvernance/sources.md#s48). Le partage Internet ne prouve pas une transmission GPS et n’est pas une architecture de relais retenue. Sur appareil non qualifié, proposer la leçon sans capture ou préparer un autre appareil avant départ.

Le serveur lie l’autorisation à un deviceAssessmentId courant et applique une unicité par leçon, moniteur **et appareil**. Aucun basculement automatique lors d’une connexion sur un deuxième écran. Une captation en cours sur téléphone n’est pas magiquement consultable en direct sur une tablette : le live miroir reste hors pilote. L’onboarding explique ces différences sans exiger de permission GPS de l’élève pour consulter son historique.

**Recette appareil :** T192–T199 ; qualification technique avant qualification de l’intégration native et du matériel, matériel réel, paysage/portrait/fenêtrage, permissions, verrouillage, interruption système, batterie et réseau. Aucun test appareil n’est revendiqué ici.

## Publication figée et lectures séparées

La référence normative est [R47](regles-etats.md#r47). `CaptureSelection` est une commande de sélection, pas la réponse publiée : le client fournit la version de capture et la version de chaque observation effectivement revue. Le serveur vérifie ces versions sous transaction puis crée un `CapturePublication` immuable, lié à `reportRevisionId`, avec un `geometrySnapshotId`, la qualité à la publication et des copies des observations sélectionnées. Une modification concurrente produit `CAPTURE_REVIEW_CHANGED` sans publier un contenu non revu.

Le replay publié se lit avec `reportRevisionId` ; le curseur est lié à cette révision et au snapshot. Il ne retourne ni `draftId`, ni choix de consentement, ni identifiants d’appareil. Sans révision, seul le moniteur disposant du droit sur le brouillon accède à la reconstruction privée. La géométrie et les commentaires reçus après publication restent privés jusqu’à une nouvelle révision. Les retraits et effacements priment sur le snapshot : celui-ci n’est pas une copie de sauvegarde exemptée de purge.

Le pilote sélectionne au plus une capture par révision de bilan. Arrêter puis recommencer peut créer une nouvelle capture après réconciliation ; il n’y a pas de fusion implicite. Le moniteur choisit explicitement celle à publier, avec sa qualité. Une bibliothèque d’itinéraires reste une extension distincte.

### Trace longue

Une capture peut dépasser une page sans être tronquée ni convertie en plusieurs pauses artificielles. Le replay charge progressivement les points d’un même segment selon le protocole de [synchronisation](../04-technique/synchronisation.md). La pagination n’est pas une preuve de donnée manquante ; le lecteur garde la continuité logique et n’annonce une rupture que si les mesures la justifient.

<a id="replay-retire"></a>
## Révision publiée et projection retirée

Le snapshot est la preuve de ce qui a été publié, pas une permission permanente. La lecture utilise les projections de [R48](regles-etats.md#r48). Le statut WITHDRAWN ou DELETED peut conserver une métadonnée autorisée, mais jamais renvoyer les segments ou observations géographiques retirés dans le JSON. Le bilan textuel conserve seulement les éléments justifiés indépendamment.

Un retrait du partage n’accorde pas l’accès au trajet privé au lecteur du bilan. Les routes privées continuent à appliquer leur propre scope ; un utilisateur hors périmètre reçoit 404 plutôt qu’un indice sur l’existence de données. Les événements de retrait/purge invalident toutes les pages et dérivés locaux connus de cette capture.

Les indices de chunks d’un manifeste sont uniques. Au service, contrôler aussi l’unicité des segments, la continuité attendue, les sommes, horodatages et bornes autorisées. Rejeter un manifeste contradictoire ne transforme pas un trajet incomplet en trajet complet et ne change pas une ancienne publication.

<a id="profil-de-collecte-mobile-v34"></a>
## Profil de collecte native
La capture conserve exactement les règles et états ci-dessus. La [réalisation iOS native](../04-technique/integration-ios-ipados.md) précise le profil Core Location proposé, sans imposer Always par défaut ; la [préparation Android](../04-technique/preparation-android.md) distingue permission de fond, lancement visible du service et notifications. Les implémentations sont séparées, les invariants métier communs. Le [coordinateur Swift](../04-technique/architecture-client-swift.md#capture) ne dépend pas de l’écran carte.

Le collecteur et le stockage sont indépendants de la carte et des composants d’écran. Arrêt hors ligne, rotation, fermeture forcée et callbacks tardifs sont précisés dans [l’intégration transverse](../04-technique/integration-mobile-transverse.md). [PX01/PX02](../02-experience/patterns-mobile-parcours.md#px01) expliquent leur présentation sans fusionner collecte, transport et partage. Les nouvelles recettes MOB complètent les tests existants ; aucune n’est présentée comme exécutée.


<a id="consentement-et-préparation-précisions-v35"></a>
## Choix GPS et repères de préparation
[R101](regles-etats.md#r101) précise le conflit entre un refus SELF et une saisie du personnel. [R102](regles-etats.md#r102) sépare les repères manuels de préparation des positions enregistrées et des observations constatées. La purge de géodonnées inclut ces repères et leurs caches ; aucune position préparée ne complète un trou GPS. La collecte ne démarre pas automatiquement après un changement de consentement ou l’ouverture d’une notification.

## Absence de mesure et publication sans trace

Le manifeste vide est défini dans [R43](regles-etats.md#r43). Un arrêt avant le premier point conserve un constat honnête « Aucun point enregistré » ; il ne produit ni point zéro, ni tracé au lieu de départ supposé. Pause/reprise avant acquisition peut laisser un segment vide explicite. La réception de tous les éléments attendus (éventuellement aucun) décrit le transfert, pas la qualité pédagogique du trajet.

La sélection `textObservationSelection` du bilan fonctionne indépendamment du GPS selon [R46](regles-etats.md#r46). Les observations ancrées continuent d’utiliser le snapshot de capture. Le nombre total de références sélectionnées est borné à 100 ; unicité par ID et appartenance au brouillon sont contrôlées côté service, même si deux objets JSON portent des versions différentes. Cette clarification ne fusionne pas plusieurs captures et n’autorise pas un démarrage totalement hors ligne.

## Première position et vérité du trajet

[R111](regles-etats.md#r111) distingue l’heure de mesure de celle de réception. Au démarrage d’une nouvelle leçon, une position ancienne reçue en cache ne constitue pas le premier point du trajet. Tant qu’aucun point admissible n’est sauvegardé, l’écran indique « En attente de position », même si le système a livré un callback. Ne pas déplacer le départ vers la dernière position connue de l’élève précédent.

La réception en lot et l’envoi différé sont autorisés pour les points réellement mesurés dans le segment. Une absence de signal demeure une lacune ; les coordonnées par défaut, le recalage routier ou une ligne d’interpolation ne deviennent jamais des mesures originales. Les doublons et les changements d’horloge sont traités avant le manifeste, sans reconstruire un trajet idéal. Les seuils précis restent à qualifier sur appareils.

L’inspiration de signalement est documentée par [Waze S139](../06-gouvernance/sources.md#s139). Drivy s’en distingue volontairement : validation explicite sans temporisation d’envoi, observations privées et aucune communauté de signalements.
