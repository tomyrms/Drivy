# Rejeu direct OSRM du 20 octobre 2026

## Portée exécutée

Deux captures demandées ont été relues sans mutation de base. Les lignes chiffrées ont été lues dans CT113, puis déchiffrées uniquement en mémoire dans CT114. Le moteur appelé directement est celui du homelab. Aucun service n'a été déployé ou redémarré. Les sorties ne contiennent que des statistiques et empreintes de code, sans identifiants de personnes ou de captures, coordonnées ou horodatages individuels.

Les scripts versionnés sont `infra/osrm/live-compare.py`, `live-compare.js` et leurs tests. Les entrées demandées `.local/osrm/live-compare.py/.js` y délèguent. La méthode et les commandes reproductibles figurent dans `infra/osrm/LIVE_COMPARE.md`. Le scénario principal revérifié après correction du TTL est conservé dans `.local/osrm/live-compare-principal-final.json`. Le diagnostic moteur précédent reste dans `.local/osrm/live-compare-final.json`, sans nouvel appel moteur lors de la revérification du TTL.

## Résultat représentatif des gardes actuels

Le rejeu compare le predictor actuel **sans** puis **avec** correction routière, pas l'ancien glide. Il attendait les algorithmes API/iOS, qui ont été utilisés après confirmation de leurs agents. Le vrai module de calcul API est bundlé en mémoire. Le predictor et l'ordonnanceur iOS sont un port numérique JS relu contre le Swift, pas une exécution sur iPhone.

| Mesure | Capture 1 | Capture 2 |
|---|---:|---:|
| Points | 1 058 | 116 |
| Segments / séquences continues | 1 / 1 | 1 / 1 |
| Durée | 1 057 s | 114,853 s |
| Vitesses / caps Doppler stockés | 0 / 0 | 0 / 0 |
| Vitesse causale estimée p95 | 1,1237 m/s | 1,7845 m/s |
| Vitesse causale estimée maximale | 1,7068 m/s | 1,9225 m/s |
| Mesures bloquées par vitesse < 2 m/s | 1 057 | 115 |
| Première mesure sans fenêtre suffisante | 1 | 1 |
| Requêtes produit / corrections acceptées / appliquées | 0 / 0 / 0 | 0 / 0 / 0 |
| Couverture en fixes / temps actif | 0 % / 0 % | 0 % / 0 % |
| Saut instantané maximal, avant / après | 0 / 0 m | 0 / 0 m |

**Avant et après sont identiques : le garde de faible vitesse interdit toute requête produit sur ces deux captures avec les vitesses estimées.** Aucun seuil n'a été abaissé pour obtenir artificiellement des corrections. Les refus produit pour confiance, distance et retard valent zéro faute de requête, pas parce que ces critères auraient été validés sur le terrain.

Écarts au GPS interpolé, identiques avant et après :

| Distance aux mesures, pas vérité terrain | Capture 1 | Capture 2 |
|---|---:|---:|
| Moyenne | 0,3293 m | 0,3959 m |
| p50 | 0,2532 m | 0,3348 m |
| p90 | 0,6819 m | 0,7108 m |
| p99 | 1,2701 m | 1,4796 m |
| Maximum | 2,9946 m | 2,4712 m |

Le compteur instantané ne mesure pas le déplacement normal entre frames. Celui-ci est disponible séparément dans le JSON. L'absence de saut dans ce scénario sans correction ne valide pas à elle seule la continuité routière réelle.

## Diagnostic moteur séparé, sans application au predictor

Un second mode envoie directement les fenêtres au moteur, en contournant **uniquement pour le diagnostic** les gardes d'admission. Il ne change pas les statistiques produit ci-dessus. Les fenêtres se chevauchent : leurs tracepoints ne sont pas une couverture de mesures uniques.

| Diagnostic direct | Capture 1 | Capture 2 |
|---|---:|---:|
| Appels moteur | 352 | 38 |
| Dernier point exploitable | 148 | 36 |
| Fenêtres dont tous les tracepoints existent | 124 | 25 |
| HTTP 200 | 169 | 38 |
| HTTP 400 | 183 | 0 |
| Parmi HTTP 400 : `NoSegment` / `NoMatch` | 180 / 3 | 0 / 0 |
| Erreur réseau / HTTP 429 / HTTP 5xx / timeout | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| Transport moteur p50 | 2,4570 ms | 2,2027 ms |
| Transport moteur p95 | 3,0008 ms | 3,3525 ms |
| Transport moteur maximum | 34,3366 ms | 3,8024 ms |
| Confiance < 0,8 | 103 | 22 |
| Distance excessive sur au moins un point | 59 | 36 |
| Ambiguïté ou changement de matching | 98 | 36 |
| Réponse sans tous les points nécessaires | 45 | 13 |

Les trois critères confiance, distance et ambiguïté sont évalués lorsqu'un dernier point exploitable existe. Ce sont des conditions **indépendantes et non additionnables**. Les 183 refus HTTP 400 sont des absences de correspondance, **pas une panne de transport**. Les temps ci-dessus incluent l'appel direct depuis CT114 et la lecture de réponse, pas le réseau mobile ou la route API complète.

## Limites et vérifications

- Vitesse et cap sont estimés à partir de mesures passées couvrant environ deux secondes. Aucun Doppler réel n'est récupérable depuis ces captures. Le téléphone aurait pu prendre des décisions différentes avec ses valeurs natives.
- Latence d'écriture/livraison supposée à 100 ms, aucune latence mobile ajoutée dans cette exécution, frames calculées à 60 Hz. Le predictor utilise la livraison, conformément à l'UI actuelle.
- Une acquisition plus récente invalide la réponse précédente même avant écriture durable. La réponse et l'affichage partagent un budget de deux secondes depuis **l'émission** : une réponse reçue après une seconde ne conserve qu'une seconde d'affichage, pas deux secondes supplémentaires.
- Les tests synthétiques couvrent acceptation, continuité de l'application/retrait, refus de confiance, réponse devenue ancienne avant la livraison suivante, délai > 2 s, sortie anonyme et impossibilité pour le diagnostic de modifier le predictor.
- Vérification exécutée : 10 tests Node et 4 tests Python réussis, préparation locale sans SSH, puis exécution réelle CT114 avec sortie agrégée validée. Le test d'expiration depuis émission a d'abord échoué sur l'ancien port, puis réussi après correction. Pas de suite métier avec mutation PostgreSQL dans cette mission.
- **Ces captures ne qualifient pas la correction routière en conduite, la fluidité physique, le GPS, la batterie ou VoiceOver. Aucune amélioration terrain n'est revendiquée.**

Empreintes SHA-256 du **diagnostic moteur précédent**, après stabilisation API `cf0f316` et avant correction du TTL iOS. Ses réponses n'étaient jamais appliquées au predictor, donc les statistiques moteur ne dépendent pas de ce TTL :

```text
API bundle 8720d3022275bccd920b4591d08df110950dc1c4d3a0bd35ab1435f07d50abf0
Swift     a049e27d6ebd52a6b6e6e4e2eef6af06d0da5ac991e1060189608a66f5de5b4a
Rejeu JS  a6f759693c738b893ceb5e39c0cd12e4102d908fc2503e5ff692076274b0c1d4
```

Le scénario principal seul a ensuite été réexécuté avec le Swift final `75361b5` et l'expiration à `sentAt + 2 s`. Les deux objets statistiques sont strictement identiques au passage précédent, après retrait de son bloc diagnostique : toujours zéro requête produit, zéro correction, avant/après identiques. Aucun appel diagnostique supplémentaire n'a été effectué.

Empreintes de ce **rejeu principal final**. L'empreinte Swift couvre la concaténation exacte de `SchoolMapMotion.swift`, `SchoolLiveMatchCoordinator.swift`, `SchoolLiveMatchModels.swift` et `SchoolCaptureLiveMap.swift`, pas le seul predictor :

```text
API bundle 8720d3022275bccd920b4591d08df110950dc1c4d3a0bd35ab1435f07d50abf0
Swift     4d319f40a0738d5ea6fe70810112b74e233922c67cc586d5cdbf94db36911972
Rejeu JS  e469c8908e00fb1e84be32a8f2447119e512c2081ca10eb111df8f7ba3fe84d7
```
