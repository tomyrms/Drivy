# Source scolaire Core Location

`SchoolCaptureLocationSource` est l'adaptateur natif injecté derrière `SchoolCaptureLocationProviding`. Il possède ses propres `CLLocationManager`, distincts du laboratoire G0, et ne dépend ni de `RecordedPoint`, ni de `DrivingSession`, ni d'`EXAMPLE`. Il ne fait aucun appel HTTP et n'écrit pas directement des points. La composition applicative doit conserver ce service au-delà de la durée de vie d'une feuille SwiftUI.

Références conservées : [R111](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md#r111), [GPS/replay](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/gps-replay.md), [architecture Swift](../../Drivy_Conception_v3_17_2026-09-20/04-technique/architecture-client-swift.md#capture), [profil Apple](../../Drivy_Conception_v3_17_2026-09-20/04-technique/integration-ios-ipados.md), [journal local](native-capture-storage.md) et [serveur](g2-capture.md). Cette tranche ne modifie pas le canon.

## Diagnostic explicite

`requestPermission()` demande seulement When In Use, et seulement si l'état est indéterminé. Ouvrir un replay, construire le service ou changer d'écran ne demande rien. Un refus garde la voie sans GPS.

`requestDiagnosticSample()` est une demande ponctuelle explicite au premier plan. La mesure reste en mémoire pour son âge et sa précision ; elle ne devient jamais le premier point d'une future leçon. Pendant une capture, cette méthode utilise les dernières métadonnées reçues au lieu de lancer une seconde source. `diagnosticSnapshot()` indique permission réellement accordée, précision complète/réduite, modèle `uname`, classe téléphone/tablette, version iOS, build, âge de mesure et précision disponibles. Une absence de point ou une valeur non exploitable reste `nil`. Le réseau est fourni par l'appelant à partir de son état connu ; une permission GPS ne prouve pas une connexion.

Le diagnostic ne déclare jamais l'appareil qualifié. AP190 et le profil serveur restent nécessaires ; les profils hébergés ne sont pas créés par ce module. Une source annoncée comme simulée ou issue d'un accessoire est exclue de cette tranche, qui n'a pas de qualification de relais matériel. L'absence d'un indicateur Apple de simulation n'est pas une attestation d'authenticité.

## Espace disque : contrôle local et extension AP190 iOS

Le contrôle local utilise `volumeAvailableCapacity` pour refuser le départ puis arrêter la source si le seuil n'est plus atteint. Le manifeste déclare `NSPrivacyAccessedAPICategoryDiskSpace` avec **E174.1**. Apple permet cette lecture pour éviter des écritures sans espace suffisant, mais interdit d'envoyer hors appareil cette information ou une information dérivée, hors exception concernant les téléchargements. [Référence Apple](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

En conséquence, `diagnosticBody(operationID:networkAvailable:)` encode **`freeBytes:null` sur iOS**, jamais le nombre local, un seuil atteint ou un résultat dérivé. `SchoolCaptureDeviceSnapshot.availableBytesLocally` reste en mémoire locale et n'est pas `Codable`. Le contrat d'implémentation AP190 accepte ce null pour iOS ; Android conserve son champ numérique. Le serveur ne prétend pas avoir contrôlé le disque iOS. Cette extension est volontairement documentée hors du contrat canonique immuable, plutôt que d'inventer une capacité ou de détourner un motif de rapport de bug.

Valeur technique initiale : **256 Mio** disponibles au départ ; recontrôle au plus toutes les dix secondes de callbacks. Une impossibilité de lire l'espace produit le même arrêt prudent, avec état visible à fournir par la composition. Ce seuil doit être mesuré avec la taille réelle du journal et les appareils de qualification ; il ne garantit pas l'absence de saturation concurrente. Le journal arrête aussi la collecte si une écriture échoue.

## Raccord au journal et au réseau

1. Conserver une source et appeler `updateScope(scope)` pour le contexte scolaire courant.
2. Après AP154 contrôlé, construire `SchoolCaptureClockReference(serverTime:response.serverTime, receivedAt:receivedAt)`. `receivedAt` est le temps monotone relevé dès réception, avant l'écriture SQLCipher. Il reste distinct du début de requête utilisé pour limiter le bail.
3. Persister l'autorisation via le journal et son bail vérifié. `prepareSegment(authorization:lease:scope:clockReference:policy:)` prépare ensuite un contexte éphémère et `startedAt`.
4. Attendre `SchoolCaptureLocalCoordinator.begin(captureID:startedAt:reason:)` avec ce même `startedAt`. Revalider la génération de la composition après l'attente, puis appeler `source.start(segment:handle:)` au premier plan.
5. Sur `.measurements(handle, values)`, mettre synchroniquement les valeurs dans `coordinator.enqueue` ; ne présenter « enregistré » qu'après son résultat durable. Une erreur ferme la source et conserve un état incomplet.
6. Sur `.interrupted(reason, stop)`, la source est déjà arrêtée. Sceller avec `coordinator.pause` ou `coordinator.stop` et les champs `stop.handle`/`stop.stoppedAt`. Les raisons signal/perte de flux permettent une pause ; permission, portée, expiration, horloge et stockage imposent un arrêt prudent. Aucun événement ne reprend de lui-même une collecte.
7. Une action d'arrêt appelle `source.stop()` **synchroniquement**, puis le coordinateur scelle la frontière retournée. Un changement de compte/droits appelle d'abord `updateScope(nil)` ou le nouveau scope. Le réseau peut continuer uniquement selon ses propres droits.

Le protocole permet d'injecter un double de source dans une recette. Il n'existe aucun double activé dans le produit. Un contexte préparé est consommé au premier départ et invalidé à l'arrêt ou au changement de scope. Il ne peut pas rouvrir un ancien segment après navigation.

Répéter `stop()` conserve la frontière du dernier arrêt jusqu'à une nouvelle préparation ; l'intégration peut ainsi la retrouver si une première fermeture de sécurité avait déjà coupé le matériel. Si le départ système échoue après `begin` durable, aucun point n'a été reçu : l'appelant doit sceller ce segment vide avec le mapping de son contexte préparé, plutôt que relancer silencieusement le départ.

## Temps, qualité et ruptures

Apple distingue l'heure à laquelle la localisation a été déterminée de la livraison des callbacks, lesquels peuvent contenir plusieurs mesures ordonnées. La source conserve cette distinction : le temps de mesure est converti par le mapping fixé au début du segment, pas par la date d'upload. [Timestamp Apple](https://developer.apple.com/documentation/corelocation/cllocation/timestamp), [livraison en lot](https://developer.apple.com/documentation/corelocation/cllocationmanagerdelegate/locationmanager(_:didupdatelocations:)).

Le mapping associe la référence serveur, le temps monotone de réception et l'horloge civile observée au début du segment. Les différences de temps de mesure sont conservées, à la milliseconde du contrat. Ce mapping n'est pas une certification absolue de l'horloge du capteur et ne supprime pas l'incertitude réseau. Il ne se persiste pas pour relancer une source après fermeture.

Une mesure en cache antérieure à l'armement effectif, future, non finie, de précision négative, dupliquée ou déjà hors bail est ignorée. Les valeurs `(0,0)` restent valides si elles sont réellement fournies par la source ; aucune sentinelle n'est créée. Une précision médiocre mais valide reste conservée dans `accuracyMeters` pour rendre la qualité visible, sans la remplacer par zéro. Le diagnostic serveur peut la juger insuffisante avant départ.

Paramètres techniques initiaux de `SchoolCaptureLocationPolicy()` : callbacks de 120 secondes au plus, dérive horloge civile/monotone de 1 seconde au plus, rupture après 60 secondes sans mesure admissible, filtre de distance de 3 mètres, précision complète requise. Ces valeurs sont des candidats à mesurer, pas des résultats physiques. Une rupture trop longue détectée à l'intérieur d'un batch ferme le segment avant la mesure qui la franchit ; aucune ligne continue artificielle n'est produite. Un saut d'horloge produit un arrêt, sans réécrire les temps pour préserver une continuité supposée.

Le bail est contrôlé avant ouverture, à chaque callback et par une minuterie sur sa `collectionDeadline` monotone. La source invalide manager, segment et tâches avant d'appeler `stopUpdatingLocation` puis avant de publier son événement. Les callbacks d'un ancien manager ne franchissent plus la barrière. Le compteur d'écarts techniques ne contient aucune coordonnée et n'est pas journalisé.

Le mode de fond n'est activé qu'après départ explicite au premier plan et vérification de `UIBackgroundModes=location`. Il conserve l'indicateur système. Une suspension ou fermeture forcée ne permet pas de promettre que le code d'arrêt s'exécute physiquement à l'échéance ; après reprise, aucun callback ne franchit un bail expiré et le journal scelle l'interruption. [Référence Apple pour le fond](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates). Aucun Always n'est demandé automatiquement.

## Vérifications et limites

Relecture statique ciblée et manifeste plist contrôlé le 24 septembre 2026. Compilation Apple et recette physique de cette source **NOT_EXECUTED** à la rédaction de cette note ; elles seront distinguées du résultat déjà acquis pour l'IPA précédent. Pas de campagne générale lancée.

Le raccord à une composition applicative stable, le traitement visible des interruptions, les revocations/retours Réglages, les interruptions réseau et la qualification iPhone/iPad sous verrouillage restent nécessaires avant de déclarer la collecte scolaire utilisable. La présence du code, la réussite d'un build ou le fonctionnement de G0 ne qualifient pas le profil scolaire.
