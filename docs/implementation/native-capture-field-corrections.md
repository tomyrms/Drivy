# Capture : retour terrain du 29 septembre 2026

Le porteur signale zéro position après environ 30 secondes sur iPhone et trop d’actions pour terminer la leçon. Ce retour ne permet pas d’identifier seul l’état du capteur ou de l’autorisation iOS. Aucun nouveau trajet physique n’a été effectué dans cette passe.

## Défauts confirmés dans le code

- `CLError.locationUnknown`, indisponibilité temporaire, arrêtait définitivement le collecteur. Le manager reste désormais actif et l’écran reçoit un diagnostic de recherche en cours. Les pertes d’autorisation, de précision, d’espace et les changements d’horloge restent des arrêts explicites avec leur cause.
- Le délai de 60 secondes sans callback arrêtait aussi définitivement la capture. Il devient un diagnostic ; une première acquisition lente reste possible. Une vraie lacune entre deux mesures sépare les segments, avec reprise locale sous le même bail valide. Elle ne traverse pas la carte avec une ligne inventée.
- Un filtre de déplacement de 3 mètres coexistait avec le rejet nécessaire des positions antérieures au début. Le filtre est supprimé (`kCLDistanceFilterNone`) afin de ne pas imposer un déplacement minimal à la prochaine mesure. Le cache reste interdit comme premier point de la nouvelle séance. Cela corrige un risque de démarrage immobile, sans établir que ce risque explique à lui seul le retour du porteur.
- La reprise d'un segment après une vraie lacune réappliquait la contrainte du premier départ au premier plan : écran verrouillé, elle aurait terminé le trajet. Une garde en mémoire reconnaît désormais la même capture déjà démarrée au premier plan et permet ses segments suivants si le bail, la portée et la politique d'arrière-plan restent valides. Premier départ en arrière-plan, autre capture, relance, expiration et changement de droits restent refusés.

Le collecteur et son `CLLocationManager` sont conservés fortement par le contrôleur racine. La préparation lui transfère la source avant l’attente asynchrone ; fermer la feuille ne reprend pas cette source. Les deux descriptions de permission et `UIBackgroundModes=location` sont présents dans `Info.plist`. Le modèle iPad est toujours le vrai `uname.machine`, avec `deviceClass=TABLET` ; une autorisation d’essai côté serveur ne vaut pas qualification physique.

Références : [R40 à R45](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md#r40), [R111](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md#r111), [Apple — démarrage des mises à jour](https://developer.apple.com/documentation/corelocation/cllocationmanager/startupdatinglocation()), [filtre de distance](https://developer.apple.com/documentation/corelocation/cllocationmanager/distancefilter), [position momentanément inconnue](https://developer.apple.com/documentation/corelocation/clerror-swift.struct/locationunknown). Les délais et la consommation restent à éprouver sur appareil.

## Fin de leçon en une action

`stopAndSynchronize()` et `finishForLesson(lessonID:)` rendent `true` seulement après arrêt du capteur et scellement SQLCipher. Une écriture locale impossible bloque la clôture et conserve son erreur. Le début réel du segment et l’arrêt relu dans la commande durable sont accessibles par `lessonTimes(lessonID:)` pour les heures de réalisation.

Le contrôleur lance ensuite arrêt serveur, lots et finalisation complète (`allowPartial=false`) dans une tâche détenue par l’app. `closeLessonFlow(lessonID:)` détache l’interface sans annuler cette tâche. Une perte de réponse conserve les octets et l’UUID ; `retrySynchronization()` reprend cette demande. Un refus explicite de version lors de la finalisation peut provenir de la clôture simultanée de la leçon : une relecture et une seule nouvelle tentative sont automatiques. Une erreur ne devient jamais une autorisation implicite de trajet partiel.

Après changement de compte ou de droits, les transmissions de l’ancien contexte sont invalidées. À l'ouverture du compte, au retour au premier plan et au retour du réseau (`NWPathMonitor`), la racine reprend automatiquement les captures scellées du journal chiffré dans la seule portée courante. Aucun collecteur GPS n'est redémarré par cette reprise. Une erreur demeure visible à la racine après la fermeture du bilan, avec une action pour réessayer. Aucun service iOS permanent de synchronisation après terminaison de l’app n’est revendiqué.

## Vérification

`SchoolCaptureLifecycleTests` utilise un vrai journal SQLCipher temporaire, des autorisations synthétiques signées et un transport contrôlé. Il couvre l’acquisition lente, l’attente sans point fictif, l’arrêt durable suivi d’une fermeture de l’écran, la réponse de finalisation perdue, le conflit avec la clôture de leçon, la reprise sans contexte GPS et le refus de reprise après déconnexion. Les tests ne déclenchent pas le GPS du simulateur. Compilation et exécution Apple sont prises dans la validation groupée ; ce document ne les déclare pas réussies avant le rapport.

Relecture statique et `git diff --check` réalisés. Restent à constater sur les appareils du porteur : première position, déplacement, immobilité, perte/reprise du signal, verrouillage, permission refusée/réduite, fin hors réseau, retour réseau, autonomie et VoiceOver.
