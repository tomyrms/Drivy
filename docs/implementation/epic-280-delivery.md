# EPIC #280 — préparation de livraison et retour arrière

28 octobre 2026. Plan préparé depuis le dépôt puis vérifié **en lecture seule sur le homelab à 19:00 UTC**. Production réelle : `a41cf64d153252dc133a60f29755f0685516be8f`, concordante avec `deploiement-reset-253-20261028.md`. **Aucune sauvegarde, installation, migration, bascule, modification de configuration ou remise à zéro exécutée pour #280.** La confirmation finale du porteur reste nécessaire avant mise en production.

## Autorisation et séquence

Le porteur demande la réalisation autonome de W01–W31, puis uniquement une confirmation finale avant production. Il essaie personnellement la nouvelle interface après déploiement ; les campagnes complètes #309 et #84 commencent après sa validation. Les branches et protections existantes restent actives. Aucun changement DNS, purge de données, réinitialisation de comptes, activation GPS obligatoire ou nouvelle collecte n’est inclus ici. La remise à zéro documentée du 28 octobre est passée ; elle n’est jamais à répéter pour la refonte.

## Compatibilité du candidat

La refonte proprement dite modifie le frontend React/Vite et ses composants shadcn. Elle conserve OIDC/BFF, CSRF/Origin, CSP, cache privé `no-store`, isolation école/compte/époque, If-Match, idempotence et reçus. Les ressources de marque/fontes restent locales et les URL n’accueillent que les identifiants déjà autorisés.

La branche de travail intègre #253 et les reçus finaux de `origin/master` (`c94ec2bb`, fusion `52fe0320`), au-delà de la référence déployée `a41cf64d`. Différence opérationnelle relevée :

- `apps/api/src/course-facts.ts` ajoute `GET /v1/schools/:schoolId/learners/:learnerId/course-facts`, avec lecture du dossier, permission cours séparée et RLS. Le nouveau `prerequisite-help.tsx` consomme ces faits et l’allowlist BFF `school-routes.ts` l’autorise. Déployer seulement les fichiers statiques sur l’ancienne API laisserait cette lecture indisponible ; ce n’est pas la parité complète.
- `20261028b_lesson_gps_preparation_audit.sql` ajoute la policy INSERT `gps_preparation_audit_insert` sur `drivy.audit_event` pour l’action `LessonPreparedForGPS`. Elle ne supprime ni table ni donnée. La migration d’annulation individuelle précédente est déjà consignée comme appliquée dans le reçu du 28 octobre ; vérifier le registre et les empreintes au lieu de la rejouer aveuglément.
- Pas de changement du contrat OpenAPI canonique 3.11.0 ; l’extension d’implémentation `learner-course-facts.json` accompagne l’API. `GPS_ONLY_QUALIFICATION_SCHOOL_IDS` reste vide en production selon la décision existante.

La livraison proposée est le candidat API/web intégré, nécessaire à toutes ses fonctions. Le worker suit la même release et doit être redémarré avec elle. Le coordinateur vérifie le diff final ; aucun état « backend inchangé » ne doit être revendiqué sur la seule nature visuelle de #280.

## Contrôles indispensables avant demande finale

1. Figer le SHA et l’archive exacte, relever branche/base et absence de fichiers privés dans l’archive. Ne pas embarquer `.local`, fixtures privées, captures personnelles ou fichiers de travail hors périmètre.
2. Installation verrouillée des dépendances (`npm ci --ignore-scripts`) sous Node 24 ; typecheck et build web. Si API intégrée, typecheck/build API et validation minimale de la migration/politique sur PostgreSQL jetable, sans campagne exhaustive. Les contrôles existants ne sont pas désactivés.
3. Audit des dépendances runtime et diff des surfaces de sécurité. Contrôler BFF/CSP, absence de cache privé nouveau, de CDN décoratif, de service worker ou de stockage de données scolaires local. Ne pas confondre compilation et preuve de sécurité complète.
4. Captures/essai synthétique court des pilotes et des tâches critiques nécessaires pour rendre la version testable ; manifeste W01 relié au SHA. La campagne exhaustive reste différée conformément au mandat.
5. Préparer l’archive de release et son SHA-256, la liste des services concernés, la sauvegarde préalable à exécuter et la commande de retour vers la release précédente. Aucune bascule avant confirmation finale.

## Relevé homelab en lecture seule

CT114 héberge l’API, le web/BFF, le worker et l’identité ; CT113 PostgreSQL ; CT109 Caddy. La sonde reproductible [epic-280-delivery-readonly-probe.py](epic-280-delivery-readonly-probe.py) utilise le transport SSH existant, la clé d’hôte épinglée, des lectures de métadonnées et des transactions PostgreSQL `READ ONLY`. Elle n’affiche ni environnement, ni secrets, ni cookies, ni corps de réponse métier. Résultats expurgés : [epic-280-delivery-homelab-20261028.json](epic-280-delivery-homelab-20261028.json).

| Élément relu | Résultat actuel |
| --- | --- |
| Lien `current` | `/opt/drivy-refonte/releases/a41cf64d153252dc133a60f29755f0685516be8f` |
| `drivy-refonte-api.service` | Actif ; répertoire configuré `current/apps/api`, CWD réel au SHA ci-dessus ; aucun drop-in ; 0 redémarrage |
| `drivy-refonte-web.service` | Actif ; répertoire configuré `current/apps/web`, CWD réel au SHA ci-dessus ; aucun drop-in ; 0 redémarrage |
| `drivy-refonte-course-worker.service` | Actif ; `current/apps/api`, CWD réel au SHA ci-dessus ; aucun drop-in ; 0 redémarrage |
| `drivy-refonte-identity.service` | Actif ; runtime Keycloak distinct ; aucun drop-in ; 0 redémarrage ; hors mutation prévue |
| Runtime / disque | Node `v24.21.0` ; 11 949 736 KiB libres CT114 ; 13 333 092 KiB libres CT113 à 18:56 UTC |
| Confinement des quatre services | Utilisateurs distincts sans privilèges, `UMask=0077`, `NoNewPrivileges=yes`, `RestrictSUIDSGID=yes`, `LimitCORE=0` |
| Configuration | Six fichiers API/web/worker/push/migration/identity présents, `root:root 0600` ; schémas API/BFF valides |
| Réseau effectif | API `192.168.1.153:3001`, web `192.168.1.153:3002`, HTTPS public ; readiness interne `ready` |
| BFF | Origine `https://drivy.shulker.ch`, cible API `https://drivy.shulker.ch/refonte`, développement désactivé, proxy de confiance activé |
| Identité | Émetteur commun `https://drivy.shulker.ch/identity/realms/drivy` ; client `drivy-web` présent ; callback exact `/app/bff/callback` autorisé ; aucune URI avec joker |
| Connexions PostgreSQL | Base/hôte/rôles runtime, owner et worker attendus ; TLS `verify-full` ; secrets présents, non publiés |
| RLS / rôles | 91 tables du schéma métier ont RLS + FORCE RLS ; quatre rôles applicatifs/worker présents sans superuser/BYPASSRLS/CREATEDB/CREATEROLE |
| Migrations | 56 appliquées sur 57 attendues ; 0 empreinte divergente, 0 migration inconnue ; seule `20261028b_lesson_gps_preparation_audit.sql` en attente ; policy associée absente |
| Périmètres existants | GPS obligatoire désactivé ; qualification Messages configurée sans publier son identifiant scolaire ; journal `drivy_web` absent et non configuré |
| HTTPS anonyme | Les cinq routes `/app/`, `/app/gestion`, `/app/preferences`, `/app/recover`, `/app/ouvrir` répondent 200, `no-store`, CSP locale et `nosniff` ; HTML identique au build actif |
| Ressources / API | JS/CSS d’entrée identiques au build actif et cache immutable ; `/refonte/v1/me` répond 401 et `no-store` sans jeton |

Les anciens overrides `90-web-release.conf`, `90-brand-web-release.conf` et `90-qa84-web-anchor.conf` ne sont pas actifs. La première sonde `127.0.0.1:3001` a échoué parce que l’API écoute son IP CT ; la sonde sur l’adresse réellement configurée a réussi. Ce résultat n’est pas une panne API. Les durées BFF non surchargées utilisent leurs valeurs de code : inactivité 480 min, maximum 720 min, réauthentification 300 s ; récupération de compte désactivée par défaut.

Relancer cette lecture avant la bascule si la préparation se prolonge. Les captures synthétiques de l’interface candidate ne sont pas une preuve de fonctionnement authentifié de la production actuelle ; aucun compte ou acte métier n’a été créé pendant cette sonde.

## Sauvegarde, staging et bascule après confirmation

- Juste avant mutation homelab, sauvegarde privée `pg_dump -Fc` de `drivy_refonte`, et de tout journal web persistant réellement présent si concerné. Le reçu courant indique `drivy_web` absente ; ne pas la créer pour ce déploiement. Vérifier catalogue/blocs, permissions 0600 et emplacement ; une lecture de dump ne vaut pas restauration d’essai.
- Construire le SHA dans un nouveau répertoire immuable de release, empreinte de transfert identique, lockfiles et runtime attendu. Conserver l’ancienne release intacte. Aucune installation dans le répertoire actif.
- Candidat API/web intégré : `install-api-release.py --apply /opt/drivy-refonte/releases/<SHA>` installe/build, applique les migrations et vérifie les droits/RLS avant de changer `current`. Le script **n’est pas un installateur frontend seul**. Vérifier auparavant registre/migrations et la compatibilité du worker ; redémarrer uniquement les services explicitement inclus au plan approuvé, avec contrôle de leurs répertoires réels.
- Frontend seul, si cette variante est explicitement décidée : répertoire `/opt/drivy-refonte/web-releases/<SHA>/apps/web`, build verrouillé puis override atomique du seul `WorkingDirectory`, `systemctl daemon-reload` et redémarrage `drivy-refonte-web`. Ne pas laisser plusieurs drop-ins concurrents. Cette variante seule ne livre pas le nouvel endpoint décrit plus haut.
- Le redémarrage BFF peut fermer les sessions en mémoire ; l’interface doit proposer une reconnexion propre et retrouver le suivi durable autorisé, sans rejouer un corps scolaire depuis le navigateur.

## Vérification de publication et rollback

Après bascule : services actifs, répertoires réels au SHA attendu, aucune boucle de redémarrage ; readiness interne ; `/app/`, `/app/gestion`, `/app/preferences`, `/app/recover`, `/app/ouvrir` retournent l’entrée attendue. Vérifier contenu HTML/asset par empreinte (pas seulement HTTP 200), cache HTML/BFF `no-store`, assets immuables, session anonyme, API 401 sans jeton et protections CSP/cookies. Ne faire aucune commande métier sur les données réelles pour une sonde visuelle. Un chargement de page publique anonyme ne qualifie pas tous les parcours authentifiés.

Pour cette livraison intégrée, le rollback logiciel ramène API/web/worker ensemble au SHA relu. Aucune restauration de configuration n’est nécessaire si le plan respecte l’absence de modification d’environnement et de drop-in. Les nouvelles écritures et versions déjà acceptées restent conservées. La policy d’audit additive peut rester avec l’ancienne API ; aucun DROP ni restauration de base automatique.

Commandes préparées **à exécuter sur CT114 seulement si un retour logiciel est décidé après déploiement**, jamais exécutées durant cette préparation :

```sh
set -eu
previous=/opt/drivy-refonte/releases/a41cf64d153252dc133a60f29755f0685516be8f
test -f "$previous/apps/api/dist/main.js"
test -f "$previous/apps/web/dist/server/main.js"
test -f "$previous/apps/web/dist/client/index.html"
test -L /opt/drivy-refonte/current
test ! -e /opt/drivy-refonte/.current-rollback-280
test ! -L /opt/drivy-refonte/.current-rollback-280
systemctl stop drivy-refonte-web drivy-refonte-course-worker drivy-refonte-api
ln -s "$previous" /opt/drivy-refonte/.current-rollback-280
mv -Tf /opt/drivy-refonte/.current-rollback-280 /opt/drivy-refonte/current
systemctl start drivy-refonte-api drivy-refonte-course-worker drivy-refonte-web
systemctl is-active drivy-refonte-api drivy-refonte-course-worker drivy-refonte-web
curl --fail --silent --show-error --max-time 8 http://192.168.1.153:3001/health/ready
```

Relancer ensuite la sonde expurgée, contrôler les CWD réels et les empreintes HTML/JS/CSS. Aucun `daemon-reload` n’est nécessaire puisque les unités et drop-ins ne changent pas. Si la proposition finale ajoute un override, revoir les commandes avec cet état exact avant accord ; ne pas appliquer aveuglément ce retour au lien seul. Keycloak, comptes, périmètres Messages/GPS, Caddy et base restent intacts.

La restauration d’une sauvegarde écraserait des actes postérieurs : elle exige un incident concret, inventaire des écritures et décision distincte. Elle n’est pas la procédure normale de retour d’un frontend. Garder l’ancien build accessible aux onglets déjà ouverts ou leur proposer la récupération explicite des chunks indisponibles ; aucun rechargement en boucle.

## W29, W30 et W31 : preuves à compléter

- W29 : tailles JS/CSS/fontes relevées dans [la fondation](epic-280-foundation.md), même navigation/recherche sous latence synthétique dans [la mesure courte](epic-280-performance.md). CLS de laboratoire seulement ; INP de terrain et mémoire restent `NOT_EXECUTED`. Aucun gain de vitesse de production déduit des composants.
- W30 : chaque ligne du manifeste dispose d’un état de migration et d’un retour/ancien lien. Retirer CSS/composants morts seulement après recherche de références ; `formation-wizard.tsx`, déjà retiré par #253, ne revient pas. Ne jamais supprimer contrôleurs/versions pour alléger l’interface.
- W31/#84 : après validation personnelle, exécuter la matrice complète routes/sous-vues/états/rôles, mobile/desktop/clair/sombre, clavier, contraste, 44 px, zoom/reflow, appareils disponibles, sécurité et intégration PostgreSQL. `PASS`, `FAIL`, `NOT_EXECUTED`, `BLOCKED` restent distincts. Aucun résultat GPS/batterie/VoiceOver physique inféré d’un simulateur.

Statut de cette préparation : `READ_ONLY_PREFLIGHT_PASS`. Vérification distante actuelle : exécutée le 28 octobre à 19:00 UTC. Sauvegarde/bascule/rollback : `NOT_EXECUTED`. Campagnes #309/#84 : différées jusqu’à l’essai et la validation personnelle. Le coordinateur complète la proposition finale avec le SHA candidat final et les résultats locaux avant de demander l’accord de production.
