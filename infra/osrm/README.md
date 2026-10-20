# OSRM Suisse : scripts et preuves

Ce dossier ne déploie rien automatiquement. Les scripts ne modifient ni la configuration de l'API, ni les caches de trajets, ni PostgreSQL. Les décisions et l'incident de sauvegarde sont consignés dans `docs/implementation/recalage-suisse-20261020.md`.

## Préparer sur Windows

Prérequis : Docker Linux amd64 et PowerShell. Le verrou fixe l'image par digest, le profil voiture, MLD et le SHA256 de l'extrait Geofabrik du 19 octobre 2026 à 20:21:11 UTC. Le nom distant `latest` est mutable : conserver le PBF exact hors Git. Un téléchargement ultérieur n'est pas automatiquement la même entrée et sera refusé si son hash diffère. La mise à jour de la carte doit réviser le verrou et relancer la qualification.

Depuis la racine du dépôt :

```powershell
# Vérification seule, sans Docker ni écriture.
powershell -NoProfile -File infra/osrm/prepare.ps1 -PbfPath .local/osrm/switzerland-latest.osm.pbf -OutputDirectory .local/osrm-rebuilt -VerifyOnly

# Nouvelle destination obligatoire. Aucun écrasement des données existantes.
powershell -NoProfile -File infra/osrm/prepare.ps1 -PbfPath .local/osrm/switzerland-latest.osm.pbf -OutputDirectory .local/osrm-rebuilt
```

Après le pull du digest, les conteneurs de préparation sont sans réseau. Étapes : `osrm-extract`, `osrm-partition`, `osrm-customize`, copie du binaire provenant de la même image, manifeste SHA256 de tous les fichiers et archive `osrm-ch-v26.10.0.tar`. Le hash de cette nouvelle archive est écrit à côté. Le hash de l'archive historique n'est pas un résultat attendu de ce nouveau conditionnement : les métadonnées du tar peuvent varier. La reproductibilité porte sur les entrées verrouillées, les commandes et les fichiers vérifiables, pas sur une promesse de tar bit-à-bit identique.

Ne pas committer PBF, graphes, binaires, archives ni traces personnelles. Conserver l'attribution OpenStreetMap/Geofabrik et les notices des données lors d'une redistribution.

## Préparer une installation ultérieure autorisée

**Ces étapes ne sont pas exécutées par les scripts livrés. Avant toute modification du homelab, y compris création d'un CT, faire et vérifier une nouvelle sauvegarde de la base.** `pg_restore --list` et `pg_restore --file=/dev/null` contrôlent la lecture de l'archive, pas une restauration sur une base d'essai.

Sur CT117 dédié seulement, avec accès console de secours :

1. Vérifier le SHA256 du tar à l'arrivée, extraire dans un nouveau répertoire de version non actif et exécuter `sha256sum -c SHA256SUMS` dans ce répertoire.
2. Installer le binaire validé dans `/opt/osrm/v26.10.0/osrm-routed` et vérifier `--version`, `--help` et `ldd` sur la cible. Installer les bibliothèques nécessaires avant de fermer l'egress. Les fichiers de graphes restent lisibles par le compte système `osrm`, non modifiables par lui.
3. Placer les graphes dans `/srv/osrm/ch-20261020`, puis préparer le lien `/srv/osrm/current`. Le préfixe `switzerland-latest.osrm` désigne un ensemble de fichiers `.osrm.*`, pas un fichier obligatoire portant ce seul nom.
4. Relire ensemble IP d'écoute dans `drivy-osrm.service`, `api_ip`, `host_ip`, `admin_lan` dans `drivy-osrm.nft`. Le port moteur 5000 n'est accessible que depuis CT114 `.153` et l'hôte `.106`. SSH reste ouvert au LAN administratif comme dans le durcissement rapporté. Aucun accès moteur pour tout le LAN.
5. Installer le modèle nft dans `/etc/nftables.conf` uniquement dans CT117 dédié, après sauvegarde de son ruleset actuel. Il contient **`flush ruleset`** : ne jamais l'appliquer à l'hôte Proxmox, à CT114 ou à un serveur partagé. Contrôler `nft -c -f /etc/nftables.conf` avant application.
6. Installer l'unité, activer nftables avant OSRM puis relire `systemctl cat drivy-osrm`, le ruleset et l'écoute réelle. Le service dépend de nftables, fonctionne sous `osrm`, interdit les core dumps et ne conserve ni stdout ni stderr. Ne pas activer les logs de requêtes, même pour diagnostiquer une erreur.
7. Vérifier santé depuis CT114 et l'hôte avec une route **synthétique**, en supprimant le corps de réponse, et vérifier le refus depuis une machine non autorisée. L'écoute n'est pas sur `127.0.0.1` : la santé utilise l'adresse privée `.158`.

```sh
curl --noproxy '*' -fsS --max-time 5 -o /dev/null \
  'http://192.168.1.158:5000/route/v1/driving/6.9311,46.9930;6.9500,47.0010?overview=false'
```

Le service reprend les options du durcissement du 20 octobre : `--algorithm mld --ip 192.168.1.158 --port 5000 --threads 2 --max-matching-size 100`. **Aucune autre option `--max-*` n'est ajoutée.** En particulier, les plafonds route/table/trip/nearest du premier script local ne sont pas repris. Limiter le matching n'éteint pas les autres endpoints. Le cloisonnement est assuré par l'écoute privée et le pare-feu.

La sortie réseau est fermée par défaut, sauf boucle locale et réponses aux connexions établies. Une maintenance de paquets demande une ouverture contrôlée et temporaire, jamais un repli permanent vers `output accept`. Les connexions déjà établies restent permises par conntrack. Contrôler les nouveaux flux après application et redémarrage.

`MemoryMax=1200M` correspond à 1 258 291 200 octets, pas à la RSS du moteur. La mesure initiale du cgroup est proche de ce plafond et comprend du cache de fichiers. Requalifier la marge sous charge, sur démarrage à froid et pendant une mise à jour. L'absence d'OOM observée ne prouve pas une capacité de production.

## Benchmark synthétique sans jeton

Utilise `createMapMatcher` et `matchTrack` de l'application. Aucun accès aux captures, à la base ni à un fichier de jeton. Les moteurs publics et les URLs avec identifiants/requête/fragment sont refusés. Le seul argument est une origine OSRM privée.

```sh
node --import tsx --test infra/osrm/compare.test.mts
node --import tsx infra/osrm/compare.mts http://127.0.0.1:15000
```

Exemple de moteur éphémère local sous **cmd.exe**, données déjà préparées :

```bat
docker run --detach --rm --name drivy-osrm-synthetic-local --read-only --cap-drop ALL --security-opt no-new-privileges --log-driver none --publish 127.0.0.1:15000:5000 --volume "%cd%/.local/osrm:/data:ro" ghcr.io/project-osrm/osrm-backend@sha256:55dbfd47d984c2cacd64e32901b4321c86b5ec761438e69aa053dc78698a786f osrm-routed --algorithm mld --threads 2 --max-matching-size 100 /data/switzerland-latest.osrm
node --import tsx infra/osrm/compare.mts http://127.0.0.1:15000
docker stop drivy-osrm-synthetic-local
```

Attendre que le moteur soit prêt avant la mesure. L'exemple ne configure pas le homelab. Le conteneur local écoute dans son espace réseau, mais Docker ne publie le port que sur la boucle locale Windows.

Corrections par rapport au prototype `.local/osrm/compare.mts` :

- Arrêt imposé au milieu du parcours, 21 échantillons stationnaires couvrant exactement 20 secondes. Le bruit de mesure reste actif pendant l'arrêt.
- Couverture : ensemble des couples `(segmentId, sequence)` réellement présents dans les plages retenues. Une borne commune ne compte plus deux fois, une séquence absente n'est pas inventée. Il s'agit d'une couverture des plages, pas du nombre d'ancres directement matchées.
- Écart géométrique : projection de chaque sommet recalé sur les segments de la polyligne génératrice complète. Ce n'est plus la distance aux seuls échantillons distants de 11 mètres. La projection locale est adaptée à ce court parcours suisse, pas aux pôles ou à l'antiméridien.
- Maximum réel à `p=1`, valeurs absentes à `null`, erreurs sans URL ni réponse brute. Quantiles par rang inférieur `floor(p*(n-1))`, sans interpolation. Quatre appels ne permettent pas de caractériser la latence p95 en production.

`baseline-synthetic-20261020.json` conserve les deux exécutions locales. **OSRM produit lui-même la route de référence : un faible écart ne prouve aucune supériorité sur Mapbox ni aucune fidélité à un trajet réel.** Une route incorrecte mais parallèle, une lacune, un retour en arrière ou une erreur temporelle peuvent être mal représentés par cette seule métrique orientée. La qualification exige un corpus indépendant et une revue du replay.

## Vérification disponible et limites

```powershell
powershell -NoProfile -File infra/osrm/prepare.test.ps1
```

Ce test remplace Docker : il valide passage des arguments, digest, réseau désactivé, chemins avec espaces, hash de l'archive, refus d'écrasement et arrêt sur erreur. Il ne valide pas le retraitement complet de la Suisse. Le mode `-VerifyOnly` a aussi été exécuté sur le PBF réel. La préparation complète avec ce nouveau script reste à rejouer.

L'image réelle épinglée a répondu `v26.10.0`, son aide a été lue, son initialisation `--trial` et deux benchmarks ont réussi localement. `--trial` effectue tout de même un bind : pour le test local, l'adresse a été remplacée par `127.0.0.1`. Une tentative avec l'adresse du CT absente de Docker a échoué au bind, pas à l'analyse des options.

Les tests locaux ont utilisé Node **v26.8.1**, alors que le dépôt exige Node **24**. Le passage sur le runtime de référence reste à qualifier. Aucun résultat PostgreSQL, iOS ou terrain n'est déduit de ces tests.
