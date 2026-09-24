# Déploiement API et web G1C

État au 24 septembre 2026, 17:32 UTC : **API 003 et portail web déployés** depuis `6ffc1036890ccc3d8232f5f8b90be4d77f6db195`. Le portail répond sous `https://drivy.shulker.ch/app`. Le scope `email` du client Apple et le nouveau client confidentiel web sont configurés. **Le transport SMTP externe et l'inscription publique restent indisponibles** ; aucune livraison d'invitation hébergée n'est revendiquée.

## Opération exécutée et preuves

Le snapshot Git comprend uniquement les manifests, API, web et fichiers de déploiement. Son SHA-256 de transfert est `7fb0457f7f2339feb82f56196579aeb8ce3f56530ebbca25cc2c4093e66a785e`. Une sauvegarde privée `pg_dump -Fc` de la base refonte, vérifiée par `pg_restore --list`, précède 003. Le propriétaire restreint a appliqué la migration ; les quinze tables ont ENABLE/FORCE RLS et le contrôle de connexion runtime sans contexte est réussi. Les rôles mailer sont préparés sans credential : aucun worker n'est démarré, aucun HBA mailer n'est ajouté.

Les compilations API et web ont réussi sous Linux depuis leurs lockfiles, avant le changement atomique de `current`. Les processus API et web utilisent réellement les répertoires de cette release. Les quatre unités API/web/identité/filtrage sont actives ; le web est activé au démarrage. Au relevé, mémoire systemd : API 43,5 Mo, web 44,0 Mo, identité 424,5 Mo. Ce relevé au repos n'est pas un test de charge.

Le client OIDC web a son secret aléatoire dans un coffre root/0600 ; callback exact, client confidentiel, PKCE S256 et scopes basic/email/profile ont été relus. Le filtre des ports 3001/3002/8081 a été validé puis appliqué atomiquement à la seule table nft de la refonte. Le Caddyfile **complet** utilisant le nouveau snippet a été validé avant rechargement ; le fichier principal, contenant notamment les destinations de l'ancien service, est inchangé.

[check-deployed-web.mjs](../../scripts/dev/check-deployed-web.mjs) a réussi **11 contrôles** dans Edge éphémère sur HTTPS public : accueil/CSP, cookie `__Host` Secure/HttpOnly/SameSite, connexion réelle par le formulaire IdP et retour BFF, rotation de session/CSRF, absence de jeton OAuth au frontend, `403 IDENTITY_NOT_LINKED` pour la sonde sans droits métier, refus des origines et CSRF obsolètes, puis déconnexion/401. Le compte sonde a été supprimé et son absence relue. Le compte `luc` n'a pas été utilisé ou modifié par cette recette.

Les contrôles HTTP supplémentaires retrouvent `/app` et `/app/bff/session` en 200/no-store, `/refonte/v1/me` sans jeton en 401/no-store, et les chemins publics admin/master/health/metrics en 404. Les connexions LAN directes aux trois ports sont refusées. La base contient toujours une école et une adhésion, zéro élève, formation, invitation ou courrier en attente. [Preuve de déploiement](proofs/g1c-deployment-2026-09-24.json), [preuve HTTPS](proofs/web-https-2026-09-24.json).

## Artefacts préparés

- `install-api-release.py` reconnaît un snapshot contenant `apps/web`, installe son lockfile indépendant avec `--ignore-scripts`, compile le BFF et le frontend, puis retire les dépendances de développement avant de changer `current`. Inclure `apps/web` dans le prochain `git archive`, en plus des sources API, des manifests racine et de `infra/deploy`.
- `drivy-refonte-web.service` utilise un compte système distinct `drivy-web`, le runtime Node maintenu, la configuration privée `/etc/drivy-refonte/web.env` et le port `192.168.1.153:3002`. Les sessions sont en mémoire : un redémarrage déconnecte les navigateurs.
- `drivy-web-client.json` décrit un client OIDC confidentiel, code + PKCE S256, sans password grant, service account ou wildcard de callback. Ajouter le secret aléatoire uniquement lors du provisionnement serveur ; ne jamais le placer dans ce JSON public. Callback exact : `https://drivy.shulker.ch/app/bff/callback`.
- `install-web-service.py --apply /root/drivy-web-bootstrap.json` lit `{oidcClientSecret:…}` depuis un fichier root privé, crée le compte système et l'unité, et écrit l'environnement root:root/0600. Il ne crée pas le client OIDC, n'ouvre pas le proxy et ne démarre aucun service.
- La proposition nftables ajoute `3002` aux ports de la seule table `drivy_refonte`, accessible depuis Caddy CT109 ou loopback. La proposition Caddy ajoute `/app` sans retirer son préfixe et exclut ces accès des logs, y compris le callback OAuth. Les handlers existants hors refonte restent à conserver lors de l'intégration dans le vrai Caddyfile.

## Procédure de déploiement et complément SMTP restant

1. Conserver une sauvegarde privée de `drivy_refonte`. Préparer les rôles mailer avec le script SQL dédié avant 003 sous le propriétaire restreint. Lors du raccordement SMTP, générer et stocker leur credential séparément et étendre HBA uniquement au rôle mailer, à la base refonte et au client CT114, sous TLS vérifié.
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

Ces contrôles de préparation ont précédé l'installation et la recette HTTPS décrites en tête. Le SMTP externe, la charge, l'inscription publique et la disponibilité durable restent à qualifier. Les preuves fonctionnelles locales sont séparées dans [la recette d'entrée web](recette-entree-web.md). La recette publique utilise une sonde sans lien métier et ne qualifie pas l'acceptation d'une invitation sur l'hébergement.
