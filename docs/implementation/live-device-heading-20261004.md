# Orientation de la carte live — 4 octobre 2026

Le signalement utilisateur est confirmé dans la source : la carte live dérivait son cap exclusivement du déplacement entre les points GPS retenus. Tourner le téléphone à l’arrêt ne pouvait donc pas changer son orientation.

`SchoolLiveHeadingSource` écoute désormais le magnétomètre via Core Location, uniquement pour l’affichage de la carte live. Le cap vrai valide est prioritaire ; le cap magnétique est utilisé sinon. Aucun démarrage de collecte de positions, aucune permission supplémentaire, aucune écriture de point, d’observation ou de cap dans le stockage ou les contrats. `SchoolMapCourse`, le collecteur durable et le replay restent inchangés.

Le flux de cap est actif seulement lorsque la carte est visible, la scène active et le collecteur en état `recording`. Pause, arrêt, disparition, passage hors premier plan ou révocation système arrêtent ce flux et effacent son cap. Chaque reprise utilise un nouveau manager ; les callbacks d’un ancien manager sont ignorés.

Le filtre d’affichage accepte des angles finis dans `[0, 360[`, une incertitude entre 0 et 45°, et des mesures reçues âgées de 5 secondes au plus (tolérance d’horloge future : 1 seconde). Les callbacks antérieurs au démarrage ou hors ordre sont écartés. Le filtre matériel est de 2°. Ces valeurs sont des choix de présentation à qualifier sur appareil, pas des performances mesurées.

Le bord de référence est celui de la fenêtre UIKit contenant réellement la carte, via `UIWindowScene.effectiveGeometry.interfaceOrientation`. Les noms paysage UIKit sont inversés lors de leur conversion en `CLDeviceOrientation`. Aucun choix arbitraire de scène globale. Après un changement de référence, le callback encore exprimé dans l’ancien repère est ignoré.

Un cap valide oriente le marqueur ; il oriente aussi la caméra uniquement si le suivi est toujours activé et si la caméra n’a pas été manipulée. Un cap absent ou rejeté laisse le sens GPS déjà calculé servir de repli. Recentrer reste explicite après un geste manuel. Le centre reste une position déjà mesurée et retenue ; aucune coordonnée n’est interpolée.

Vérifications effectuées : lecture intégrale des trois fichiers modifiés, contrôle `git diff --check`, revue de l’absence de lien vers le stockage et de la garde du mode libre. Cinq tests Swift purs ajoutés : nord vrai à zéro, repli magnétique à l’arrêt, valeurs invalides/incertaines, ancienneté, références portrait/paysage. **Tests non exécutés et compilation Apple non lancée pour ce correctif**, conformément à la demande de limiter les campagnes.

Restent non qualifiés : rotation physique ouest/nord à l’arrêt, interférences du véhicule, qualité magnétique, passage 359°/0°, verrouillage de rotation, multi-fenêtre iPad, gestes simultanés, pause/reprise et retour de premier plan sur appareil, consommation et VoiceOver. Le simulateur ne fournit pas de magnétomètre. Les captures UI précédentes ne prouvent pas ce nouveau comportement.

Références lues : AGENTS, COMMENCER_ICI, GPS/replay, R44–R46, contrats AP154–AP164, scénarios MOB064–MOB065 ; skills SwiftUI UI Patterns, Write Swift et Impeccable (harden, iOS, craft floor). Documentation Apple : [cap et sens de déplacement](https://developer.apple.com/documentation/corelocation/getting-heading-and-course-information), [headingOrientation](https://developer.apple.com/documentation/corelocation/cllocationmanager/headingorientation), [headingAccuracy](https://developer.apple.com/documentation/corelocation/clheading/headingaccuracy), [géométrie effective de scène](https://developer.apple.com/documentation/uikit/uiwindowscene/effectivegeometry).
