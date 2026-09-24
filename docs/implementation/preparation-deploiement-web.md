# Préparation du déploiement web G1C

État au 24 septembre 2026 : **préparé, pas appliqué**. Le service public reste sur la release G1B `c3e5e67`. L'ajout du scope `email` au client Apple est le seul changement d'identité déjà exécuté pour G1C ; il ne configure aucun transport SMTP externe.

## Artefacts préparés

- `install-api-release.py` reconnaît un snapshot contenant `apps/web`, installe son lockfile indépendant avec `--ignore-scripts`, compile le BFF et le frontend, puis retire les dépendances de développement avant de changer `current`. Inclure `apps/web` dans le prochain `git archive`, en plus des sources API, des manifests racine et de `infra/deploy`.
- `drivy-refonte-web.service` utilise un compte système distinct `drivy-web`, le runtime Node maintenu, la configuration privée `/etc/drivy-refonte/web.env` et le port `192.168.1.153:3002`. Les sessions sont en mémoire : un redémarrage déconnecte les navigateurs.
- `drivy-web-client.json` décrit un client OIDC confidentiel, code + PKCE S256, sans password grant, service account ou wildcard de callback. Ajouter le secret aléatoire uniquement lors du provisionnement serveur ; ne jamais le placer dans ce JSON public. Callback exact : `https://drivy.shulker.ch/app/bff/callback`.
- `install-web-service.py --apply /root/drivy-web-bootstrap.json` lit `{oidcClientSecret:…}` depuis un fichier root privé, crée le compte système et l'unité, et écrit l'environnement root:root/0600. Il ne crée pas le client OIDC, n'ouvre pas le proxy et ne démarre aucun service.
- La proposition nftables ajoute `3002` aux ports de la seule table `drivy_refonte`, accessible depuis Caddy CT109 ou loopback. La proposition Caddy ajoute `/app` sans retirer son préfixe et exclut ces accès des logs, y compris le callback OAuth. Les handlers existants hors refonte restent à conserver lors de l'intégration dans le vrai Caddyfile.

## Ordre avant exposition

1. Conserver une sauvegarde privée de `drivy_refonte`. Préparer les rôles mailer avec le script SQL dédié avant 003 sous le propriétaire restreint ; générer et stocker leur credential séparément. Étendre HBA uniquement au rôle mailer, à la base refonte et au client CT114, sous TLS vérifié.
2. Déployer le snapshot approuvé, migrer et vérifier la connexion runtime et les quinze tables FORCE RLS. Le script de release ne démarre pas les services.
3. Créer le client OIDC web avec son secret privé, préparer son unité et sa configuration. Relire client confidentiel, callback, PKCE et scopes ; ne pas remplacer silencieusement un client existant dont le secret ne correspond pas.
4. Contrôler le filtrage et le Caddyfile complet avant application atomique. Démarrer uniquement les services refonte concernés, puis vérifier les réponses HTTPS, cookies `__Host` et absence de port BFF ouvert au LAN.
5. Raccorder le transport SMTP réel et son worker distinct avant de présenter les invitations comme envoyables. Configurer également l'identité pour la vérification d'adresse. L'absence de transport conserve le refus explicite `INVITATION_DELIVERY_UNAVAILABLE` ; aucun message externe de recette n'est envoyé automatiquement.

La configuration/adoption de politique ou l'activation de « Luc auto école » ne font pas partie de ce déploiement. Aucun élève, catalogue, prix ou formation de démonstration n'est injecté dans la base hébergée.

## Contrôles de préparation exécutés

- Syntaxe Python des installateurs et JSON du client valide.
- `npm ci --prefix apps/web --ignore-scripts` puis build réussis sur le poste ; la CI utilise désormais les mêmes options d'installation web.
- Le Caddy installé dans CT109 adapte la proposition dans un Caddyfile minimal indépendant. Le fichier temporaire a été supprimé ; aucun Caddyfile réel, secret DNS ou service n'a été modifié. Cette adaptation n'est pas la validation du fichier complet futur.
- `nft --check` dans CT114 accepte le lot proposé sans l'appliquer.

Ces contrôles ne qualifient pas encore l'installation Linux du web, sa mémoire, le SMTP externe ou sa disponibilité publique. Les preuves fonctionnelles locales sont séparées dans [la recette d'entrée web](recette-entree-web.md).
