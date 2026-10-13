# Déploiement du portail Studio — 14 octobre 2026

Déploiement explicitement demandé par le porteur pendant la réalisation. **Publié à 01:01:46 Europe/Zurich** sur [Drivy](https://drivy.shulker.ch/app/), version `2b4ca811a777d6f7283fd6910bd179451acc0cba`, branche `codex/portail-studio-20261014`.

## Qualification avant bascule

Les deux workflows du SHA exact ont réussi : [439 tests API/PostgreSQL et 233 tests web, typage, builds et intégrité documentaire](https://github.com/tomyrms/Drivy/actions/runs/38481209557) ; [80 contrôles intégrés Chromium, OIDC, BFF, API et PostgreSQL](https://github.com/tomyrms/Drivy/actions/runs/38481209552). L’Agenda final de cette recette a été inspecté : les informations du moniteur et du lieu sont séparées, après correction de la priorité d’une règle CSS révélée par la capture du build précédent.

Archive Git limitée à `apps/web`, transfert vérifié par SHA-256, build Linux isolé sous Node **v24.21.0**, dépendances verrouillées et retrait des dépendances de développement avant activation. Le code API et ses dépendances sont identiques à la base déjà en service `c5bfb73060405de9aa0b57b8197e79954ac85588`. Aucun changement natif Apple.

## Sauvegarde et bascule

Avant toute modification du service : `pg_dump -Fc` de `drivy_refonte` dans CT113, fichier privé 0600 synchronisé, puis **catalogue vérifié par `pg_restore --list`**. Taille : **1 023 446 octets**. Chemin : `/root/drivy_refonte-before-web-2b4ca811a777d6f7283fd6910bd179451acc0cba-20261013T230144Z-241b1b53ffbc.dump`. Aucune restauration d’essai n’est revendiquée.

Les **32 migrations** existantes et leurs empreintes sont conformes à la base active ; aucune migration exécutée. Les processus et configurations privées attendus ont été revérifiés avant activation, sans publier le contenu ni les empreintes des environnements privés.

Le web et son BFF utilisent `/opt/drivy-refonte/web-releases/2b4ca811a777d6f7283fd6910bd179451acc0cba/apps/web` dans CT114. L’override `/etc/systemd/system/drivy-refonte-web.service.d/90-web-release.conf` est remplacé atomiquement. Seul `drivy-refonte-web` redémarre ; son état actif et le répertoire réel de son processus sont vérifiés. API, identité, lien partagé `current` et environnements privés restent inchangés.

## Vérification publiée

**19 contrôles HTTPS réussis** : les 12 fichiers publics correspondent au build par SHA-256, cinq routes d’entrée répondent HTTP 200, le BFF retourne la session anonyme attendue et l’API refuse l’accès sans jeton avec HTTP 401. Les entrées gardent `no-store` et les assets leurs règles de cache.

La page publique anonyme a été chargée et capturée dans le navigateur après publication : marque, apparence et connexion visibles ; aucune erreur ni alerte console. Aucune commande métier n’a été effectuée sur les données de production. Une reconnexion peut être demandée après redémarrage des sessions BFF en mémoire.

[Reçu](proofs/web-studio-20261014/deployment.json) · [Contrôles HTTPS](proofs/web-studio-20261014/deployment-https.json) · [Capture publique](proofs/web-studio-20261014/production-anonymous.jpg) · [Qualification et limites](web-studio-verification-20261014.md) · [Galerie avant/après](proofs/web-studio-20261014/index.html).

## Retour arrière

La version précédente reste disponible : `/opt/drivy-refonte/web-releases/1c43c35f3bbb6389719bdc55ebf0ee7f0d34b6fa/apps/web`. Pour revenir à cette version, restaurer ce `WorkingDirectory` dans l’override, puis exécuter `systemctl daemon-reload` et `systemctl restart drivy-refonte-web`. Vérifier le répertoire du processus et les routes publiques. Ce retour web ne requiert aucune restauration de base.

Au prochain déploiement global, actualiser ou retirer explicitement cet override lorsque la nouvelle version globale intègre le portail : changer uniquement `current` ne met pas le web à jour.
