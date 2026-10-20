# Recalage suisse : déploiement OSRM et affichage direct

## Périmètre de cette livraison

Branche `claude/recalage-suisse-osrm-20261020`, issue de `claude/gps-replay-fluide-20261020`, sans fusion ni publication de l'app. Cette livraison couvre le moteur privé, la bascule des replays, la purge des dérivés Mapbox et une correction éphémère du marqueur iOS. Les preuves distinguent les opérations réellement exécutées sur le homelab, les tests synthétiques et PostgreSQL locaux, la campagne Apple et les qualifications encore nécessaires sur iPhone.

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

## État intermédiaire des preuves avant intégration

Cette matrice décrit les lacunes constatées avant les résultats d'intégration et le déploiement consignés plus bas. Elle ne remplace pas la matrice finale de qualification.

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

Cette chronologie conserve l'état des preuves initiales. Les résultats d'intégration et de déploiement ultérieurs sont ajoutés ci-dessous. La bascule du recalage ne signifie pas que toute l'application cesse ses échanges avec Apple Plans.

## Intégration du recalage direct

L'extension `apps/api/contracts/live-match.json` décrit `POST /v1/schools/:schoolId/captures/:captureId/live-match`, sans modification du contrat canonique. Le serveur relit les droits avant et après le calcul, dans deux transactions distinctes. Seul le moniteur auteur de la capture encore autorisée peut obtenir une réponse. Les positions ne sont ni stockées par cette route, ni journalisées. Le limiteur est en mémoire et distingue cadence, simultanéité et saturation.

Le client OSRM direct n'accepte qu'une adresse privée ou locale, interdit les redirections, borne le corps à 64 Kio et le délai total moteur à 750 ms. Aucun repli Mapbox. L'app propose une fenêtre de 3 à 20 mesures réelles, sur 30 secondes au plus, toutes les 2,5 secondes au minimum. L'envoi suit leur écriture durable. Les identifiants du segment, de la séquence et du temps écoulé doivent encore correspondre à la mesure courante à réception.

Les refus sont conservateurs : vitesse inférieure à 2 m/s, précision insuffisante, trajectoire de manœuvre, confiance inférieure à 0,8, alternatives OSRM ou correction excessive. La borne de correction est `min(20 m, max(5 m, précision))`. Un refus ou une panne laisse fonctionner la prédiction locale. Une correction admise ne modifie que le marqueur, jamais les mesures, la trace ou les ancres d'observation. Son ajout et son retrait conservent la position affichée au même instant et ne redémarrent pas l'horizon de prédiction.

### Corrections issues des vérifications

- Première campagne Apple `39496894028` et IPA `39496894877` : compilation en échec, initialiseur de `SchoolLiveMatchWindow` rendu privé par son état interne. Initialiseur explicite ajouté dans `98c2ba7`. Une relance doit confirmer la compilation et les tests, pas seulement la lecture du correctif.
- Deuxième campagne Apple `39498734817` : compilation des tests en échec, appels `mutating` inclus dans les macros Swift Testing. Les quinze appels concernés sont évalués avant les assertions dans `f730cc1`, sans modification du code produit. Nouvelle campagne `39499618964` lancée et suivie.
- Revue indépendante : durée de vie initialement comptée depuis la réception au lieu de l'émission, attente OIDC partagée non interrompue par l'annulation du groupe de tâches, et refus de droit live ignoré par le coordinateur. Corrections et tests ajoutés dans `75361b5`, puis contre-revue sans autre défaut concret.
- Invalidation replay iOS : aucun cache disque de route recalée, mais le DTO ignorait la provenance et la version. La garde doit désormais exiger OSRM et l'algorithme 2, sinon conserver les mesures réelles comme affichage de repli.

## Notice de l'école

Formulation à reprendre après déploiement complet : « Le recalage routier est calculé sur notre hébergement à partir des données OpenStreetMap. Les positions ne sont pas envoyées à un fournisseur tiers pour ce calcul. » Les fonds de carte restent fournis par Apple Plans. Cette formulation ne prétend pas supprimer tous les échanges réseau de l'app. Les notices déjà adoptées ne sont pas réécrites automatiquement.

## Comparaison synthétique demandée avec Mapbox

Exécution complémentaire réelle à **21:07:04 UTC**, via le même client applicatif et le même pipeline `matchTrack`, algorithme 2. Les deux moteurs reçoivent exactement les mêmes 789 points synthétiques, graine 7, arrêt de 20 secondes. Empreinte d'entrée : `50da31042740240e77b0239c26a0b9295936c8aa49d4f197a0c6292bb92c5a40`. Le wrapper privé charge le jeton en mémoire, sans le journaliser. Aucune position de personne n'est envoyée à Mapbox.

| Mesure | OSRM local | Mapbox, appel Internet réel |
|---|---:|---:|
| Mesures couvertes | 774/789, 98,1 % | 737/789, 93,4 % |
| Tronçons / appels | 4 / 4 | 5 / 4 |
| Temps total | 77,421 ms | 591,831 ms |
| Médiane par appel | 14,375 ms | 137,381 ms |
| Écart géométrique médian à la référence | 0 m | 0,001 m |
| Écart p95 / maximum | 0,043 / 5,756 m | 0,093 / 3,279 m |

Confiances OSRM : 0,909 / 0,892 / 0,977 / 0,884. Confiances Mapbox : 0,972 / 0,945 / 0,891 / 0,977 / 0,903. Rapport agrégé local : `.local/osrm/compare-private-result.json`. Le moteur Docker local a ensuite été arrêté.

Cette comparaison complète la baseline précédente mais ne constitue pas un classement de qualité : référence générée par OSRM, un seul passage, quatre appels par moteur, réseau local contre Internet. Les écarts portent sur les sommets vers une polyligne, sans vérité terrain indépendante ni jugement temporel. Ces durées ne sont pas celles du homelab ni du réseau mobile.

## Rejeu du direct sur les deux captures

[Méthode, résultats et limites](direct-replay-osrm-20261020.md). Les vitesses et caps Doppler ne sont pas présents dans les captures stockées. Avec l'estimation causale utilisée pour le rejeu, les vitesses maximales sont 1,7068 et 1,9225 m/s : les deux trajets restent sous le seuil de 2 m/s. **Zéro appel produit, zéro correction appliquée, avant/après identiques.** Aucun seuil n'est abaissé pour obtenir artificiellement un résultat.

Le diagnostic séparé appelle OSRM sans appliquer ses résultats au marqueur : 352 et 38 fenêtres, temps médians d'environ 2 à 3 ms, aucun timeout ni défaut réseau. Les 183 HTTP 400 de la première capture sont `NoSegment` (180) ou `NoMatch` (3), pas des pannes de transport. Cette mesure vérifie le moteur et documente les refus, mais ne qualifie pas une correction acceptée en conduite. Les tests synthétiques et Swift doivent couvrir ce chemin, puis un essai iPhone doit en apprécier le rendu réel.

## Déploiement API et purge exécutés à 21:14 UTC

Release **`cf0f316417a9613cbc50c3e6a7feec61ad41192c`**, API et web sur le même répertoire, identité active sans modification. Avant installation : sauvegarde privée CT113 `/root/drivy_refonte-before-cf0f316417a9613cbc50c3e6a7feec61ad41192c-20261020T211441Z-42719ad1e910.dump`, propriétaire root, permissions 600, synchronisée et vérifiée par décompression complète `pg_restore --file=/dev/null`. Pas de restauration d'essai.

L'ancienne API a été arrêtée avant la migration : aucun ancien processus ne peut continuer à réclamer un bail par la signature supprimée. Les 35 migrations appliquées ont toutes été comparées aux empreintes du commit. SHA256 de la migration 035 : `5440b5fa0f5935977c7bb0a2b00493d42157e07a27cef74d632e64f6b0899d1e`. Archive de release vérifiée après transfert : `480884a090b45f8b12799e7b45412cd534f2306687be6c0eda310113b80921b3`.

Contrôles post-déploiement à 21:15 UTC :

- Cache Mapbox : **2 lignes avant, 0 après**. Aucune ligne d'algorithme ancien ni bail en cours. Ancienne fonction à quatre arguments absente, nouvelle fonction présente.
- Mesures : **18 chunks, 204 483 octets chiffrés**, empreinte agrégée `07c363f29bdcbebd9c0e2f8cc6cb096d` identique avant/après. Aucun recalcul forcé ni écriture sur les leçons réelles pendant la recette. Le prochain replay autorisé reconstruira son cache OSRM à la demande.
- API readiness 200, nouvelle route live sans identité 401, services API/web/identité actifs. Environnement du processus : fournisseur OSRM, endpoint privé, aucun jeton Mapbox actif. Anciennes variables toujours commentées dans le fichier privé.
- OSRM actif, zéro redémarrage spontané, mémoire cgroup 1 102 225 408 octets au contrôle. Zéro erreur de service API et zéro message d'échec de traitement depuis le déploiement, compteurs seuls exportés.

La sauvegarde conserve l'état antérieur pour restauration. La purge concerne le cache actif, pas les sauvegardes historiques. Ne pas remettre un ancien binaire seul après la migration 035 ni réactiver Mapbox pour contourner une panne : les mesures réelles restent le repli.

### Preuves de la version serveur

CI **`39498076583`**, commit `cf0f316`, réussie : **552 tests API / 43 fichiers**, vraie PostgreSQL 17 et SMTP, **316 tests web / 27 fichiers**, typage et builds, Node 24. Parcours navigateur d'ouverture d'école **`39498076715`** réussi. Manifeste canonique contrôlé : **556 fichiers inchangés**, sans régénération.

Le lot direct compte 26 tests unitaires et 26 tests PostgreSQL. La régression de demi-tour récent a d'abord été observée rouge sur une fenêtre de 20 points, puis corrigée et contre-vérifiée : refus sans appel moteur. Le lot purge compte 55 tests ciblés, dont migration peuplée, baux concurrents, cache de mauvais fournisseur/version et conservation des chunks et notices. Ces preuves qualifient les chemins logiciels, pas la justesse physique du GPS.

## Matrice finale de qualification

| Exigence | Vérification exécutée | Résultat observé et limite |
|---|---|---|
| OSRM Suisse, voiture, version épinglée | Image/données/binaire vérifiés, préparation Windows réelle, service CT117 | v26.10.0, profil voiture, archive transférée à empreinte identique ; nouveau script de préparation testé mais pipeline complet de ce script non rejoué |
| Respect de la mémoire disponible | Prétraitement hors homelab, RSS/cgroup et OOM du moteur | RSS environ 650 Mio, cgroup 1,10 Go au dernier contrôle, zéro redémarrage spontané ; charge longue non qualifiée |
| Moteur privé et résilient au redémarrage | Bind explicite, nftables, redémarrage CT117, appel synthétique depuis CT114 | Accès API réussi, PC refusé, egress neuf bloqué, journaux moteur désactivés |
| Sauvegarde avant déploiement | Archives privées, lecture complète avant bascule/configuration/durcissement/release | Vérifications réussies, restauration non testée ; création initiale du CT sans sauvegarde constitue l'écart décrit plus haut |
| Comparaison OSRM/Mapbox | Même trace synthétique et même client, protocole corrigé | 774/789 contre 737/789 couverts ; aucune donnée réelle envoyée à Mapbox, aucune supériorité terrain déduite |
| Bascule sans résultats Mapbox persistants actifs | Migration réelle, invalidation fournisseur/version/baux testée sur PostgreSQL | 2 caches actifs supprimés, 0 restant ; sauvegardes privées antérieures conservées |
| Mesures réellement enregistrées inchangées | Comparaison des chunks chiffrés et empreinte avant/après | 18 chunks, 204 483 octets, empreinte identique ; correction strictement affichage |
| Seul le moniteur autorisé peut appeler le direct | Cas autre moniteur/école/élève, droits perdus pendant attente, double transaction | 26 tests PostgreSQL directs réussis, refus sans divulgation de position |
| Cadence, panne et réponse tardive | Tests du limiteur, HTTP natif interrompu, moteur en panne et délai dépassé | 26 tests unitaires directs réussis, budget moteur 750 ms, pas de persistance ni repli tiers |
| Aucune position dans les journaux | Tests de logs API et erreurs, sorties OSRM nulles, contrôle agrégé après release | Tests réussis ; zéro message d'échec API observé, aucun journal de coordonnées exporté |
| Ne pas forcer parking/manœuvre | Tests confiance/distance/ambiguïté/vitesse et demi-tour récent | Refus conservateurs, dont régression de fenêtre longue corrigée ; limites physiques à vérifier sur appareil |
| Réponse périmée ignorée, correction continue, ancres intactes | Tests Swift ajoutés, contre-revue, rejeu numérique | Campagne Apple finale en cours ; aucun gain terrain revendiqué par le port JS |
| Rejeu réel avant/après | Déchiffrement CT114 en mémoire, lecture seule CT113, statistiques seulement | Deux captures, zéro correction admise avec vitesse estimée ; diagnostic séparé sans application au marqueur |
| Build et tests Swift Apple | Workflow `39499618964` sur le code iOS corrigé | En cours ; première compilation échouée puis corrigée, pas encore de succès final revendiqué |
| IPA d'essai | Workflow `39498733858` déclenché par push | En cours ; aucune signature, installation, fusion ou publication de l'app effectuée |
| Notice et attribution | Proposition de notice OSRM, lien OpenStreetMap fixe dans les réglages | Notices adoptées non modifiées, MapKit conservé, aucun SDK Mapbox ajouté |
| GPS/batterie/VoiceOver/fluidité | Nécessite un iPhone physique et une conduite autorisée | Non exécuté depuis Windows ou simulateur, reste à qualifier |
