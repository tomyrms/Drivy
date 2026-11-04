# Service des cours : qualification du processus réel (#37 / C37)

4 novembre 2026. Branche `tomyrms/issues-cours-processus-37`, base `e2edc85ed092237016620079d52d11eb7a2d02b5`.
Lot de preuve uniquement : aucun changement de produit, d'infrastructure, de dépendance, de contrat ni de workflow.

## Ce qui manquait

`apps/api/src/course-worker.ts` est déjà le vrai processus long : il refuse une configuration absente, vérifie le rôle
(`current_user` et `drivy_course_worker`, sans superuser ni BYPASSRLS), appelle `processPushBatch(pool, sender)` dans une
boucle, attend 15 s quand rien n'est traité et bascule `stopping` sur `SIGTERM`/`SIGINT` avant de fermer l'expéditeur et
le pool. Les tests existants (`course-notifications`, `course-push-failure`, `course-push-revalidation`) appelaient
`processPushBatch` directement : le lancement, la boucle, la reprise et la fermeture n'étaient pas exercés.

Aucun défaut de comportement n'a été reproduit dans `course-worker.ts` : le fichier n'a pas été modifié. Aucune
seconde implémentation n'a été écrite ; le test lance le module réel, dont le `try{await run()}catch{…}` s'exécute au
chargement.

## Environnement réellement exécuté

- Windows, Node **v24.22.2** portable (`C:\Users\jtoma\AppData\Local\Temp\drivy-orchestration-20261104\node-v24.22.2-win-x64`)
  placé dans le `PATH` du processus seulement ; dépendances installées depuis le `package-lock.json` du dépôt
  (`npm ci`, 111 paquets). Le test refuse de s'exécuter si le runtime majeur n'est pas 24.
- PostgreSQL jetable `postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24`,
  loopback uniquement, port libre, nom `drivy-c37-pg-<aléa>`, supprimé en `finally` (aucun `prune`, aucun volume
  conservé). Une attente dédiée du **serveur final** (seconde annonce « ready to accept connections » puis requête TCP)
  évite la coupure du serveur temporaire d'initialisation ; sans elle la recette échouait par
  `Connection terminated unexpectedly`.
- Rôles synthétiques, supprimés en `finally` :
  - `drivy_c37_worker_login` : `LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT`, membre de
    `drivy_course_worker` avec `SET TRUE, INHERIT FALSE` — donc deux lignes distinctes pour la vérification du service,
    et `SET LOCAL ROLE drivy_course_worker` possible comme en exploitation ;
  - `drivy_c37_worker_bypassrls` : même forme, avec `BYPASSRLS`, uniquement pour le scénario de refus.
- Sous-processus : environnement construit explicitement (`PATH`, `SystemRoot`, `TEMP`, `TMP`,
  `COURSE_WORKER_DATABASE_URL`) ; aucune variable `APNS_*`, aucun `.env`, aucun `.p8`, aucun parcours de l'environnement
  complet. La fixture lève si une clé `APNS_*` apparaissait.
- Aucune connexion Apple, aucun SMTP, aucune donnée réelle.

## Scénarios et observations

| # | Scénario | Observation réelle |
| --- | --- | --- |
| 1a | Configuration absente | code de sortie **1**, signal nul, `stdout` vide, `stderr` = une seule ligne `Service des cours : démarrage impossible, vérifier configuration et droits.` ; compteurs métier identiques avant/après |
| 1b | Rôle interdit (`BYPASSRLS`) | code **1**, même message unique ; ni mot de passe, ni `postgres://`, ni `127.0.0.1` dans `stderr` ; `stdout` vide ; compteurs métier identiques ; **0** connexion restante pour ce rôle |
| 2 | Rôle autorisé, APNs non configuré | l'outbox est vide avant le processus ; après lancement, la boucle prépare **1** notification `OFFER` `PENDING` (`sent_at` nul) ; après échéance écrite en SQL, le passage suivant met la proposition `EXPIRED` et la notification `OFFER` `EXPIRED`, `sent_at` nul ; **0** ligne `SENT` ; processus toujours vivant ; `stdout` vide |
| 3 | Plusieurs passages + relance | sessions A puis B observées dans deux passages distincts (B après A, sans délai fixe comme preuve) ; après arrêt/relance, C est traitée ; A, B et l'offre restent à **1** ligne chacune, états inchangés, offre **1** `ACTIVE`, **0** `SENT`, outbox non délivrée **0** |
| 4 | Perte de connexion PostgreSQL contrôlée | **≥1** backend du login terminé par `pg_terminate_backend` ; diagnostic unique `Connexion inactive perdue (error).` ; processus vivant ; la session B publiée ensuite est traitée par un passage ultérieur ; aucune ligne de journal hors des deux messages génériques ; aucun mot de passe, URL, hôte, titre ni UUID dans `stdout`/`stderr` ; `stdout` vide |
| 5 | `SIGTERM` pendant l'attente | **NON_EXÉCUTÉ sous Windows** (`it.skipIf`, raison de plateforme uniquement). Le contrat de borne est lu dans `infra/deploy/drivy-refonte-course-worker.service` (`TimeoutStopSec=30`) et vérifié ; l'arrêt gracieux, la sortie code 0, la libération des connexions/verrous et l'absence de transaction partielle restent à exécuter sur le runner Linux |

`child.kill()` sous Windows est une terminaison forcée (`TerminateProcess`) : les scénarios 2, 3 et 4 arrêtent le
processus ainsi, et **ne prouvent aucun arrêt gracieux**. Aucun `process.emit('SIGTERM')` n'est utilisé comme preuve ;
aucune conclusion n'est tirée d'un kill forcé.

## Commandes et résultats observés

| Commande | Résultat |
| --- | --- |
| `node --version` (PATH préfixé) | `v24.22.2` |
| `npm ci --no-audit --no-fund` | 111 paquets installés |
| `npx tsc --noEmit` (apps/api) | code de sortie **0** |
| `npx vitest run test/course-worker-process.integration.test.ts` | **6 réussis, 1 ignoré**, code **0** |
| `npx vitest run` des 4 suites liées (`course-notifications`, `course-push-failure`, `course-push-revalidation`, `course-worker-process`) | **37 réussis, 1 ignoré**, 4 fichiers, code **0** |

Journal de la dernière campagne :
`artifacts/c37-20261104/verification.log` (répertoire ignoré par Git, non versionné). Les compteurs SQL du tableau sont
ceux assertés par les tests sur la base jetable (une ligne `OFFER`, `EXPIRED`, `sent_at` nul, zéro `SENT`, outbox non
délivrée nulle).

Une première exécution a réellement échoué sur une attente trop stricte (`Connexion inactive perdue (Error).` attendu,
`(error)` observé) : l'assertion a été corrigée sur la casse réelle du diagnostic. Ce n'est pas un test de mutation ; le
fichier produit ne pouvait pas être modifié pour ce lot.

## Limites de cette preuve

- **`SIGTERM` POSIX non exécuté** : aucun runtime Linux local adapté (seule la distribution `docker-desktop` de WSL est
  présente, sans Node 24 ; aucune installation implicite n'a été faite). Précondition pour l'étape suivante : un runner
  Linux avec Node 24 et les dépendances du lock, qui exécutera le test tel quel — le cas n'est ignoré que sur `win32`.
- Arrêt **pendant un travail en cours** non contrôlable sans instrumenter le service : non testé. Le scénario 5 vérifie
  seulement l'absence de transaction ouverte avant l'arrêt.
- Le contrat `TimeoutStopSec=30` est lu, pas exercé : aucun `systemd`, aucun service réel, aucun déploiement.
- APNs réel non prouvé : aucune clé, aucun appareil, aucun envoi. `processPushBatch` reste appelé sans expéditeur.
- La suite API complète n'a pas été relancée ici (périmètre ciblé, et deux cas d'invitation dépendent d'un SMTP local
  absent). Les suites liées à la file de notifications sont vertes.
- Aucune parité UI/iPad de #37 n'est prouvée par ce lot.

## Fichiers

- `apps/api/test/course-worker-process.integration.test.ts` (nouveau) ;
- `apps/api/test/fixtures/course-worker-process/worker-process.ts` (nouveau, fixture de lancement et d'attente) ;
- ce document ;
- `artifacts/c37-20261104/verification.log` (ignoré, non versionné).

Aucun fichier de `apps/api/src`, `infra/deploy`, `docs/implementation/STATUS.md`, du contrat ou des dépendances n'a été
modifié.
