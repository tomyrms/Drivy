# Déploiement isolé de la refonte G1A

Déploiement initial exécuté le 24 septembre 2026, à la demande du porteur sur son hébergement existant. API G1A et identité sont accessibles en HTTPS ; les preuves détaillées sont consignées dans `STATUS.md`. Aucun jeu de démonstration n’est chargé dans les bases hébergées.

## Implantation

| Élément | Emplacement nouveau | Ancien service conservé |
|---|---|---|
| API Node 24.21.0 | CT114, `192.168.1.153:3001`, `/opt/drivy-refonte` | `/opt/drivy-api`, Node 22, PM2, port 3000 |
| Keycloak 26.7.4 / JDK 21 | CT114, port 8081, contexte `/identity` | Aucun changement de PM2 |
| Données métier PostgreSQL 16 | CT113, base `drivy_refonte` | Bases et rôles antérieurs inchangés |
| Identité PostgreSQL 16 | CT113, base `drivy_identity` | Aucune table Keycloak dans la base métier |
| HTTPS Caddy 2.11.2 | CT109, `drivy.shulker.ch` | `/knowledge/*` et destination par défaut conservés |

L’API publique est `https://drivy.shulker.ch/refonte`. L’issuer exact est `https://drivy.shulker.ch/identity/realms/drivy`. Caddy retire `/refonte` avant de joindre l’API ; il conserve `/identity` pour Keycloak. L’administration et le realm `master` ne sont pas publiés. Les ports 3001/8081 acceptent uniquement CT109 et la boucle locale, au moyen du filtrage dédié. Le management Keycloak écoute seulement `127.0.0.1:9001`.

TLS est terminé par Caddy ; son lien vers CT114 est HTTP sur le réseau privé filtré. PostgreSQL utilise TLS avec vérification complète du certificat et du nom `drivy-db.tailb60275.ts.net`, résolu explicitement vers `192.168.1.151`. Le certificat public est obtenu via SSH avec clé d’hôte déjà approuvée ; aucune clé privée TLS n’est copiée. Ni `rejectUnauthorized=false`, ni `sslmode=prefer`, ni `start-dev` ne sont utilisés.

## Fichiers et responsabilité

Tous les scripts sont dans `infra/deploy/`. Les scripts d’installation réclament `--apply` pour distinguer leur exécution d’une simple lecture. Ils ne pilotent ni SSH, ni Caddy, ni le pare-feu, ni le démarrage des unités. L’opérateur applique les phases ci-dessous. Ils refusent les collisions plutôt que remplacer un objet existant ; après un échec partiel, examiner les seuls objets refonte avant de reprendre. Ne pas supprimer les bases pour rendre un script rejouable.

- `provision-databases.py` : CT113, création de deux bases et des nouveaux rôles. Les passwords aléatoires restent dans `/root/drivy-refonte-bootstrap.json`, root `0600`. Seuls leurs vérificateurs SCRAM sont transmis à PostgreSQL ; le script ne restitue aucun SQL ni erreur sensible.
- `install-runtimes.py` et `runtime-lock.json` : CT114, téléchargements officiels avec SHA-256 verrouillé ; installation privée de Node, Temurin JDK et Keycloak. Le Node système n’est pas remplacé.
- `install-services.py` : comptes système dédiés, secrets root `0600`, certificat public `0644`, répertoire `/etc/drivy-refonte` `0755`, build Keycloak optimisé et unités systemd. Les unités ne sont ni activées ni démarrées.
- `install-api-release.py` : installation npm depuis le lock, compilation, migrations hashées, vérification du rôle runtime et de RLS, retrait des dépendances de développement, puis mise à jour de `/opt/drivy-refonte/current`. Aucun redémarrage automatique.
- `pg-hba-refonte.conf`, `ingress-refonte.nft`, `drivy-refonte-ingress.service`, `caddy-refonte.caddy` : ajouts limités aux nouvelles bases, nouveaux rôles, nouveaux ports et nouveaux chemins. Le filtrage est une dépendance obligatoire des deux services.
- `provision-school.mjs` : provisionnement initial contrôlé de l’identité et de l’école, procédure séparée. Il ne constitue pas une API d’administration publique ni un seed.

## 1. Préparer PostgreSQL dans CT113

Vérifier PostgreSQL 16, l’absence des deux bases et des quatre noms de rôles, et l’espace disque. Les noms réservés sont `drivy_refonte`, `drivy_identity`, `drivy_refonte_owner`, `drivy_refonte_runtime`, `drivy_identity_owner` et `drivy_app`. Cette dernière appellation NOLOGIN provient de la migration canonique de réalisation, pas d’un rôle ancien réutilisé.

```sh
python3 /root/drivy-deploy/provision-databases.py --apply
```

Le propriétaire de migration est sans SUPERUSER, BYPASSRLS, CREATEDB ou CREATEROLE ; il reçoit ADMIN OPTION sur le nouveau rôle NOLOGIN `drivy_app`, nécessaire au GRANT de la migration 001. Le runtime reçoit ce rôle sans ADMIN OPTION, reste NOINHERIT, n’est propriétaire d’aucune table et ne possède aucun droit de création. Keycloak possède sa propre base sous un troisième rôle de connexion.

Les bases sont créées explicitement en UTF8 depuis `template0`. Le cluster historique utilise SQL_ASCII par défaut : lors du premier déploiement, les deux bases de bootstrap encore sans compte utilisateur ont été conservées sous les noms `drivy_refonte_bootstrap_ascii_20260924` et `drivy_identity_bootstrap_ascii_20260924`, puis les bases définitives initialisées en UTF8. Les anciennes bases `drivy` et `drivy_test` n'ont pas été modifiées.

Insérer `pg-hba-refonte.conf` avant les règles générales existantes, sans les remplacer. Les seules connexions admises viennent de CT114 en TLS/SCRAM, vers la base prévue pour chaque rôle. Vérifier `pg_hba_file_rules` avant le rechargement de PostgreSQL. Conserver une sauvegarde du HBA précédent. Si un audit PostgreSQL supplémentaire est installé, vérifier qu’il ne journalise pas le texte des DDL de credentials ; les commandes du script désactivent la journalisation SQL pour leur seule session et n’envoient jamais les passwords en clair.

Transférer le coffre directement de CT113 vers CT114 par un canal SSH authentifié, avec mode `0600`, sans l’afficher ni le placer dans une archive Git/CI. Copier uniquement le certificat public PostgreSQL vers `/root/drivy-db-ca.crt` sur CT114. Ce certificat étant auto-signé, son empreinte obtenue par le canal SSH approuvé constitue la référence de confiance.

## 2. Préparer CT114 sans affecter l’ancienne API

Prérequis : `python3`, `openssl`, `tar`, `xz`, `useradd`, `nftables`, systemd et accès sortant HTTPS aux hôtes des archives/npm. Les paquets système manquants sont installés explicitement par l’opérateur. Réserver la capacité avant installation : CT114 dispose de 2 Gio de RAM et environ 3 Gio libres au relevé initial. Les trois archives sont supprimées automatiquement après extraction ; conserver seulement les releases nécessaires au retour arrière.

```sh
python3 /root/drivy-deploy/install-runtimes.py --apply
python3 /root/drivy-deploy/install-services.py --apply /root/drivy-refonte-bootstrap.json /root/drivy-db-ca.crt
systemd-analyze verify /etc/systemd/system/drivy-refonte-api.service /etc/systemd/system/drivy-refonte-identity.service /etc/systemd/system/drivy-refonte-ingress.service
```

Le script vérifie le certificat pour son hostname, ajoute seulement le mapping DNS manquant dans `/etc/hosts` et refuse une collision avec une autre IP. Les trois connexions DB utilisent `sslmode=verify-full` et `/etc/drivy-refonte/db-ca.crt`.

Keycloak utilise un heap borné à 512 Mio, un cache local et au plus huit connexions DB. systemd borne son processus à 1 Gio ; l’API dispose de 128 Mio de heap V8 et de 256 Mio au total. Ces budgets sont des paramètres initiaux, pas une qualification de charge. Surveiller RSS, mémoire du conteneur, temps de connexion et éventuels OOM pendant la première mise en service.

CT114 interdit la création de namespaces de montage par systemd (`226/NAMESPACE`). Les unités adaptées à ce conteneur n'utilisent donc pas `ProtectSystem`, `PrivateTmp` ou les autres protections nécessitant ces montages. Le confinement LXC reste inchangé ; comptes de service sans privilèges, `NoNewPrivileges`, fichiers de code/configuration appartenant à root, restrictions réseau et limites mémoire restent appliqués. Le chargeur nft possède uniquement `CAP_NET_ADMIN`. Les trois unités ont passé `systemd-analyze verify` et démarrent réellement dans CT114.

Le realm `drivy` ne crée aucun utilisateur. Il impose HTTPS, PKCE S256, code flow avec client public `drivy-apple`, audience `drivy-api`, callback exact `ch.drivy.qualification:/oauth/callback`, scopes `basic` et `profile`. `basic` fournit notamment `sub`. Password grant, implicit flow, comptes de service, inscription publique et offline access sont désactivés. Les refresh tokens standards sont renouvelés avec rotation ; session inactive 30 minutes, maximum 2 heures. L’application doit demander `openid profile`, sans `offline_access`.

Le compte `refonte-bootstrap` appartient uniquement au realm `master`, inaccessible publiquement. Son password reste dans `identity-bootstrap.env`. Après création/vérification d’un accès d’administration permanent interne, supprimer ce compte temporaire dans Keycloak et retirer le fichier bootstrap ; ne pas seulement retirer le fichier, ce qui laisserait le compte en base.

## 3. Installer une release et ses migrations

Créer un snapshot du commit vérifié incluant `package.json`, `package-lock.json`, `apps/api` et `infra/deploy`, sans `.git`, `.local`, exports historiques, `.env`, artefacts ni données. L’extraire comme root dans `/opt/drivy-refonte/releases/<SHA-complet>`. Inclure le manifest de commit/empreinte du transfert dans les preuves techniques, pas le coffre.

```sh
python3 /root/drivy-deploy/install-api-release.py --apply /opt/drivy-refonte/releases/<SHA-complet>
```

La migration utilise uniquement `MIGRATION_DATABASE_URL`, jamais le rôle runtime. Elle conserve son verrou transactionnel et ses hashes SHA-256. Le contrôle suivant utilise au contraire la vraie connexion runtime : absence de privilèges dangereux, présence des huit tables initiales et RLS forcée sur toutes les tables métier (treize après G1B), `SET LOCAL ROLE drivy_app` effectif et zéro personne visible sans contexte d’identité. Aucun seed n’est exécuté. Les secrets de migration ne figurent pas dans l’environnement du service API.

## 4. Filtrage, Caddy et démarrage

Vérifier les capacités LXC permettant nftables dans CT114. L’installateur copie les règles dans `/etc/drivy-refonte/ingress.nft`. L’unité `drivy-refonte-ingress.service` les vérifie puis les applique avant API et identité ; `Requires` et `After` empêchent le démarrage de ces dernières si le filtrage échoue, y compris au redémarrage du conteneur. Son état reste actif après exécution. Le lot nft recrée au besoin et vide uniquement la table `inet drivy_refonte`, puis remet ses règles atomiquement ; aucun flush global ni retrait des règles à l’arrêt de l’unité n’est effectué. La table a une politique générale ACCEPT et ne refuse que 3001/8081 aux sources autres que CT109/boucle locale. Ne pas changer la politique générale du pare-feu, les ports 3000/5432 d’autres services ou les règles globales de Proxmox. Si NET_ADMIN manque, ne pas contourner cette dépendance : préparer et qualifier une variante avec filtrage persistant Proxmox pour ce seul conteneur avant tout démarrage. Vérifier le filtrage effectif avant publication.

Importer `caddy-refonte.caddy` dans le site `drivy.shulker.ch`. Conserver `/knowledge/*` et le handle final vers `192.168.1.153:3000`. Le handle englobant ne sélectionne que `/refonte`, `/refonte/*` et `/identity*` ; il est trié avant le handle existant sans matcher. Son bloc `route` garantit que les seuls chemins publics d’identité sont servis avant le refus du reste de `/identity*`. `log_skip` neutralise les access logs pour les nouveaux parcours, afin de ne pas enregistrer les codes OAuth ni les recherches. Les requêtes métier et les événements utilisateurs Keycloak ne sont pas ajoutés aux logs applicatifs.

Valider le Caddyfile complet avec la version 2.11.2 déjà installée, puis le recharger. Un échec de validation ne doit jamais remplacer la configuration active. Démarrer les deux nouvelles unités seulement lorsque le filtrage et les connexions DB sont vérifiés :

```sh
systemctl start drivy-refonte-identity.service
systemctl start drivy-refonte-api.service
```

Contrôles sans afficher de jeton :

- Discovery publique : HTTP 200, issuer exact, endpoints sous `/identity/realms/drivy/`, support code/S256. JWKS : HTTP 200 et clés publiques attendues.
- `/identity/admin/`, `/identity/realms/master/`, `/identity/health`, `/identity/metrics` : refus HTTP 404 par Caddy. Ports directs 3001/8081 inaccessibles depuis une source LAN autre que CT109.
- `/refonte/v1/me` sans Bearer : HTTP 401 et `Cache-Control: no-store`, pas de contenu personnel. Une identité non liée : 403 `IDENTITY_NOT_LINKED`.
- Ancienne API et `/knowledge/*` : mêmes destinations et comportement qu’avant rechargement.
- Journaux, RSS et `systemctl is-active` des nouvelles unités : absence de secrets et service stable ; TLS PostgreSQL confirmé par `pg_stat_ssl` pour les trois rôles.

Après ces contrôles, activer les trois unités au démarrage. L’import `--import-realm` ignore un realm déjà présent ; il n’écrase pas une configuration vivante lors d’un redémarrage. Les modifications ultérieures du realm nécessitent une opération d’administration dédiée.

## 5. Première école et configuration Apple

Le porteur a retenu le compte `luc`, l’école `Luc auto école` et l’adresse de test `luc@example.com` pour le contact obligatoire de l’école. Cette adresse est une valeur d’essai autorisée, pas un contact validé. Le provisionnement utilise les vrais UUID Keycloak comme subject, un password temporaire généré côté serveur et l’action obligatoire `UPDATE_PASSWORD`. Le profil d’identité n’exige pas d’email inventé. La base métier reste vide jusqu’à cette opération explicite ; les données anciennes ne sont jamais importées.

Le fichier d’accès initial reste sous `/root` en mode `0600`, hors des logs et des artefacts publics. Le script de provisionnement vérifie la base/issuer, l’unicité de l’opération et les liens de reprise. Il restaure FORCE RLS dans la même transaction avant toute validation d’écriture.

Après vérification du parcours réel, compiler l’app avec les valeurs publiques :

```text
DRIVY_API_BASE_URL=https://drivy.shulker.ch/refonte
DRIVY_OIDC_ISSUER=https://drivy.shulker.ch/identity/realms/drivy
DRIVY_OIDC_CLIENT_ID=drivy-apple
```

Le bundle iOS reste `ch.drivy.qualification`, pour conserver la continuité des essais locaux G0. Aucun secret client n’est ajouté. L’installation/signature via iLoader et la connexion système sur appareil restent des vérifications distinctes de la compilation IPA.

## Retour arrière

Arrêter uniquement `drivy-refonte-api` et `drivy-refonte-identity`, puis retirer uniquement l’import des nouvelles routes Caddy et recharger sa configuration validée. L’ancienne API est restée active pendant toute l’opération. Conserver les nouvelles bases, secrets et releases pour diagnostic/reprise ; aucune commande DROP ou suppression récursive n’est prévue. Pour revenir à une release API précédente, choisir explicitement son SHA et vérifier la compatibilité des migrations avant de changer `current`.

## Références primaires

- [Keycloak 26.7.4 : proxy, hostname et chemins publics](https://github.com/keycloak/keycloak/blob/26.7.4/docs/guides/server/reverseproxy.adoc).
- [Keycloak 26.7.4 : administration temporaire](https://github.com/keycloak/keycloak/blob/26.7.4/docs/guides/server/bootstrap-admin-recovery.adoc) et [import de realm](https://github.com/keycloak/keycloak/blob/26.7.4/docs/guides/server/importExport.adoc).
- [Archives Node 24.21.0 et SHA-256](https://nodejs.org/dist/v24.21.0/SHASUMS256.txt), [release Keycloak 26.7.4](https://github.com/keycloak/keycloak/releases/tag/26.7.4), [Temurin JDK 21.0.12.1+1](https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.12.1%2B1).
- [Caddy handle_path](https://caddyserver.com/docs/caddyfile/directives/handle_path), [route](https://caddyserver.com/docs/caddyfile/directives/route), [reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), [log_skip](https://caddyserver.com/docs/caddyfile/directives/log_skip).
- [PostgreSQL 16 : vérification TLS client](https://www.postgresql.org/docs/16/libpq-ssl.html), [HBA](https://www.postgresql.org/docs/16/auth-pg-hba-conf.html) et [attributs des rôles](https://www.postgresql.org/docs/16/role-attributes.html).
