# Réglage GPS du portail — déploiement du 17 octobre 2026

Le réglage **Trajets GPS** est publié sur le homelab à **15:39 Europe/Zurich**, conformément à l’autorisation de déploiement conservée dans `AGENTS.md`.

- Web : `e8d7b758f3b0838545844e3012108dc0ca9f0ac4`, répertoire `web-releases/<SHA>/apps/web`.
- API et identité : inchangées ; API sur `a68bb381af3936cc923f631c7ce21360459d2fbb` (connexion native). Les PID et répertoires des processus ont été comparés avant/après.
- Aucune modification des fichiers d’environnement privés, du BFF, des dépendances ou des migrations ; 33 empreintes de migrations contrôlées.
- Sauvegarde PostgreSQL de `drivy_refonte` terminée avant la bascule : `pg_dump -Fc`, 1 031 913 octets, fichier privé mode 0600 sur CT113, écriture synchronisée puis catalogue vérifié par `pg_restore --list`. Aucune donnée du dump n’est exportée dans le dépôt ou en CI.
- Build sur Node 24.21.0 verrouillé, installation depuis le lockfile. Seul le service web a été redémarré.
- **19 contrôles HTTPS réussis**, dont 12 empreintes de fichiers de la release, les pages d’entrée, la session anonyme et le refus 401 de l’API sans identité.

Les écoles gardent leur réglage actuel. L’administrateur peut désormais activer le module depuis **Paramètres → Confidentialité → Trajets GPS**. L’accord de l’élève et la permission iOS restent distincts ; aucune capture ne naît de l’activation du module.

## Preuves de vérification

[Vérifications de `e8d7b75`](https://github.com/tomyrms/Drivy/actions/runs/39037098306) : **459 tests API/PostgreSQL**, **254 tests web**, types, builds et intégrité documentaire réussis.

[Recette d’ouverture et connexion](https://github.com/tomyrms/Drivy/actions/runs/39036951653) : **100 contrôles navigateur → OIDC → BFF → API → PostgreSQL** réussis sur `0ad37f9`, sources API/web identiques à la release.

Parcours du nouveau réglage exécutés dans un navigateur avec transport synthétique : annulation, activation, désactivation, restitution du focus, réauthentification refusée et conflit de version puis relecture. Captures : [activation](assets/demarrage-lecon-gps-20261017/web-gps-enabled-synthetic.png), [désactivation](assets/demarrage-lecon-gps-20261017/web-gps-disabled-synthetic.png), [conflit](assets/demarrage-lecon-gps-20261017/web-gps-conflict-synthetic.png). Elles ne représentent pas l’école réelle du porteur.

## État à conserver au prochain déploiement

Le lien partagé `/opt/drivy-refonte/current` reste sur `a68bb381…`. Le web utilise un override dédié : `/etc/systemd/system/drivy-refonte-web.service.d/90-web-release.conf`. Le prochain déploiement global doit tenir compte de cet override pour ne pas laisser le web sur une ancienne release.

Retour arrière : retirer uniquement cet override, relire systemd et redémarrer le web. Il reprend alors `/opt/drivy-refonte/current/apps/web`. Aucun retour arrière de base n’est nécessaire, aucune migration ni modification de réglage d’école n’ayant été effectuée.
