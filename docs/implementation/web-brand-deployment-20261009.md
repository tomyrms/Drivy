# Mise en ligne du branding web — 9 octobre 2026

Déploiement demandé explicitement par le porteur après constat que le branding n’était pas visible sur le portail. Mise en service à 14:36 Europe/Zurich, depuis `b710303c40b8f4462e8a4b39817544ecb53bde65`, branche `claude/marque-la-trace-20261006`. La passe `codex/stabilite-parcours-20261009` reste indépendante : aucun de ses fichiers locaux ni son commit `083fbc0` n’entre dans cette livraison.

## Version en service

- Web : `/opt/drivy-refonte/web-releases/b710303c40b8f4462e8a4b39817544ecb53bde65/apps/web`.
- Un seul réglage systemd ajouté : `/etc/systemd/system/drivy-refonte-web.service.d/90-brand-web-release.conf`, avec `WorkingDirectory` vers cette release web.
- API et lien partagé `/opt/drivy-refonte/current` : toujours `ef0ea216d2cdcff183e9b6446c59b8c387b78bfd`. PID API 148 identique avant/après, répertoire réel identique. Le service web seul a redémarré, PID 549 → 10537.
- Configuration privée web, identité, proxy et filtrage conservés. Les sessions navigateur en mémoire du web sont renouvelées par ce redémarrage.

Les 63 fichiers sources du web précédemment servi correspondent aux empreintes Git de `ef0ea216`. Le diff vers `b710303` contient uniquement 14 fichiers de marque : logo, couleurs, icônes, manifeste et autorisation CSP `manifest-src 'self'`, avec son test. Les dépendances et les règles métier sont identiques.

## Préparation et contrôles

Sauvegarde privée de `drivy_refonte` réalisée dans CT113 avant la bascule, mode 0600, catalogue vérifié avec `pg_restore --list`. Aucune base `drivy_web` n’est présente dans cet environnement. Aucune migration n’est exécutée.

L’archive Git contient uniquement `apps/web`. Son empreinte SHA-256, contrôlée après transfert, est `e42a34824de9c5a7ca12ffd933aba50563849536a46ca5311d1b3a96b874697e`. Compilation Linux avec Node verrouillé v24.21.0 : `npm ci --ignore-scripts --include=dev`, `npm run build`, puis `npm prune --omit=dev --ignore-scripts`. Les deux premières tentatives de préparation se sont arrêtées avant installation : filtre du dossier parent `apps` et argument d’extraction incompatible avec Python 3.11.2. Elles ont été corrigées avant la construction ; aucun service actif n’a été modifié par ces tentatives.

Après bascule :

- Service web actif et processus dans la release attendue ; API et lien partagé inchangés.
- Onze fichiers publics, dont HTML, JS, CSS, police, icônes et manifeste : HTTP 200 et SHA-256 identiques au build. Contrôles HTTPS réalisés avec PowerShell ; la sonde Python reçoit un refus HTTP 403 sur les fichiers publics, alors que le navigateur et PowerShell les servent correctement.
- `/app`, `/app/invitation`, `/app/gestion` : HTTP 200 ; HTML sans cache, CSP du manifeste présente.
- Session anonyme : HTTP 200, `authenticated: false`, `no-store`. API `/refonte/v1/me` sans jeton : HTTP 401 et `no-store`.
- Navigateur intégré sur le portail anonyme en sombre : logo rendu, cobalt `#91b5ff`, manifeste `/app/site.webmanifest`, aucune erreur ni alerte dans la console. [Capture de l’en-tête et de la connexion](assets/web-brand-deployment-20261009/branding-publie.png).

[Preuve de déploiement](proofs/web-brand-deployment-20261009.json). Les parcours connectés et les données de l’école ne sont pas modifiés ou rééprouvés par ce contrôle de publication.

## Retour arrière et prochain déploiement

La release précédente est conservée dans `/opt/drivy-refonte/releases/ef0ea216d2cdcff183e9b6446c59b8c387b78bfd`. Tant que `current` pointe vers celle-ci, le retour arrière consiste à retirer uniquement le fichier `90-brand-web-release.conf` ajouté ci-dessus, exécuter `systemctl daemon-reload`, puis redémarrer uniquement `drivy-refonte-web`. Aucun retour de données n’est nécessaire pour ce changement graphique.

**Le prochain déploiement global doit traiter explicitement ce drop-in.** Bascule de `current` seule ne met plus le web à jour : intégrer les changements de marque dans la nouvelle version, puis soit supprimer ce drop-in pour reprendre `current/apps/web`, soit le remplacer par le chemin de la nouvelle release web isolée. Vérifier le répertoire réel de chaque processus après redémarrage. Ne pas lancer les installateurs d’API ou de bootstrap OIDC pour une simple mise à jour de marque web.
