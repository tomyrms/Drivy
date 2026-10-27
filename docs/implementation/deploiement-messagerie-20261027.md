# Déploiement messagerie, bilans et planning web — 27 octobre 2026

Version `54b6ea98d1806813a45bb9b8646447c78e6274a1` (master après les PR #180 et #181) installée le 27 octobre 2026 vers 18:36 UTC sur le homelab, à la demande du porteur. API, web et worker des cours et notifications tournent sur cette version.

## Sauvegarde

Avant toute modification, `drivy_refonte` a été sauvegardée sur CT113 : `/root/drivy_refonte-before-54b6ea98d1806813a45bb9b8646447c78e6274a1-20261027T183546Z-bc78ff87327b.dump`, 2 498 650 octets, droits 0600, relue par `pg_restore` (catalogue et blocs). Aucune restauration d'essai n'est revendiquée. La base `drivy_web` n'était pas concernée par cette version.

## Installation

- Archive `git archive` de la version (SHA-256 `62f3f543…0636e0`), identique avant et après transfert.
- Worker et API arrêtés, puis `infra/deploy/install-api-release.py --apply` : compilation API et web, migrations, bascule du lien `current` de `5888f03` vers `54b6ea9`.
- Migrations : 53 avant, 55 après (`20261025_messaging_mention_push.sql`, `20261026_messaging_mutation_receipts.sql`). Noms et empreintes du registre identiques au dépôt.
- `api.env` inchangé. Aucune variable nouvelle : la récupération de compte reste désactivée (`ACCOUNT_RECOVERY_ENABLED` absent, donc `false`).
- L'override `90-qa84-web-anchor.conf`, qui figeait le web sur `71390e97`, est retiré et conservé dans `/root/90-qa84-web-anchor.conf.before-54b6ea98d1806813a45bb9b8646447c78e6274a1`. Le web suit à nouveau `current`.

## Vérifications

- `drivy-refonte-api`, `-web`, `-identity` et `-course-worker` actifs ; répertoires réels de l'API, du web et du worker dans la nouvelle version ; readiness interne de l'API à 200.
- Journaux API, web et worker : aucun avertissement ni erreur dans les dix minutes suivant la bascule, aucun redémarrage automatique.
- Public : `/app/` et `/app/bff/session` à 200 ; `/refonte/v1/account-recovery/options` à 200 avec la récupération indisponible ; `/refonte/v1/me` à 401 sans jeton ; nouvelle route BFF `lessons/availability` à 401 sans session.
- Aucune commande métier exécutée sur les données de production pour ces contrôles.

## Ce que change cette version

- Messagerie (#98, #100 à #104, #141, #169, #170) et reçus de mutations (#104).
- Notification de **mention** : le déclencheur `messaging_mention_enqueue` met en file un push générique (sans contenu ni nom d'auteur) que le worker revalide avant envoi. Les notifications de **nouveau message** ne sont pas implémentées côté serveur (#74, choix ouverts dans #66).
- Bilans conservés localement (#162, #163), planning des leçons depuis l'agenda web (#51), récupération de compte préparée mais désactivée (#50).

## Qualification

Validation finale du candidat intégré `4014c52` (run 40545726242) : contrats, droits et PostgreSQL, web et BFF, recette navigateur, scripts, intégrité et IPA réussis. La campagne iOS complète a été coupée à 90 minutes (94 min nécessaires) : sur iPhone, tests métier et toutes les suites UI réussis sauf deux tests de saisie (focus clavier), corrigés en `75c8851` ; sur iPad, tests métier et suites UI jusqu'à la messagerie réussis, le reste non exécuté. Le porteur a demandé de poursuivre sans relancer la campagne complète. La limite du job iOS passe à 150 minutes.

Aucune qualification physique iPhone/iPad, VoiceOver, GPS, batterie ou réception push n'est déduite de ce déploiement.

## Retour arrière

1. Sur CT114 : `ln -sfn /opt/drivy-refonte/releases/5888f03718045e13dc3c304040ead26991ffe719 /opt/drivy-refonte/current`.
2. Remettre `/root/90-qa84-web-anchor.conf.before-54b6ea98d1806813a45bb9b8646447c78e6274a1` dans `/etc/systemd/system/drivy-refonte-web.service.d/90-qa84-web-anchor.conf`, puis `systemctl daemon-reload`.
3. `systemctl restart drivy-refonte-api drivy-refonte-web drivy-refonte-course-worker`, puis vérifier états, répertoires réels et routes HTTPS.

Les deux migrations sont additives : l'ancienne version ignore leurs tables, colonnes et fonctions, et `course_push_revalidate` reste en place. Après retour, l'ancien worker enverrait encore les mentions mises en file, avec leur seul titre générique et un corps vide. Une restauration de la base depuis la sauvegarde ne serait nécessaire qu'en cas de donnée altérée, et ferait perdre les écritures faites depuis 18:35 UTC.
