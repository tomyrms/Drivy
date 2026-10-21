# Recalage direct sur la route, 21 octobre 2026 (#90)

Suite du diagnostic `diagnostic-gps-osrm-20261021.md` (#89). OSRM privé seul, aucune mesure modifiée.

## Ce qui change

| Avant | Après |
|---|---|
| L'app envoyait 3 à 20 mesures à 1 Hz ; OSRM donnait une confiance nulle sur des points si serrés. | L'école retient les mesures espacées d'au moins 20 m en remontant depuis la dernière (3 au moins), dans une fenêtre de 30 mesures et 30 s. |
| Refus dès qu'un point avait une alternative (`alternatives_count`), ce qui arrivait presque toujours. | Refus par confiance < 0,6, par écart de chaque mesure > min(25, max(10, 2,5 × précision)) m, et par détour (route > 1,6 × chemin mesuré + 30 m). |
| Garde de vitesse < 2 m/s côté app, API et carte : aucune correction en conduite lente. | Plus de garde de vitesse. Un arrêt ne produit pas trois mesures à 20 m d'écart : aucune requête, aucun faux tracé. |
| Réponse : position de la dernière mesure seulement. Seul le marqueur bougeait. | Réponse : position et **tronçon routier** ancré sur les mesures retenues (contrat `live-match` v2). |
| La ligne restait faite des mesures brutes. | `SchoolLiveTrace` remplace, entre deux ancres, les mesures affichées par la géométrie routière. Hors tronçon, ou de part et d'autre d'une lacune, la ligne reste mesurée. |
| Une nouvelle mesure annulait la requête en cours : à 1 Hz, presque rien n'aboutissait. | Une nouvelle mesure retire seulement la correction du marqueur. La réponse tardive garde son tronçon, qui décrit des mesures déjà dessinées. |
| Réduire les animations désactivait le recalage. | Même géométrie ; seul le glissement du marqueur devient un placement instantané. |

Invariants conservés : positions affichées, ancres des signalements, point de départ et position courante restent les mesures ; rien n'entre dans la file d'envoi ni dans le stockage ; droits relus avant et après le moteur ; aucun journal de positions ; délai moteur 750 ms ; un appel au plus toutes les 2,5 s.

## Validation sur traces synthétiques

Vrai module `live-matching.ts` (bundlé) exécuté sur CT114 contre le moteur CT117, fenêtres toutes les 3 s, itinéraire Berne-Muri calculé par OSRM, bruit gaussien. Erreur mesurée contre la position vraie de la trace, écart de ligne contre l'itinéraire.

| Trace | Fenêtres recalées | Position p50 / p90 | Ligne p90 / max | Calcul p90 |
|---|---:|---:|---:|---:|
| 3 m/s, σ 5 m | 41 % | 3,4 / 9,2 m | 0,0 / 11,3 m | 3,1 ms |
| 7 m/s, σ 5 m, trois arrêts de 30 s | 49 % | 3,7 / 8,2 m | 0,0 / 13,5 m | 3,3 ms |
| 12 m/s, σ 5 m | 67 % | 3,2 / 9,6 m | 0,0 / 9,5 m | 3,7 ms |
| 15 m/s, σ 4 m | 65 % | 3,2 / 6,8 m | 0,0 / 11,7 m | 3,9 ms |
| 12 m/s, σ 10 m | 3 % | 1,3 / 2,6 m | 0,0 / 0,1 m | 4,5 ms |
| Marche dans un parc hors route | **0 %** | | | |

Avant ce lot, les mêmes conditions donnaient **0 %** de fenêtres acceptées. Avec un bruit de 10 m, le moteur reste prudent et la ligne reste mesurée : c'est voulu. Pendant les arrêts, une partie des fenêtres est recalée (9/25 puis 7/25 et 17/25 en ville) : ce sont les fenêtres dont les 30 dernières secondes contiennent encore la conduite qui précède l'arrêt. La position renvoyée reste celle de la dernière mesure, sans nouveau tracé.

Validation urbaine (deux itinéraires dans Berne, hors zone piétonne) :

| Trace | Fenêtres recalées | Position p50 / p90 | Ligne p90 / max |
|---|---:|---:|---:|
| Ville A, 3 m/s, σ 5 m | 38 % | 3,5 / 9,1 m | 0,0 / 11,7 m |
| Ville A, 7 m/s, σ 5 m, arrêts | 49 % | 3,3 / 8,5 m | 0,0 / 16,7 m |
| Ville A, 12 m/s, σ 5 m | 54 % | 3,2 / 7,8 m | 0,0 / 7,4 m |
| Ville A, 15 m/s, σ 4 m | 25 % | 3,9 / 7,0 m | 0,0 / 10,2 m |
| Ville B, 3 m/s, σ 5 m | 42 % | 3,6 / 8,7 m | 0,0 / 7,5 m |
| Ville B, 7 m/s, σ 5 m, arrêts | 59 % | 3,3 / 6,3 m | 0,0 / 4,4 m |
| Ville B, 12 m/s, σ 10 m | 12 % | 3,0 / 8,5 m | 0,1 / 10,0 m |

Le maximum d'écart de ligne (jusqu'à 21 m sur un cas à σ 10 m) vient d'un tronçon placé sur une rue voisine parallèle : rare (p90 ≤ 4,7 m dans tous les cas), à surveiller en conduite réelle.

## Tests

- API : `live-matching.test.ts` (27 tests, nouvelle politique, tronçon, détour, dérive à l'arrêt, lacune) et `live-match.integration.test.ts` (26 tests sur PostgreSQL réelle, droits relus après moteur, contrat v2 validé par Ajv).
- iOS : tests `SchoolLiveMatchTests` adaptés et nouveaux (tronçon ancré refusé s'il ne correspond pas aux mesures envoyées, ligne sur la route sans changer positions ni ancres, aucun tronçon à travers une lacune, réponse tardive qui garde son tronçon sans bouger le marqueur). Exécution sur runner Apple non lancée (consigne : IPA seulement).

## À qualifier

Conduite réelle (ville, rond-point, rue parcourue deux fois, parking), latence réseau mobile, iPad, VoiceOver. Les seuils (20 m, 0,6, détour 1,6) sont synthétiques.
