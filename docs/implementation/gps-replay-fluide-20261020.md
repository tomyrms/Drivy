# GPS en direct et replay fluides — 20 octobre 2026

Demande du porteur : un replay et un suivi GPS aussi fluides que Waze, Plans ou Google Maps. « Oublie la règle de jamais en avance », collage à la route via Mapbox, replay qui suit la direction même en ×5 et ×10, fonctionnement sans réseau avec reprise du bon chemin au retour de la connexion.

Branche `claude/gps-replay-fluide-20261020`, depuis `origin/master`.

## Ce qui est décidé ici

1. **Le marqueur en direct peut être en avance sur la dernière mesure.** Il est prédit à partir de la vitesse et du cap Doppler fournis par iOS avec chaque mesure (navigation à l’estime), au plus 1,6 s au-delà de la dernière mesure, puis il attend. Cela remplace la règle « le marqueur va vers une mesure sans la dépasser » de `gps-fluide-recalage-20261011.md` § 1. La règle « pas de position inventée » tient pour tout ce qui est durable : une position prédite n’est jamais enregistrée, envoyée, ni utilisée comme ancre ; le tracé reste fait de mesures.
2. **Le mode direction suit le cap de route en roulant.** La boussole, perturbée par la carrosserie, n’oriente la carte qu’à l’arrêt. Libellé : « Suivi dans le sens du trajet ».
3. **Le replay tire son horaire de toutes les mesures**, plus seulement des sommets que le filtre d’affichage garde. Le tracé dessiné ne change pas.

## Mesure sur la leçon réelle

Leçon du 20 octobre avec Dania (`989f9a3d…`), lue sur le homelab en transaction `READ ONLY`. Les points ont été déchiffrés dans le conteneur de l’API ; seules des statistiques en sont sorties, aucune coordonnée ni aucun nom.

| Fait | Valeur |
|---|---|
| Mesures | 1 058, une par seconde, aucune lacune, précision médiane 3,5 m |
| Vitesse | médiane 0,7 m/s, 30 % du temps à l’arrêt : leçon lente (manœuvres) |
| Sommets retenus par le filtre d’affichage | 151 sur 1 058 (14 %) |
| Marqueur figé sur un sommet | médiane 4 s, 90 % jusqu’à 8 s, 146 fois plus de 2 s |
| Puis | saut d’environ 3,8 m en 1 s |

**Cause principale** : le filtre d’affichage tient un véhicule lent sur le même sommet tant que ses mesures restent dans le rayon d’incertitude (3 à 15 m). Il est fait pour le tracé, mais il pilotait aussi l’horaire du curseur et le marqueur en direct. À basse vitesse, le marqueur s’arrêtait plusieurs secondes puis bondissait. Les autres causes (vitesse qui change d’un coup à chaque point, flèche et caméra orientées sur le petit segment courant, lissage divisé par la vitesse de lecture, 60 Hz au plus) aggravaient l’effet.

## Replay

`SchoolReplayPath.refineTimetable` :

- Les nœuds connus de l’horaire (sommets dessinés, ancres du recalage routier, extrémités) restent tels quels.
- Entre deux nœuds, chaque mesure est projetée sur le tracé, sans sortir de ce tronçon : une boucle ou une rue prise deux fois ne happe pas une mesure sur le mauvais passage.
- Un arrêt réel (aucune progression entre le premier et le dernier tiers des mesures) garde le véhicule sur son sommet, comme avant.
- Un mouvement lent est nettoyé par une médiane sur cinq, une régression isotone (jamais de recul) et une moyenne sur cinq.

`SchoolReplayPath.meters(at:)` : la distance suit une cubique monotone (tangentes de Fritsch-Butland). La vitesse varie sans à-coup d’un point à l’autre, ne recule jamais et chaque mesure est atteinte exactement à son instant. Un mouvement régulier reste exactement linéaire.

Direction : la flèche vise 8 m plus loin sur le tracé, la caméra 22 m (× √vitesse de lecture). Les lissages ne sont plus divisés par la vitesse mais par sa racine : à ×10, la caméra tourne encore avec la route sans à-coup.

Résultat sur la leçon réelle (même calcul en JavaScript, sur la même sélection que l’app, image par image à 60 Hz) :

| | Avant | Après |
|---|---|---|
| Temps total où le curseur est figé | 906 s | 287 s (arrêts réels uniquement) |
| Arrêts de plus d’une seconde | 147 | 17 |
| Écart médian entre curseur et mesure à l’instant de la mesure | 1,7 m | 0,4 m |
| Accélération du curseur, 99e centile | sauts de plusieurs centaines de m/s² par point | 5 m/s² |

Trajet court du 19 octobre (`fe28ac17…`, 116 mesures, en mouvement continu) : de 24 arrêts de plus d’une seconde à aucun.

## Direct

- `SchoolCaptureMeasurement` porte la vitesse et le cap Doppler d’iOS, quand iOS les juge fiables (`speedAccuracy`, `courseAccuracy`). Ils ne sont ni stockés ni envoyés : le schéma du coffre, les lots et le contrat ne changent pas.
- `SchoolCaptureMapSegment.liveFix` : la dernière mesure admise (précision ≤ 30 m), avant le filtre d’affichage. Le marqueur la suit à chaque mesure.
- `SchoolMapPredictor` : position = mesure + vitesse × temps écoulé (au plus 1,6 s), plus une correction qui s’efface en 0,45 s. Une nouvelle mesure ne fait jamais sauter le marqueur : il part d’où il est dessiné. En dessous de 0,6 m/s, le véhicule est tenu pour arrêté et le bruit ne fait pas ramper le marqueur. Au-delà de 80 m d’écart, il est posé. Le délai d’écriture dans le coffre (quelques dizaines de millisecondes) n’est pas rattrapé : l’heure d’une mesure est sur l’horloge de l’école, et la comparer à l’horloge du téléphone projetterait le marqueur trop loin dès que les deux divergent.
- Réduire les animations : pas de prédiction, le marqueur se pose sur chaque mesure.

Rejeu sur les leçons réelles, image par image à 60 Hz, chaque mesure livrée à la carte 0,1 s après sa prise. La vitesse Doppler n’étant pas conservée, elle est estimée à partir des deux mesures précédentes, plus bruitée que celle d’iOS. Référence : la position interpolée entre mesures brutes.

| | Ancien marqueur | Nouveau marqueur |
|---|---|---|
| Leçon du 20 octobre : écart à la position, médiane / 99e centile | 2,6 m / 7,5 m | 0,25 m / 1,3 m |
| Leçon du 20 octobre : arrêts de plus d’une seconde | 146 | 14 |
| Trajet du 19 octobre : écart, médiane / 99e centile | 3,1 m / 5,7 m | 0,34 m / 1,5 m |
| Trajet du 19 octobre : arrêts de plus d’une seconde | 24 | 1 |

## Exigences et preuves

| Demande | Vérification | Résultat observé |
|---|---|---|
| Replay sans saccade | Rejeu image par image sur la leçon réelle ; test `aSlowVehicleRollsSteadily…` | Arrêts > 1 s : 147 → 17 (arrêts réels) ; aucun recul |
| Vitesse continue, mesures respectées | Test `theSpeedChangesSmoothly…` ; rejeu réel | Écart de vitesse au point < 1 m/s ; écart curseur/mesure médian 1,7 → 0,4 m |
| Suivre la direction en ×5/×10 | Test `theArrowLooksAhead…` (zigzag, bords compris) | Flèche à 3,5° au plus de la route au lieu de 18° ; lissage caméra non mesuré en image |
| Direct en avance, sans saut | Tests `theLiveMarkerRollsOn…`, `aNewFixCorrects…` ; rejeu réel | Voir tableau ci-dessus |
| Comportements existants (arrêt au feu, lacune, recalage routier, 6 000 points) | Tests existants inchangés | Passent (CI) |
| Hors connexion | Aucun changement du stockage ni de l’envoi | Non retesté : comportement antérieur |
| Collage à la route en direct | — | Non fait, décision du porteur |
| Fluidité réelle sur iPhone, 120 Hz | — | Non vérifiable ici : essai du porteur avec l’IPA |

## Carte

`CADisplayLink` jusqu’à 120 Hz et `CADisableMinimumFrameDurationOnPhone` : sans cette clé, iOS bride les iPhone ProMotion à 60 Hz.

## Collage à la route pendant la leçon (Mapbox), pas encore fait

Le porteur a fourni son jeton Mapbox le 20 octobre. C’est le même jeton public que celui du recalage serveur ; il est rangé dans `.local/acces/`, hors dépôt (le dépôt est public).

Ce que demande le SDK Navigation v3 en mode « free drive » :

- Un trajet est facturé à chaque `startFreeDrive()`, plus un coût par utilisateur actif mensuel ; à l’échelle d’une auto-école, la gratuité couvre l’usage actuel (à vérifier dans le compte Mapbox).
- Le SDK embarque le Maps SDK Mapbox. Les conditions demandent d’afficher les résultats sur une carte Mapbox. Garder MapKit et n’utiliser que la position recalée pose la même question de conformité que celle déjà ouverte pour le recalage serveur (`gps-fluide-recalage-20261011.md`, points restant ouverts).
- La télémétrie Mapbox envoie des positions à Mapbox (États-Unis) et doit pouvoir être refusée. C’est un destinataire de plus, à nommer dans la notice de l’école.

Le choix revient au porteur : passer la carte de leçon sur Mapbox, ou garder MapKit avec la prédiction actuelle et le recalage après la leçon.

## Hors connexion

Inchangé et déjà conforme à la demande : l’enregistrement se fait dans le coffre local sans réseau, les lots partent quand la connexion revient, et le recalage routier est calculé côté serveur à la première lecture du trajet. Le replay s’affiche d’abord sur les mesures, puis sur la route dès que le recalage est prêt.

## Vérifications

| Vérification | Résultat |
|---|---|
| Leçon réelle, avant/après (homelab, lecture seule, statistiques seulement) | Voir le tableau du replay |
| Scénarios des nouveaux tests rejoués en JavaScript avec le vrai `selectTrack` de l’API | Passent, ainsi que les scénarios des tests existants (déplacement continu, arrêt au feu, arrêt puis départ, trajet de 6 000 points) |
| Tests Swift (CI Apple) | Run `39482372052` vert : 685 tests Swift Testing dans 63 suites. Premier passage (`39479415879`) : un échec du nouveau test de la flèche, fenêtre mal recentrée au bord d’un tronçon, corrigé. |
| IPA d’essai | `fc7c4c3`, run `39482372250` |

**Non vérifié** : rien n’a été vu tourner sur un appareil. La fluidité perçue, le comportement de la prédiction sur route (virage serré, rond-point, freinage brusque) et le 120 Hz réel restent à qualifier par le porteur sur iPhone.
