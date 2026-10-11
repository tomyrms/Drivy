# GPS fluide, tracés fidèles et recalage routier — 11 octobre 2026

Demande du porteur : un suivi GPS stable et fluide pendant la leçon, des tracés qui ne s’entremêlent plus, un replay sans saccades, et le recalage des trajets sur la route par Mapbox Map Matching, sans jeton dans l’app.

Branche `claude/gps-fluide-mapbox-20261011`, à jour sur master après les PR #10 à #13.

## Ce qui est décidé ici

Ces points changent des règles écrites auparavant. Ils viennent de la demande du porteur du 11 octobre 2026.

1. **Interpolation d’affichage autorisée.** Le marqueur glisse entre deux positions mesurées, en direct comme en replay. `carte-replay-gps-20260930.md` et `live-device-heading-20261004.md` l’interdisaient. La règle « pas de position inventée » tient autrement : une position interpolée n’est jamais enregistrée, jamais envoyée, jamais utilisée comme ancre d’un signalement, et le marqueur va toujours vers une mesure réelle sans la dépasser.
2. **Un arrêt n’est plus une rupture.** Un feu rouge de plus de quinze secondes coupait le trait et faisait disparaître le curseur du replay. La position est maintenant tenue jusqu’au redémarrage.
3. **Une mesure écartée ne coupe plus le trait** si les deux mesures qui l’encadrent ont moins de quatre secondes d’écart. Au-delà, le trait est coupé comme avant. La mesure écartée n’est jamais dessinée.
4. **Recalage routier introduit**, comme couche distincte des mesures, côté serveur seulement.
5. **La leçon s’ouvre en suivi**, nord en haut. Elle s’ouvrait carte libre : il fallait toucher le bouton pour que la carte accompagne la voiture.

## Causes trouvées

L’audit a été mené par trois agents en lecture seule (GPS, carte et replay, serveur et Mapbox), puis recoupé à la main. Tout vient de la lecture du code ; rien n’a été profilé sur appareil.

### Saccades en direct

- Le marqueur sautait d’une position enregistrée à la suivante, environ une fois par seconde, sans transition. La caméra glissait 0,35 s puis restait immobile jusqu’au point suivant.
- À chaque position, tout le segment était refiltré, ses polylignes reconstruites et le cap recalculé depuis le départ, sur le fil principal : cinq à six passes sur tous les points, avec quatre allocations `CLLocation` par point. Le coût grandissait avec la durée de la leçon.
- Tout l’écran de leçon (barre, dock, commandes) était réévalué à chaque position, et la carte entière à chaque image d’une rotation.
- À basse vitesse, le filtre d’immobilité ne laissait passer qu’une position sur deux ou trois.
- La boussole relançait une animation de caméra tous les deux degrés.

### Saccades en replay

- La lecture avançait par pas de 100 ms et le curseur se posait sur le dernier point mesuré : un bond par seconde à vitesse normale.
- L’instant de lecture était un état de l’écran entier : chaque pas et chaque mouvement du doigt sur la chronologie réévaluaient tout.
- Le cap changeait par marches et faisait pivoter la carte par à-coups.
- Chaque page chargée reconstruisait la chronologie et mettait la lecture en pause.

### Tracés entremêlés

L’ordre des points n’est pas en cause : il est garanti à l’acquisition (lot trié, toute mesure plus ancienne que la dernière admise est jetée), à l’écriture (file sérielle, refus du coffre), au transfert (le serveur refuse tout désordre) et à l’affichage (tri sur la séquence durable).

La cause est le bruit du capteur, tracé avec des seuils trop larges :

- précision acceptée jusqu’à 35 m alors que le rayon d’immobilité plafonnait à 8 m : à l’arrêt, la dérive se dessinait en pelote ;
- le filtre de saut retranchait les deux précisions en entier : un écart d’environ 125 m en une seconde passait et se traçait en ligne droite ;
- aucune détection d’une mesure jetée de côté puis revenue.

## Architecture

Quatre couches, qui ne se mélangent pas.

| Couche | Où | Rôle |
|---|---|---|
| Mesures | coffre SQLCipher, `capture_chunk` | Chaque position admise, inchangée. Rien de ce chantier n’y touche. |
| Sélection | `SchoolCaptureDisplayRoute.Selector` (app), `selectTrack` (serveur) | Quelles mesures sont dessinées. Une mesure retenue est toujours une mesure, à sa place. |
| Recalage | `capture_matched_route` (serveur), `SchoolMatchedRoute` (app) | Entre deux mesures, la géométrie de la route probablement suivie. |
| Affichage | `SchoolMapGlide`, `SchoolReplayPath`, `DrivyRouteMapView` | Position du marqueur et de la caméra à chaque image. Jamais stockée. |

Responsabilités côté app :

- **Acquisition** : `SchoolCaptureLocationSource`, inchangée.
- **Validation et filtrage** : `SchoolCaptureDisplayRoute` et `SchoolTrackGeometry`.
- **Persistance** : `SQLCipherSchoolCaptureStore`, inchangée.
- **Construction du trajet** : `SchoolLiveTrace` en direct, `SchoolReplayTimeline` et `SchoolReplayPath` en replay.
- **Rendu** : `DrivyRouteMapView`, une seule carte pour le direct et le replay.
- **Animation** : `SchoolMapMotion` (glissement, lissage du cap, fondu de caméra), `SchoolLiveMapMotion`.
- **Lecture** : `SchoolReplayPlayer`.

### Sélection des mesures

Le filtre traite une mesure à la fois et garde son état : le coût par position est constant, quelle que soit la durée de la leçon. La version « tout le trajet d’un coup » passe par le même code.

- Précision au-delà de 30 m : écartée (35 m avant).
- Saut : vitesse impliquée au-delà de 50 m/s, en accordant au plus 20 m d’incertitude aux deux mesures.
- Immobilité : la position est tenue tant que la mesure reste dans le rayon d’incertitude (3 à 15 m selon la précision). Un véhicule qui roule déjà garde ses sommets s’il continue dans la même direction : un virage lent, une marche arrière ou une manœuvre de parking ne sont pas du bruit.
- Pic : une mesure à plus de 12 m de la ligne qui relie ses deux voisines, pour un détour au moins double du chemin direct, le tout en quatre secondes au plus, est retirée. Un demi-tour ou un angle droit ne remplissent pas ces conditions.
- Rupture : silence de plus de 15 s entre deux mesures reçues, séquence manquante, ou plus de 4 s sans mesure fiable.

Ces seuils sont des choix techniques à éprouver sur route.

### Carte et animation

`DrivyRouteMapView` enveloppe un `MKMapView`. SwiftUI `Map` ne permet ni de déplacer une annotation sans réévaluer la vue, ni d’ajouter des points à une polyligne, ni de maîtriser l’interpolation du cap.

- Un `CADisplayLink` (30 à 60 images par seconde) demande à chaque image la pose du marqueur et le cap de la caméra, puis les applique sans passer par SwiftUI. Il se met en pause dès que plus rien ne bouge, et quand la carte quitte l’écran.
- Le tracé en direct est découpé en polylignes de 200 sommets. Les tronçons clos ne sont plus touchés ; seul le dernier est remplacé à l’arrivée d’une position. Tous les halos sont sous tous les traits bleus, pour que deux tronçons se raccordent sans encoche.
- En direct, le marqueur part de l’endroit où il est dessiné et rejoint la dernière position enregistrée en un peu plus d’un intervalle entre deux positions. Une nouvelle position relance le mouvement depuis l’endroit courant : aucun retard ne s’accumule, et le marqueur a au plus une position de retard. Au-delà de 250 m, ou à l’ouverture d’un nouveau tronçon, il est posé, pas traîné.
- Le cap tourne par l’arc le plus court, à un rythme indépendant de la cadence d’images. 359° vers 1° est un quart de tour de 2°, jamais un tour complet.
- Recentrage et premier point : fondu de 0,6 s qui converge sur la cible en mouvement.
- Un geste sur la carte libère le suivi, comme avant. Le zoom choisi à la main est repris au recentrage.
- Réduire les animations : le marqueur et la caméra se posent sans mouvement, comme avant.

L’écran de leçon ne lit plus les segments : seule la carte est redessinée à l’arrivée d’une position.

### Replay

- `SchoolReplayPath` prépare une fois, par tronçon dessiné, la ligne et son horaire. La position à un instant demande deux recherches dichotomiques, quelle que soit la longueur du trajet.
- `SchoolReplayPlayer` tient une seule base de temps. La carte calcule l’instant exact à chaque image ; l’instant observé par la chronologie n’est publié que douze fois par seconde, ce qui suffit au pouce et à l’horloge.
- Déplacer la chronologie pose la carte sur la position correspondante à l’image suivante, lecture en cours ou non.
- Vitesses ×1, ×2, ×4 ; pause et reprise sans dérive ; la lecture n’est plus interrompue par l’arrivée d’une page.
- Seuls le lecteur et la carte suivent la tête de lecture ; le reste de l’écran n’est plus réévalué.
- Une lacune reste vide pour la position interpolée comme pour la position mesurée.

## Recalage routier

### Choix d’architecture

Le recalage se fait **sur le serveur, après la leçon, à la première lecture du trajet**.

- Pas pendant la leçon : il faudrait du réseau en voiture, des appels en continu, et un tracé qui se corrige sous les yeux. Le direct affiche les mesures filtrées.
- Pas dans l’app : le jeton y serait extractible. Aucun jeton n’est dans l’app.
- Pas dans un worker séparé : il aurait fallu un rôle PostgreSQL, un secret et un service de plus sur le homelab. Le calcul part de la requête d’un compte qui a le droit de lire le trajet, lit les mesures avec ses droits, puis tourne hors transaction dans le processus de l’API. Seuls les trajets réellement consultés sont recalés.

### Route

`GET /v1/schools/{schoolId}/captures/{captureId}/matched-route`, extension décrite par `apps/api/contracts/matched-route.json`. Le contrat canonique 3.11.0 et `GET …/replay` ne changent pas : un client qui ignore cette route fonctionne comme avant.

- `READY` : tronçons recalés (la liste peut être vide).
- `PENDING` : calcul en cours. L’app relit toutes les trois secondes, cinq fois au plus, puis laisse le trajet mesuré.
- `UNAVAILABLE` : rien à proposer.
- Mêmes droits que le replay privé, par la RLS de `capture_session`.

### Calcul

`apps/api/src/track-matching.ts`, sans réseau ni base :

1. Les mesures sont triées par séquence et passent par le même filtre que l’app (`selectTrack`, copie de `Selector`). Les deux doivent évoluer ensemble.
2. Chaque suite continue est recalée séparément : aucun tronçon ne traverse une lacune.
3. Le moteur reçoit les extrémités, les arrêts et un point tous les vingt mètres au moins, par lots de cent (limite de l’API) qui se recouvrent de dix points. Chaque lot n’est retenu que loin de ses bords.
4. Un tronçon n’est gardé que si le moteur a placé le point, à moins de dix mètres au-delà du rayon de recherche de sa mesure, avec une confiance d’au moins 0,5 (`MAP_MATCHING_MIN_CONFIDENCE`). Sinon il s’arrête avant ce point et la mesure reste tracée : un parking, une cour privée ou une manœuvre ne sont jamais forcés sur une route.
5. Chaque tronçon porte sa géométrie et, pour chaque mesure placée, sa distance le long de cette géométrie. L’app en tire l’horaire du curseur.

`apps/api/src/map-matching-client.ts` est le seul fichier propre au fournisseur. Deux moteurs parlent le même format : Mapbox Map Matching, et un OSRM auto-hébergé.

### Persistance

Migration `024_matched_route.sql`, table `drivy.capture_matched_route` : une ligne par trajet, contenu chiffré avec la clé des captures (AES-256-GCM, données associées liées au trajet, à la version des mesures et à celle de l’algorithme).

- Le résultat est lié à `reconstruction_version`. Une borne resserrée, un retrait ou une suppression le détruit dans la même transaction.
- Un bail de trois minutes réserve le calcul ; deux lectures simultanées ne lancent qu’un calcul ; un calcul abandonné est repris à l’expiration du bail.
- Échec : seul un code est conservé (`RATE_LIMITED`, `PROVIDER_UNAVAILABLE`, `PROVIDER_REFUSED`, `INVALID_RESPONSE`). Nouvel essai après 1, 4, 9, 16 minutes, puis une journée.
- Ni URL, ni coordonnée, ni réponse du moteur dans les journaux.

### Dans l’app

`SchoolReplayTimeline` pose la géométrie d’un tronçon à la place des mesures qu’il couvre et garde les mesures partout ailleurs. Un tronçon incohérent (séquence inconnue, géométrie illisible, plage qui déborde d’un tronçon dessiné) est ignoré en entier. Les mesures affichées (`samples`) ne changent jamais.

### Configuration

Sans ces variables, rien n’est calculé et rien n’est envoyé à un tiers.

| Variable | Valeur |
|---|---|
| `MAP_MATCHING_PROVIDER` | `mapbox` ou `osrm` |
| `MAP_MATCHING_ACCESS_TOKEN` | jeton Mapbox, requis pour `mapbox` |
| `MAP_MATCHING_BASE_URL` | requis pour `osrm` ; `https://api.mapbox.com` par défaut pour `mapbox` |
| `MAP_MATCHING_MIN_CONFIDENCE` | 0,5 par défaut |
| `MAP_MATCHING_TIMEOUT_MS` | 10 000 par défaut |

À poser dans `/etc/drivy-refonte/api.env` sur le homelab, après sauvegarde de la base et application de la migration 024. Le jeton collé par le porteur le 11 octobre est rangé dans `.local/acces/map-matching.env`, hors dépôt.

### Activé avec Mapbox le 11 octobre 2026, points restant ouverts

À la demande du porteur, la release `de2f331` est déployée sur le homelab et le recalage y est activé avec Mapbox. Trois points restent à sa charge, pour trois raisons relevées dans les textes de Mapbox et dans le dossier de conception. Elles sont rapportées par l’audit ; les conditions de Mapbox sont à relire à la source avant de s’engager.

1. **Conditions d’utilisation de Mapbox.** La page de l’API indique que les résultats doivent être affichés sur une carte Mapbox ; les conditions produit interdisent de stocker les résultats d’une API de navigation et de l’interroger par traitement automatique. Drivy affiche sur MapKit et conserve le résultat. Sans accord écrit de Mapbox, cet usage n’est pas conforme.
2. **Nouveau destinataire de données.** Les positions de l’élève partent chez un tiers, hors de Suisse. Le dossier de conception demande de le documenter et de le montrer dans la notice ; une nouvelle version de notice révoque les captures en cours.
3. **Alternative sans tiers.** Un OSRM auto-hébergé sur le homelab, avec l’extrait OpenStreetMap de la Suisse, répond au même format : `MAP_MATCHING_PROVIDER=osrm`. Aucune position ne quitte l’hébergement, aucune condition commerciale ne s’applique. Il reste à l’installer.

## Vérifications

Les résultats ci-dessous sont ceux qui ont été réellement obtenus. Rien n’a été mesuré sur appareil.

| Vérification | Résultat |
|---|---|
| Filtrage, lots et assemblage des tronçons (TypeScript, en local) | 27 tests passent : ville, autoroute, rond-point, demi-tour, marche arrière, parking, arrêt au feu, perte de signal, point aberrant, pic latéral, longue zone brouillée, trajet long en plusieurs lots, faible confiance, zone non couverte, panne du moteur. |
| API sur PostgreSQL réelle (CI, `38170281258`) | 311 tests passent, dont 9 nouveaux : un seul calcul pour deux lectures simultanées, résultat chiffré au repos, replay inchangé, droits (autre moniteur, autre école, élève avant et après partage, administration), moteur en panne puis nouvel essai, reprise après bail expiré, purge par borne resserrée et par retrait, recalage non configuré. |
| Client du moteur contre l’API Mapbox réelle (en local) | Une requête sur une ligne synthétique le long d’une avenue publique : réponse en 309 ms, un tronçon retenu à 0,963 de confiance ; la partie de la ligne qui traversait le bâti n’a pas été recalée. Aucune donnée de personne. |
| Compilation de l’app (CI, `38170281260`) | IPA d’essai compilée sur la branche fusionnée avec master, sans avertissement du compilateur Swift. |
| Tests Swift (CI) | Avant la fusion de master (`38169304033`) : 479 tests passent. Après (`38170285836`) : 482 tests passent. Les nouveaux couvrent le filtre une mesure à la fois, l’arrêt, les pics, les manœuvres, le tracé en tronçons, le glissement du marqueur, le cap par l’arc court, l’interpolation du replay, la lacune, un replay de 6 000 points, la couche recalée et le lecteur. |

Trois tests existants ont changé parce que le comportement change (points 2 et 3 des décisions) : `isolatedJump…` dans `SchoolMapCourseTests`, deux tests de `SchoolMapRouteGapTests`, et l’aperçu de leçon dans `SchoolCaptureInteropTests`. Deux tests serveur comptent les tables sous RLS : 45 devient 46. Un test serveur échouait environ une fois sur cent parce qu’il cherchait « 22 » suivi de trois chiffres dans une réponse qui contient un identifiant aléatoire ; il ignore maintenant cet identifiant.

**Non exécuté** : les parcours UI (XCUITest) sur iPhone et iPad, et tout essai sur appareil.

### Ce qui n’est pas vérifié

- **Aucune mesure de performance.** Pas d’Instruments, pas de compteur d’images : cette machine n’a pas de chaîne Swift et le simulateur de la CI ne qualifie ni la fluidité ni le GPS. Les 60 images par seconde sont un objectif de conception, pas un résultat.
- **Rien n’a été vu tourner** : ni la carte, ni le glissement du marqueur, ni le replay.
- **Position du marqueur sous les panneaux.** La carte s’étend sous la barre et le dock ; le centrage du suivi compte sur les marges de `MKMapView`. Si le marqueur apparaît trop bas, c’est là qu’il faut regarder.
- **Trajets réels** : ville, autoroute, rond-point, demi-tour, marche arrière, parking, tunnel. Ils sont couverts par des tests sur traces synthétiques, pas par des trajets enregistrés.
- **Seuils du filtre** : à éprouver sur route.
- **VoiceOver** sur les marqueurs de la nouvelle carte.

## Limites

- Les signalements pris à l’arrêt restent sans position, comme avant : l’ancre exige que la dernière mesure soit affichée.
- Le replay se charge toujours par pages de cent points, chacune redéchiffrant tout le trajet côté serveur : une heure de leçon demande une trentaine de requêtes avant l’affichage complet. Le contrat canonique fixe cette limite.
- L’aperçu du trajet dans le bilan de leçon dessine les mesures filtrées, pas le tracé recalé.
- Le tracé recalé arrive quelques secondes après la première ouverture d’un replay ; les suivantes l’affichent d’emblée.
- Au-delà de 80 lots (environ 8 000 points confiés au moteur), la fin du trajet reste tracée par ses mesures.
- Le web ne montre pas encore la couche recalée.
