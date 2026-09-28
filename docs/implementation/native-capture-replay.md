# Replay privé des trajets scolaires

`SchoolCaptureReplayView(model:workspace:)` présente le modèle `SchoolCaptureReplayWorkspace` de la racine. Il possède sa propre `NavigationStack`. Le chargement passe par AP160 et ne réutilise ni les trajets personnels, ni leurs exemples, ni un dessin de maquette.

Références relues : E24, R43/R45/R46/R47, F16 dans `gps-replay.md`, AP160, AS02/AS03/AS05/AS07. Les décisions de composition communes avec la séance et le replay personnel, ainsi que la recherche sur les sources officielles Uber/Apple, figurent dans `native-journey-design.md`.

## Composition et commandes

La carte occupe l’espace central. Le bandeau nomme l’élève et indique le caractère privé ; la partie basse regroupe l’observation sélectionnée, le temps, lecture/pause, précédent/suivant et ×1/×2/×4. Sur iPad large, ces commandes et la liste sont dans une colonne à gauche. Avec les tailles d’accessibilité, la page entière défile, sans réduire artificiellement les caractères.

Le curseur suit l’intervalle temporel disponible depuis l’autorisation de capture. La durée n’est pas présentée comme durée facturable de leçon. Les graduations des observations proviennent de `observedAt`, jamais de leur date de réception. Les lacunes entre portions apparaissent dans la chronologie. La lecture utilise une horloge monotone pour sa cadence ; ×1 correspond au temps de replay disponible, sans calculer une vitesse de conduite.

Sélectionner une observation conserve la vitesse et l’état de lecture. Le texte complet est accessible dans la liste ; celle-ci s’ouvre centrée sur la sélection. Précédent/suivant conservent les identifiants lorsque deux observations ont le même instant. Une observation sans heure ne reçoit pas d’heure inventée. Déplacer la carte suspend seulement son suivi automatique. « Suivre la position » et « Voir tout le trajet » sont deux commandes explicites.

## Géométrie et qualité

Chaque fragment fourni par le workspace dessine sa propre polyligne. Aucune jonction n’est créée entre deux fragments, même s’ils partagent le même segment serveur. Un fragment d’un seul point reste visible. La précision réduite est signalée par des pointillés et un texte, pas par la couleur seule.

Le repère de lecture correspond à une mesure réellement reçue, avec son heure affichée. Il n’est jamais interpolé ou recalé sur la route. Entre la dernière mesure d’un fragment et le début du suivant, aucun repère de position courante n’est dessiné. L’ancre d’une observation est recherchée par le triplet exact capture/segment/séquence ; une ancre indisponible n’est pas déplacée sur un passage voisin.

Les dates des mesures sont décodées une seule fois au fil des pages. La projection garde les fragments distincts et la recherche de la mesure à un instant utilise une recherche dichotomique, sans rebalayer les positions à chaque tick. Cela décrit l’algorithme, pas une qualification de performance sur appareil.

## Chargement et accès

Les portions peuvent être lues pendant le chargement des pages suivantes. En cas d’échec après une première page, le message « Chargement incomplet » reste visible avec la cause et une reprise explicite. `isComplete` atteste seulement la fin de lecture des pages : un trajet `PARTIAL` conserve toujours son avertissement, même après chargement terminé. L’absence de positions après une lecture confirmée n’est pas confondue avec une panne de lecture.

La présentation est réservée au scope courant du moniteur, en complément des droits contrôlés au serveur. Changer de compte, d’école, de membre ou d’epoch invalide le modèle, vide géométrie/sélection/feuilles et quitte la vue. Un refus serveur qui purge la capture retire aussi les anciennes positions de la présentation. Fermer explicitement la vue l’invalide ; le parent doit également l’invalider lors de la fermeture finale par geste. Ouvrir les feuilles Observations/Détails ne l’invalide pas. Le passage en arrière-plan ou la disparition de la vue met seulement la lecture en pause.

AP160 fournit actuellement les observations ancrées dans les pages de cette capture. La liste se nomme donc « Observations du trajet » : elle ne prétend pas couvrir toutes celles de la leçon. Les observations temporelles sans GPS restent accessibles depuis la leçon et le bilan. Aucun bouton de publication, de création de bilan ou de modification n’est ajouté sans raccord réel. Les noms de thèmes absents de ce DTO ne sont pas déduits d’un identifiant ou d’une couleur.

## Vérification

Relecture de l’interface du workspace et du client AP160, de ses gardes de pagination et des scénarios de zoom/replay ; contrôle de diff effectué. La compilation Apple groupée est gérée par la racine. Rendu de cette nouvelle vue sur iPhone/iPad, VoiceOver et trajet physique : **NOT_EXECUTED** à l’écriture de cette note. Les captures des anciens écrans ne qualifient pas ce nouvel écran ni sa performance.
