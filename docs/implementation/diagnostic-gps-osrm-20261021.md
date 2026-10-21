# Diagnostic GPS/OSRM du 21 octobre 2026 (#89)

Lecture seule. Aucun service redémarré, aucune configuration ni base modifiée. Les captures réelles ont été lues en transaction `READ ONLY` sur CT113 et déchiffrées uniquement en mémoire sur CT114 ; seuls des agrégats numériques sont sortis. Aucun identifiant, nom, coordonnée ou horodatage individuel n'est consigné ici. Les traces synthétiques utilisent des itinéraires calculés par le moteur lui-même à Berne, avec un bruit gaussien déterministe.

## 1. Versions et configuration observées

| Élément | Observé |
|---|---|
| API CT114 | release `7d14a39` (lien `current`), migrations jusqu'à 039 |
| Fournisseur | `MAP_MATCHING_PROVIDER=osrm`, `MAP_MATCHING_BASE_URL=http://192.168.1.158:5000`, aucune variable Mapbox, aucune ligne Mapbox commentée |
| Seuil replay | `MAP_MATCHING_MIN_CONFIDENCE` absent : défaut 0,5 |
| Direct | même URL privée (`createOSRMLiveMatcher(mapMatching.baseURL)`), seuil codé 0,8 |
| Moteur CT117 | `/opt/osrm/v26.10.0/osrm-routed --algorithm mld --ip 192.168.1.158 --port 5000 --threads 2 --max-matching-size 100 /srv/osrm/current/switzerland-latest.osrm` |
| Service | actif depuis le 20.10 20:59:35 UTC, `NRestarts=0` |
| Mémoire | courant 682 Mo, anonyme 674 Mo, cache fichier 5 Mo ; **pic = plafond `MemoryMax` (1 258 291 200 o)**, `memory.events max 176`, `oom 0`, `oom_kill 0` |
| CT117 | 2 cœurs, 1 536 Mo, swap 512 Mo (0 utilisé), charge 0,2 à 0,45 |
| Hôte Proxmox | 15,7 Go, 3,5 Go disponibles |
| iOS installé | **non observé** (pas d'accès à l'iPhone) |

Le moteur a atteint son plafond mémoire 176 fois sans être tué : le noyau a récupéré le cache de fichiers. Ce n'est pas une saturation fonctionnelle (latences ci-dessous), mais le plafond ne laisse aucune marge pour le cache. Pas d'achat de RAM conseillé sur cette base.

## 2. Moteur : `/match` synthétique depuis CT114

| Cas | Code | Tracepoints | Confiance | Durée |
|---|---|---|---|---|
| 100 points tous les 8 m, bruit 5 m, `tidy` | Ok | 34/100 | 0,335 | 6 ms |
| 20 points | Ok | 7/20 | 0,374 | 7 ms |
| 3 points | Ok | 2/3 | 0,032 | 3 ms |
| 20 points immobiles | Ok | 7/20 | 0,827 | 7 ms |
| Hors graphe (lac) | 400 NoSegment | 0/3 | | 3 ms |

Sur les captures réelles, transport moteur p50 2,5 ms, p95 3,7 ms, max 29 ms, aucune erreur réseau, 429 ni 5xx. **Le moteur répond vite et correctement : la lenteur ou l'irrégularité ne vient pas du homelab.**

## 3. Recalage direct : les réglages actuels n'acceptent presque rien

Fenêtres glissantes de 20 mesures à 1 Hz, paramètres exacts de `live-matching.ts` (`tidy=false`, `gaps=split`, rayon = précision annoncée, confiance ≥ 0,8, aucun `alternatives_count`), sur conduite synthétique propre :

| Trace | Fenêtres | Acceptées (réglages actuels) | Points espacés de 15 m | Espacés + seuil 0,5 |
|---|---:|---:|---:|---:|
| Urbain 4 m/s, σ 5 m | 114 | **0** | 27 (erreur p50 3,6 m) | 30 |
| Urbain 8 m/s, σ 5 m | 55 | **0** | 14 | 23 |
| Urbain 14 m/s, σ 5 m | 30 | **0** | 19 (erreur p50 2,8 m) | 21 |
| Périurbain 8 m/s, σ 5 m | 135 | **0** | 16 | 37 |
| Périurbain 14 m/s, σ 5 m | 75 | **0** | 7 | 35 (erreur p50 2,4 m) |
| σ 10 m (urbain ou périurbain) | 30 / 75 | **0** | 0 à 2 | 2 |

Causes établies :

1. **Points trop serrés.** À 1 Hz, deux mesures sont à 4 à 14 m ; avec un bruit de 5 m, le modèle de Markov d'OSRM juge les transitions improbables et la confiance retombe vers 0 (p50 0,00 sur toutes les traces synthétiques). En ne gardant qu'une mesure tous les 15 m, la confiance remonte et l'erreur médiane du point recalé reste de 2 à 5 m.
2. **Garde `alternatives_count !== 0`.** Sur 1 Hz, presque chaque fenêtre a au moins un point avec une alternative (90 sur 104 en urbain lent). Ce critère seul suffit à tout refuser.
3. Le seuil 0,8 est ensuite le troisième filtre ; il pèse moins que les deux premiers.

Conséquence produit : **le marqueur et la ligne en direct ne sont pratiquement jamais recalés**, quelle que soit la vitesse. C'est l'entrée principale de #90.

## 4. Capture réelle la plus longue du 21 octobre

Leçon de 54 minutes, terminée. Agrégats seulement :

| Mesure | Valeur |
|---|---|
| Points, segments | 1 050, 3 (fin des deux premiers : `PAUSE`, dernier : `STOP`) |
| Chronologie (s depuis l'autorisation GPS) | seg. 0 : 2 à 64 ; seg. 1 : 282 (3 points) ; seg. 2 : 1 677 à 3 098 |
| Début de leçon | **126 s avant l'autorisation GPS** |
| Chemin brut total | 1 678 m |
| Précision annoncée | p50 3,8 m, p90 14,3 m, max 99 m ; 13 points > 30 m |
| Intervalle | p50 1 s, max 16,5 s |
| Vitesse paire à paire | p50 1,3 m/s, p90 2,1 m/s ; un bond à 889 m/s |
| Vitesse Doppler stockée | 0 échantillon (le contrat de lot ne la stocke pas) |

Ce trajet est en grande partie lent ou à l'arrêt (1,7 km en environ 25 minutes de points). Ce n'est pas une conduite représentative ; il explique néanmoins chaque symptôme :

- **Portion initiale « Position indisponible ».** La leçon a démarré 126 s avant que le GPS soit autorisé ; la première mesure arrive 2 s après l'autorisation. Le trou initial correspond à ces 126 s sans GPS, pas à un retard d'acquisition ni à un filtre d'affichage.
- **Grand trou au milieu.** Les deux premiers segments se terminent par une `PAUSE` manuelle ; aucun point entre 282 s et 1 677 s (23 minutes). C'est une pause, pas une perte de signal.
- **Direct (rejeu `live-compare.py`, vrai module API).** 38 requêtes simulées, 0 acceptée. Refus côté client : vitesse < 2 m/s 850 fois, fenêtre insuffisante 70, cadence 78. Côté API : virage 15, vitesse 11, confiance 11. Diagnostic moteur sans garde : 321 appels, confiance p50 0, p95 0,86 ; correction p50 5 m, p90 17 m ; 69 `NoSegment`.
- **Replay (nouveau `replay-diagnose.py`, vrai `track-matching.ts`).** La sélection garde 354 des 1 050 mesures, en 14 suites continues dont 10 n'ont qu'un point. 95 points partent au moteur en 4 lots : tous les points sont placés, mais **la confiance des 4 lots vaut 0 à 0,01**, sous le seuil 0,5. Résultat : 0 tronçon, couverture 0 %, état `EMPTY` en base. Comme pour le direct, des points lents et bruités espacés de 20 m font chuter la confiance.

La seconde capture examinée (37 points en 11 s, immobile, précision 9,4 m) ne peut produire aucun recalage : un seul point retenu.

## 5. Conclusions

| Hypothèse | Verdict |
|---|---|
| Homelab saturé, RAM insuffisante | **Non.** 2,5 ms p50, aucun OOM ni redémarrage. Plafond mémoire atteint par le cache : marge à revoir, pas une cause. |
| Mauvaise configuration, repli tiers | **Non.** OSRM privé seul, graphe et image conformes au verrou. |
| Matching refusé par la logique applicative | **Oui, cause principale en direct.** Fenêtre de mesures à 1 Hz non espacées et garde d'alternatives : ~0 % d'acceptation même en conduite propre. |
| Replay vide | **Oui, confiance moteur nulle** sur des points lents et bruités ; le seuil 0,5 n'est pas en cause pour cette capture (max 0,01). |
| Trou initial | **Leçon commencée avant l'autorisation GPS** (126 s). |
| Trou central | **Pause manuelle**, pas une perte de signal. |

## 6. Pistes pour #90 et #91 (non appliquées)

- Direct : espacer la fenêtre envoyée (une mesure tous les ~15 m, au moins 3), retirer ou assouplir le refus sur `alternatives_count`, rayon au moins 10 m. Gain attendu en synthétique : 0 % → 20 à 60 % de fenêtres acceptées avec une erreur médiane de 2 à 5 m. À requalifier en conduite réelle.
- Replay : distinguer dans l'interface « trop lent ou à l'arrêt pour être recalé » de « recalage en attente » et de « échec » (#91). Pour les longues portions lentes, envisager un lissage local plutôt qu'un collage routier.
- Départ : signaler dans l'app qu'une leçon a démarré avant le GPS, ou proposer d'autoriser le GPS dès le lancement de la leçon.
- Mémoire CT117 : relever `MemoryMax` (par exemple 1,5 Go sur un CT de 2 Go) pour garder le cache du graphe, sur décision séparée et après sauvegarde.

## Outils

- `infra/osrm/live-compare.py --run --diagnostic` : direct, inchangé.
- `infra/osrm/replay-diagnose.py` et `.js` (nouveaux) : mêmes barrières (lecture seule, déchiffrement en mémoire CT114, liste blanche de champs numériques des deux côtés), avec le vrai `track-matching.ts`.
- Les scripts synthétiques de cette session n'ont touché que le moteur, depuis CT114, avec des itinéraires générés par OSRM.
