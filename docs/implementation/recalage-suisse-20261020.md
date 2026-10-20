# Recalage Suisse : état initial, scripts et preuves du 20 octobre 2026

## Périmètre de cette livraison

Mission complémentaire limitée à la lecture, aux scripts et à cette documentation. Aucun accès SSH, aucune modification du homelab, aucune migration de base ni modification de `STATUS.md` par l'auteur de ce lot. Les faits d'exploitation ci-dessous proviennent du mandat, des fichiers locaux et des comptes rendus du coordinateur. Les essais propres à ce lot sont locaux, avec des données synthétiques et un Docker éphémère.

Références lues : `COMMENCER_ICI.md`, règles R41 à R50, `03-fonctionnel/gps-replay.md`, contrat API de conception, scénarios T102 à T109, `gps-fluide-recalage-20261011.md` et `gps-replay-fluide-20261020.md`. Le contrat canonique reste OpenAPI 3.11.0. Les droits serveur, le chiffrement des mesures, les lacunes et la distinction entre trace mesurée et recalage restent obligatoires. Le partage automatique validé le 28 septembre prime sur les anciens scénarios de publication, sans exposer les observations privées.

## Décisions d'implémentation

- OSRM v26.10.0 sur CT117, réseau privé `192.168.1.158:5000`, appelé par l'API CT114 `192.168.1.153`. Le réseau ne remplace pas les contrôles d'autorisation de l'API.
- Graphe Suisse Geofabrik, profil voiture et pipeline MLD, préparés localement sur Windows. Horodatage des données lu dans `prepare.log` : **19 octobre 2026 à 20:21:11 UTC**.
- Image verrouillée : `ghcr.io/project-osrm/osrm-backend@sha256:55dbfd47d984c2cacd64e32901b4321c86b5ec761438e69aa053dc78698a786f`. Le digest du tag installé a été relu localement, le binaire a répondu `v26.10.0`.
- SHA256 du PBF mesuré localement : `59a6be5f1d7967b133dcbe5cdae7ae0b53fd49dfd2607fe37f935183ef277fed`. Le script suivi refuse un autre extrait même s'il porte le même nom `latest`.
- Unité systemd : deux threads, IP privée explicite, seulement `--max-matching-size 100` parmi les options `--max-*`. Pas de plafonds route/table/trip/nearest ajoutés à l'aveugle. Les options ont été recoupées avec le binaire épinglé et le source `src/tools/routed.cpp` du tag v26.10.0.
- Port moteur limité à l'API et à l'hôte `.106`. SSH reste réservé au LAN administratif dans le modèle reproduisant le durcissement réel. Egress fermé par défaut, réponses aux connexions établies et boucle locale seulement. Maintenance réseau explicite.
- Pas de journalisation des URLs, positions, réponses ou jetons. `StandardOutput=null`, `StandardError=null`, `LimitCORE=0`. La santé utilise l'adresse `.158`, pas `127.0.0.1` après le bind privé.
- Le nouveau benchmark synthétique n'accepte plus de fichier de jeton et n'appelle aucun tiers. Il utilise le client et le pipeline applicatifs, sans lire une capture réelle.

Livrables : `infra/osrm/runtime-lock.json`, `prepare.ps1`, `prepare.test.ps1`, `drivy-osrm.service`, `drivy-osrm.nft`, `compare.mts`, `synthetic.mts`, `compare.test.mts`, `baseline-synthetic-20261020.json` et `README.md`. Le prototype non suivi `.local/osrm/compare.mts` redirige désormais vers l'implémentation corrigée. Aucun fichier contenant un jeton n'est ajouté au dépôt.

## Chronologie : ne pas confondre moteur disponible et résultats migrés

Toutes les heures de cette section sont en **UTC**, le 20 octobre 2026. L'heure locale de la session est UTC+02:00.

| Instant | Fait et source | Ce qu'il ne prouve pas |
|---|---|---|
| Avant 20:55 | CT117 est créé et le moteur Suisse fonctionne. L'API utilise encore Mapbox au début de la mission. | Aucune bascule applicative à cet instant. |
| 20:55:13 | Première sauvegarde après création de CT117, vérifiée en lecture. Détails ci-dessous. | Ne rend pas la création antérieure conforme au mandat. |
| 20:56:04 | Nouvelle sauvegarde avant bascule, rapportée par le coordinateur. | Pas une restauration d'essai. |
| 20:56 | Coordinateur : environnement API passé à OSRM, anciennes variables dont jeton commentées, service API redémarré actif. Script local `switch-osrm.sh` lu comme historique opérationnel, pas exécuté par ce lot. | Les routes Mapbox déjà stockées ne deviennent pas OSRM par changement d'environnement. Les anciens secrets commentés ne sont pas une preuve d'effacement. |
| 20:57:00 | Sauvegarde avant durcissement puis écoute privée, deux threads, suppression stdout/stderr et egress fermé. Source `.local/osrm/harden.sh` et compte rendu coordinateur. | Aucune preuve de charge prolongée. |
| 20:59 | Redémarrage final CT117, preuve `.local/osrm/reboot-proof.txt` : OSRM/nftables actifs, écoute `.158:5000`, `NRestarts=0`, règles persistantes, egress neuf bloqué, route synthétique CT114 HTTP 200. Le coordinateur rapporte un timeout PC attendu, code curl 28. | Ce contrôle de `/route` ne prouve ni la purge du cache ni la restitution de chaque replay par OSRM. |
| 21:01 | Agent API : correctifs de cache/provider et migration 035 préparés, tests ciblés annoncés verts, **aucun déploiement de ce lot annoncé à cette heure**. | Ne pas écrire que tous les résultats servis proviennent déjà d'OSRM. Le suivi de ce lot est distinct. |

L'avertissement Proxmox « Systemd 257 ... nesting » apparaît dans la preuve de redémarrage. Selon le coordinateur, `nesting` n'a pas été activé et les services fonctionnent. Ce n'est pas une raison pour élargir silencieusement les privilèges du CT.

## Incident de sauvegarde : violation du mandat

**CT117 a été créé avant la sauvegarde préalable exigée. C'est une violation du mandat du 28 septembre, pas une étape normale.** La sauvegarde faite ensuite sécurise les opérations suivantes mais ne répare pas rétroactivement l'ordre des opérations.

Première archive vérifiée sur CT113, faits transmis dans le mandat :

| Champ | Valeur |
|---|---|
| Chemin | `/root/drivy_refonte-before-osrm-20261020T205513Z.dump` |
| Taille | 1 298 574 octets |
| Permissions | `600` |
| SHA256 | `98439c5995ab3dcefb44b58d7c2504ffbca5ae7d0f3550ba5be4061e4136e87b` |
| Contrôles | `pg_restore --list` et `pg_restore --file=/dev/null` |
| Restauration dans une base d'essai | **Non réalisée** |

Archives suivantes rapportées par le coordinateur, chacune de 1 298 574 octets, permissions `600`, mêmes deux contrôles de lecture :

- `/root/drivy_refonte-before-osrm-switch-20261020T205604Z.dump`
- `/root/drivy_refonte-before-osrm-hardening-20261020T205700Z.dump`

Aucun SHA256 de ces deux dernières archives n'est inventé ici. La procédure future doit bloquer toute création, installation, bascule ou modification réseau tant qu'une sauvegarde fraîche et ses contrôles ne sont pas acquis. Un exercice de restauration isolée reste nécessaire.

## Mémoire : trois mesures différentes

Mesures initiales transmises et complétées par la fin de `.local/osrm/measure-all.json` :

- RSS du moteur : **665 328 kB**, mesure du processus, pas la mémoire totale du cgroup.
- Cgroup : **1 257 992 192 octets**, environ **1 258 Mo décimaux**, dont environ **580 Mo de cache de fichiers** selon le mandat. Pic : **1 258 291 200 octets**.
- Aucun OOM constaté et `NRestarts=0` sur la période observée. Après redémarrage final : `MemoryCurrent=1257865216`, `NRestarts=0` dans la preuve locale.

Le plafond `MemoryMax=1200M` vaut 1 258 291 200 octets. La proximité du plafond appelle une mesure à froid et sous charge, pas la conclusion « moteur trop gros » à partir du seul cache, ni « capacité validée » à partir de l'absence d'OOM. Les métriques doivent distinguer RSS, mémoire anonyme, cache de fichiers, événements OOM et redémarrages.

## Mesures initiales sur les leçons : comparaison avec un cache

Source : `.local/osrm/measure-all.json`, relu localement. Ne pas committer cet export, ses identifiants de capture ou des positions. Ce fichier mêle un bloc JSON et trois lignes systemd en suffixe : il n'est pas un document JSON strict dans son ensemble.

| Échantillon | Mesures | Sommets sélectionnés | Couverture OSRM | Confiance | Appels OSRM | Total |
|---|---:|---:|---:|---:|---:|---:|
| Court | 116 | 58 | 116/116, 100 % | 0,679 | 1 | 43 ms |
| Long | 1 058 | 151 | 228/1 058, 21,6 % | 0,960 | 2 | 23 ms |

Pour ces deux échantillons, la couverture Mapbox **déjà stockée** est identique, avec confiance 0,678 pour le court et 0,960 pour le long. **Aucun appel Mapbox réel n'a été fait pour cette mesure initiale.** Aucune comparaison de latence contemporaine OSRM/Mapbox n'en découle. Trois autres très courts échantillons, 7 à 9 mesures, n'ont produit qu'un sommet sélectionné chacun, aucun appel et aucun tronçon recalé.

Le script historique additionnait les plages. Les deux résultats comparés comportent chacun un seul tronçon, donc pas de double comptage entre tronçons ici. Cette observation ne rend pas la formule correcte pour un corpus général. La faible couverture du trajet long demeure une limite majeure à analyser : choix de sélection, lacunes, rejet de points et géométrie ne sont pas interchangeables. Une forte confiance ne qualifie que le tronçon retenu, pas tout le trajet.

## Baseline synthétique corrigée

Les trois défauts du prototype ont été reproduits par des tests rouges avant correction : arrêt jamais atteint avec le pas de 11 m, couverture gonflée par chevauchement/trous et distance positive au milieu d'un segment pourtant sur la route.

Corrections : arrêt temporel garanti de 20 s, ensemble de mesures couvertes par segment/séquence, projection sur toute la polyligne au lieu des échantillons. La mesure reste orientée des sommets recalés vers la référence, non pondérée par longueur, et ne juge pas la chronologie ou le choix d'une route parallèle.

Deux exécutions à 20:59:06 et 20:59:48 UTC, Docker local Windows, Node v26.8.1, image et PBF verrouillés :

| Résultat | Valeur |
|---|---|
| Route génératrice | OSRM, 8 442,860 m |
| Trace bruitée | 789 mesures, graine 7, sigma 4 m, 1 Hz, arrêt 20 s |
| Couverture des plages | 774/789, 98,1 %, 4 tronçons |
| Confiances | 0,909 / 0,892 / 0,977 / 0,884 |
| Appels de matching | 4 par exécution |
| Durées totales | 66,391 ms puis 53,685 ms |
| Écart à la polyligne | médiane 0 m, p95 0,043 m, maximum 5,756 m |
| Appels tiers | Aucun |

Les résultats hors durée sont identiques au second passage. **Il s'agit d'une baseline de cohérence, pas d'une victoire d'OSRM sur une route qu'il a lui-même générée.** Pas de vérité terrain indépendante, de comparaison Mapbox en direct ni de qualification physique GPS.

## Vérifications exécutées par ce lot

- Six tests `node --import tsx --test infra/osrm/compare.test.mts` verts. Les trois régressions principales ont d'abord échoué avec les calculs historiques.
- TypeScript strict des trois fichiers `.mts` : vert, sans modification des dépendances.
- `prepare.ps1 -VerifyOnly` sur le PBF réel : hash conforme. Source différente : refus avant Docker.
- `prepare.test.ps1` : orchestration validée avec **Docker remplacé**, y compris chemins avec espaces, digest, réseau fermé, manifeste, refus d'écrasement et arrêt sur erreur. Le test a détecté puis permis de corriger l'interception de `-v` par PowerShell. Ce n'est pas une exécution du pipeline complet.
- Vrai binaire épinglé : version/aide relues, initialisation `--trial` réussie sur boucle locale, deux benchmarks réels sur graphe Suisse monté en lecture seule. Une première tentative `--trial --ip 192.168.1.158` a échoué car l'adresse du CT n'existe pas dans Docker local. `--trial` effectue bien un bind, puis quitte après initialisation.
- Suite globale `npm test` tentée sans `TEST_DATABASE_URL` pour interdire toute base/homelab implicite : 11 fichiers verts, 32 rouges, 182 tests réussis, 4 échoués, 171 ignorés. Les suites d'intégration exigent une vraie base isolée. Un test de notice OSRM concurrent était aussi rouge et a été signalé à son auteur. Après correction, contrôle direct du binaire Vitest à **21:05:17 UTC** : **34 tests verts** (`track-matching.test.ts`, 28 tests, et `text-proposals.test.ts`, 6 tests). Une tentative intermédiaire via npm, bloquée sans sortie, a été annulée avant ce contrôle direct. Ce succès ciblé ne transforme pas l'exécution globale précédente en succès.
- Aucun contrôle PostgreSQL, iOS, batterie, GPS physique ou VoiceOver revendiqué dans ce lot. Node local v26.8.1 diffère du runtime Node 24 exigé par le dépôt.

## Exigences de preuve et travaux en attente

| Exigence | Preuve disponible | État / suite |
|---|---|---|
| Même moteur et même extrait à la reconstruction | Digest image, version binaire, hash PBF et tests de préparation | Pipeline complet du nouveau script encore à rejouer, archive à vérifier sur cible |
| Absence de faux arrêt, double couverture et erreur d'échantillonnage | Trois tests régressifs puis six tests verts, baseline réelle locale | Acquis pour le benchmark synthétique |
| Écoute privée et filtrage persistant | `reboot-proof.txt`, HTTP 200 CT114, egress refusé, timeout PC rapporté | Qualifié pour le redémarrage observé, refaire après changement réseau |
| Pas de données dans les logs moteur | stdout/stderr nuls et core dumps interdits relus après redémarrage | Auditer aussi proxy/API et leurs exceptions, pas seulement OSRM |
| Bascule complète des résultats vers OSRM | Environnement changé à 20:56, correction/migration cache préparée séparément | **PENDING** : déploiement de migration, anciens baux, cache, relecture authentifiée et provenance réelle de chaque résultat |
| Route longue exploitable | 21,6 % seulement couverts sur le long échantillon initial | **PENDING** : expliquer les refus et lacunes, corpus indépendant, revue visuelle et temporelle |
| Comparaison loyale des moteurs | Cache Mapbox initial seulement, route synthétique générée par OSRM | **PENDING** : corpus autorisé et indépendant, protocole explicite, aucune conclusion comparative actuelle |
| Capacité/mémoire | RSS et cgroup distingués, aucun OOM observé | **PENDING** : froid/chaud, plusieurs trajets concurrents, long terme, marge et p95 avec effectif suffisant |
| Sauvegarde restaurable | Trois archives vérifiées en lecture selon le mandat/coordinateur | **PENDING** : restauration dans une base isolée, incident de création sans sauvegarde non effacé |
| Environnement de référence | Tests locaux Node 26, OSRM réel en Docker | **PENDING** : Node 24, vraie PostgreSQL isolée pour les changements API, tests Apple et terrain |

Le coordinateur reste responsable de l'actualisation de `STATUS.md` et de la synthèse finale des lots. Cette note initiale ne certifie ni une purge déjà appliquée, ni une qualité terrain, ni l'absence d'envoi tiers dans toute l'application après la bascule.
