# Déploiement de Registre Drivy — 14 octobre 2026

Déploiement explicitement demandé par le porteur pendant la réalisation. **Publié à 00:10:45 Europe/Zurich** sur [Drivy](https://drivy.shulker.ch/app/), version `1c43c35f3bbb6389719bdc55ebf0ee7f0d34b6fa`, branche `codex/portail-registre-20261013`.

## Préparation et sauvegarde

Archive Git limitée à `apps/web`, transfert SHA-256 vérifié, build Linux avec Node **v24.21.0** et dépendances verrouillées, puis retrait des dépendances de développement. La release était isolée pendant la compilation. Les deux workflows de qualification du SHA exact ont réussi avant activation : [439 tests API/PostgreSQL et 233 tests web, types/builds/docs](https://github.com/tomyrms/Drivy/actions/runs/38475181117) ; [80 contrôles intégrés OIDC/BFF/API/PostgreSQL](https://github.com/tomyrms/Drivy/actions/runs/38475181157).

Avant toute bascule : `pg_dump -Fc` de `drivy_refonte` dans CT113, fichier privé 0600 synchronisé, **catalogue vérifié avec `pg_restore --list`**. Taille : **1,023,304 octets**. Chemin : `/root/drivy_refonte-before-web-1c43c35f3bbb6389719bdc55ebf0ee7f0d34b6fa-20261013T221042Z-d571a5e51385.dump`. Aucune restauration de test n’est revendiquée.

Les **32 migrations** déjà présentes et leurs empreintes correspondent à la base active. Aucune migration exécutée. Le code API et ses dépendances sont identiques entre la base déployée `c5bfb73` et la release testée ; le serveur BFF et ses dépendances ne changent pas depuis `bad540b`.

## Bascule et contrôle public

- Web et BFF : `/opt/drivy-refonte/web-releases/1c43c35f3bbb6389719bdc55ebf0ee7f0d34b6fa/apps/web` dans CT114.
- Override `/etc/systemd/system/drivy-refonte-web.service.d/90-web-release.conf` remplacé atomiquement pour viser la nouvelle release. L’ancienne valeur est conservée dans le reçu.
- Seul `drivy-refonte-web` redémarre ; service actif et répertoire du processus vérifié. API, identité et lien partagé `current` inchangés. Environnements privés inchangés, vérifiés par empreinte sans publier leur contenu ou leur empreinte.
- **19 contrôles HTTPS réussis** : les 12 fichiers publics correspondent par SHA-256 au build, cinq entrées HTTP 200, session anonyme attendue et refus API HTTP 401 sans jeton. Cache immuable des assets et `no-store` des entrées conservés.
- Page publique anonyme chargée dans le navigateur, marque et connexion visibles, **aucune erreur ni alerte console**. Capture brute conservée. Aucune commande métier effectuée sur les données de production.

[Reçu de déploiement](proofs/web-registre-20261013/deployment.json) · [Contrôles HTTPS](proofs/web-registre-20261013/deployment-https.json) · [Capture publique](proofs/web-registre-20261013/production-anonymous.png) · [Qualification et limites](web-registre-verification-20261014.md).

Le redémarrage du BFF renouvelle les sessions en mémoire : une reconnexion peut être demandée. Zoom natif, lecteur d’écran, Safari et recette avec une auto-école restent à qualifier ; les essais de données synthétiques ne valent pas cette recette.

## Retour arrière

La release précédente reste disponible : `/opt/drivy-refonte/web-releases/bad540b2e6ed9a9b4967229edf3997ea3b087424/apps/web`. Pour revenir au portail précédent, restaurer ce `WorkingDirectory` dans l’override, puis `systemctl daemon-reload` et `systemctl restart drivy-refonte-web`. Vérifier le répertoire réel du processus et les routes publiques. Aucune restauration de la base n’est nécessaire pour ce retour web.

**Au prochain déploiement global**, traiter cet override explicitement : l’actualiser ou le retirer une fois la nouvelle release globale intégrée. Changer uniquement `current` ne met pas le portail à jour.
