# Mise en ligne de la refonte web — 13 octobre 2026

Déploiement demandé explicitement par le porteur. Portail publié sur https://drivy.shulker.ch/app/ à **23:12 Europe/Zurich**, depuis `bad540b2e6ed9a9b4967229edf3997ea3b087424`, branche `codex/refonte-portail-web`.

## Version en service

- Web et BFF : `/opt/drivy-refonte/web-releases/bad540b2e6ed9a9b4967229edf3997ea3b087424/apps/web` dans CT114.
- Override ajouté : `/etc/systemd/system/drivy-refonte-web.service.d/90-web-release.conf`, fixant ce `WorkingDirectory`.
- API et lien partagé `/opt/drivy-refonte/current` conservés sur `c5bfb73060405de9aa0b57b8197e79954ac85588`. PID API 26154 et identité 149 identiques avant/après. Seul le web redémarre : PID 26256 → 26611 ; son répertoire réel correspond à la release.
- Environnements privés inchangés, contrôlés par empreinte sans publication de leur contenu ni de leurs empreintes. Les sessions web en mémoire sont renouvelées par le redémarrage.

## Sauvegarde et préparation

Avant toute bascule : sauvegarde `pg_dump -Fc` de `drivy_refonte` dans CT113, fichier privé mode 0600, écriture synchronisée et catalogue vérifié par `pg_restore --list`. Taille : 1 022 571 octets. Chemin conservé dans la [preuve de déploiement](proofs/web-redesign-20261013/deployment.json). Ce contrôle vérifie la lisibilité du catalogue ; aucune restauration de test n’est revendiquée.

Les noms et empreintes des **32 migrations déjà appliquées** correspondent exactement à la base déployée. Aucune migration exécutée. Les sources API et les dépendances ne changent pas.

L’archive Git contient uniquement `apps/web`. SHA-256 vérifié après transfert : `3ee9a412d730536276b8be052993ff4a459ffdeb15858bef978afc48a020c8b8`. Build Linux avec Node verrouillé **v24.21.0** : `npm ci --ignore-scripts --include=dev`, `npm run build`, puis `npm prune --omit=dev --ignore-scripts`. La préparation reste isolée du service actif jusqu’à la bascule.

## Qualification et publication

- [Vérifications CI à `93c85d1`](https://github.com/tomyrms/Drivy/actions/runs/38468486548) : **439 tests API sur PostgreSQL réel**, **233 tests web**, typages, builds et intégrité documentaire réussis.
- [Recette intégrée à `93c85d1`](https://github.com/tomyrms/Drivy/actions/runs/38468486729) : **80 contrôles réussis**, Chromium 153, OIDC/Keycloak, SMTP, BFF/API/PostgreSQL réels sur données synthétiques. Ouverture, reprise AP72, activation, catalogue, invitations, dossier, disponibilités et réservation de la première leçon ; récupération du compte. [Rapport conservé](proofs/web-redesign-20261013/reports/integrated-browser.json). Huit captures récupérées ; Agenda final inspecté.
- Les sources `apps/web` et `apps/api` sont identiques entre la release `bad540b`, `33d9551` et `93c85d1`. Les commits suivants adaptent uniquement les pilotes navigateur aux dimensions et libellés de la refonte. Les premiers échecs de ces pilotes ne sont pas comptés comme réussites.
- **19 contrôles HTTPS après publication** : 12 fichiers publics HTTP 200 avec SHA-256 identiques au build, cinq routes d’entrée dont `/app/preferences[/]`, session anonyme HTTP 200 avec `authenticated: false`, API `/refonte/v1/me` sans jeton HTTP 401. Les fichiers nommés par empreinte gardent leur cache immuable ; HTML et script initial du thème utilisent `no-store`.
- Navigateur sur la page publique anonyme en sombre : marque, bouton Apparence et connexion rendus ; aucune erreur ni alerte console. Aucune commande métier sur les données de production n’est exécutée pour cette publication.

Docker Desktop local reste indisponible ; la recette intégrée a été exécutée sur GitHub Actions. Restent les essais avec une école, le lecteur d’écran et le zoom natif. Aucune qualification physique Apple n’est déduite de ces contrôles web.

## Retour arrière et prochain déploiement

La version précédente reste dans `/opt/drivy-refonte/releases/c5bfb73060405de9aa0b57b8197e79954ac85588`. Tant que `current` pointe vers cette base, retirer uniquement `/etc/systemd/system/drivy-refonte-web.service.d/90-web-release.conf`, puis exécuter `systemctl daemon-reload` et `systemctl restart drivy-refonte-web`. Vérifier le répertoire réel du processus, la session anonyme et les fichiers publics. Aucune restauration des données n’est nécessaire pour ce retour web.

**Au prochain déploiement global, traiter explicitement cet override** : intégrer la refonte, puis le supprimer pour reprendre `current/apps/web`, ou le remplacer par la nouvelle release web. Changer seulement `current` ne met plus le web à jour. Vérifier le répertoire réel de chaque processus après redémarrage.
