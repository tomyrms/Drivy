# Environnement messagerie synthétique #68

23 octobre 2026. Livrable isolé autorisé par le coordinateur, **configuration et procédures non exécutées**. Ce répertoire ne configure ni service de chat, ni Matrix de production, ni APNs. Il n'active aucune fonctionnalité Drivy. Les notes de résidence et sécurité restent les références des décisions produit à obtenir.

## Choix d'implémentation du laboratoire

- Image PostgreSQL copiée à l'identique depuis `../../compose.yaml`, version 17 Alpine et digest `sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24`. Aucun tag flottant ajouté. Ce verrou n'est pas une vérification actualisée des vulnérabilités de l'image.
- Node 24 requis par le dépôt et refus des autres versions lors des opérations. Dépendances `pg` existantes et `package-lock.json` du dépôt, aucun nouveau package ou installation effectué.
- Projet Compose distinct `drivy-messaging-synthetic`, volumes propres `fixture-data` et `restore-data`, sans volume externe ou montage de données de l'app. Ne pas lancer deux exemplaires concurrents de ce projet sur le même moteur.
- Source `drivy_test` sur `127.0.0.1:55468` uniquement. Identifiant et mot de passe **publics synthétiques**, sans valeur de secret, interdits ailleurs. Aucun token OIDC généré.
- Réseau source déclaré interne. Cible de restauration sans réseau, sans port publié et sur un autre volume. L'efficacité de l'isolation Docker/hôte n'a pas été mesurée.
- Moteur local exigé par le wrapper (pipe/socket, pas TCP/SSH), contexte inspecté puis fixé. Un socket proxy ou une configuration Docker compromise ne sont pas détectables par cette vérification.
- `pull_policy: never` et `--pull never` empêchent le téléchargement implicite d'une image. Image et dépendances doivent déjà être disponibles localement. Aucun provisionnement automatique.
- Pas de fournisseur tiers, Keycloak, SMTP, relais push, serveur applicatif ou partage réseau démarré. Pas de test ou d'appel à l'API publique dans les scripts.

## Fichiers

| Fichier | Rôle |
|---|---|
| `compose.yaml` | Source de fixtures et cible de restauration séparée, image verrouillée |
| `init.sql` | Marqueur de laboratoire à la création du volume source |
| `seed.mjs` | Appelle directement `migrate` et `seedFixtures` existants, sans duplication de schéma |
| `environment.mjs` | Commandes explicites up/seed/backup/restore/stop, sans nettoyage destructif |
| `qualification.json` | Preuves absentes et contrôles restant à autoriser, pas un rapport de tests |
| `.gitignore` | Exclut les archives/manifeste `.state/` de Git |

Le marqueur évite une erreur ordinaire de cible. **Il ne prouve pas que la base ne contient que des données synthétiques.** Ne jamais importer de dump de production, de données de personnes, de positions, de médias ou de secrets dans cet environnement. Ne pas manipuler des archives reçues de tiers : une restauration SQL ne constitue pas un bac à sable pour fichiers hostiles.

## Procédure proposée, à exécuter seulement après autorisation distincte

Commandes depuis la racine du dépôt, avec Node 24, Docker Compose disponible et image déjà locale. Elles sont fournies, **pas lancées pendant cette livraison** :

```text
node prototypes/messaging-environment/environment.mjs up --synthetic-only
node prototypes/messaging-environment/environment.mjs seed --synthetic-only
node prototypes/messaging-environment/environment.mjs backup --synthetic-only
node prototypes/messaging-environment/environment.mjs restore --synthetic-only
node prototypes/messaging-environment/environment.mjs stop --synthetic-only
```

`seed` relit le marqueur sur la base effectivement contactée, applique les migrations canoniques et appelle `apps/api/scripts/fixtures.ts` avec l'issuer synthétique `https://messaging.test.invalid`, identique au scénario messagerie existant. Il ne lance pas Vitest, ne tronque aucune table et ne simule pas de chiffrement réel. Les fixtures scolaires réutilisées ne créent pas à elles seules un historique de messages.

Les scénarios PostgreSQL existants dans `apps/api/test/messaging.integration.test.ts` utilisent `TEST_DATABASE_URL` et exigent le nom `drivy_test`. Si leur exécution est ultérieurement autorisée, leur URL dédiée sera :

```text
postgresql://drivy_fixture:synthetic-public-fixture-only@127.0.0.1:55468/drivy_test
```

Ne pas leur donner la base de restauration, celle du compose racine ou une base d'école. Leurs hooks font un `TRUNCATE` des fixtures et leur garde actuelle vérifie le nom de base, pas l'hôte. **Ne jamais réutiliser une valeur ambiante de `TEST_DATABASE_URL`.** Pour un futur lancement expressément autorisé, valider d'abord le marqueur via le wrapper `up`/`seed`, puis fournir explicitement l'URL locale dédiée ci-dessus au seul processus de scénario. Le marqueur ne doit pas être supposé valide à partir du nom `drivy_test`. Aucune commande de tests n'est incluse dans le wrapper. Suspendre toute écriture et tout futur scénario pendant une opération de sauvegarde/restauration. La seule présence d'une archive ne prouve pas que les scénarios de messages ont été réalisés.

## Sauvegarde et restauration synthétiques

1. `backup` vérifie le marqueur, puis utilise le `pg_dump --format=custom` de l'image source fixée. Les octets ne sont jamais affichés. Il écrit `.state/snapshot.dump` puis un manifeste SHA-256, taille, date, image et mention synthétique. Création exclusive : une archive existante n'est jamais écrasée.
2. **Archive non chiffrée de fixtures publiques uniquement.** Aucun chiffrement de sauvegarde réel n'est promis, aucun repli depuis un coffre chiffré n'existe. Ne pas réutiliser ce mécanisme pour données réelles, clés, exports E2EE ou environnements hors laboratoire. Les modes POSIX demandés ne constituent pas une preuve d'ACL Windows.
3. Le manifeste détecte une corruption accidentelle, pas une falsification : il n'est ni signé ni authentifié. Un arrêt entre l'archive et le manifeste laisse un ensemble incomplet et la restauration échoue. Pas de reprise qui écrase silencieusement l'existant.
4. `restore` vérifie manifeste et hash avant de démarrer sa cible. Il crée exclusivement `drivy_restore`, puis appelle `pg_restore --single-transaction --exit-on-error --no-owner --no-acl` et relit le marqueur. L'archive est fournie par stdin, sans copie supplémentaire dans le conteneur.
5. La cible reçoit à sa création `init-restore.sql` : seulement `drivy_app` et `drivy_invitation_mailer`, NOLOGIN et sans mot de passe, car `pg_dump` n'exporte pas les rôles référencés par les politiques et droits. Aucun rôle ni attribut n'est copié depuis un autre cluster. Un volume `restore-data` déjà initialisé ne relit pas ce fichier.
6. Si la base cible existe déjà, création refusée. Une erreur de restauration peut laisser la base vide créée : elle reste isolée, aucune suppression automatique. Un opérateur devra décider explicitement du nettoyage après inspection, uniquement des ressources de ce projet.
7. Une restauration terminée et son marqueur ne qualifient pas la cohérence métier, les permissions, les révocations, les médias ou la récupération de clés. Pas de réouverture utilisateur ou de promotion de la cible.
8. `stop` arrête les services mais conserve volumes et archives. Aucune commande `down -v`, `DROP DATABASE` ou purge automatique n'est fournie. Le nettoyage du laboratoire et de ses copies locales reste une action distincte à approuver.

Limites techniques volontaires : archive bornée par le buffer de 64 Mio et timeout de 120 secondes. Ce ne sont ni des objectifs RPO/RTO, ni un dimensionnement de production. Les diagnostics bruts des sous-processus sont masqués pour ne pas imprimer les valeurs SQL.

## Frontières #68 restant bloquées

- **RES04/RES05 non exécutés** : aucun backup/restore réalisé, aucune restauration après révocation/suppression démontrée. Le journal indépendant de tombstones/révocations et son rejeu ne sont pas implémentés ici. Une ancienne sauvegarde peut contenir d'anciens droits, raison supplémentaire de ne jamais ouvrir la cible restaurée.
- Résidence réelle, opérateurs, accès support, sauvegardes de l'hôte/Docker Desktop et pays des appareils non qualifiés. Une adresse loopback n'est pas une garantie suisse.
- Chiffrement de sauvegarde de production, gestion de clés, médias, WAL/PITR, snapshots, réplication, politiques de rétention et purge hors périmètre.
- Aucun résultat E2EE, Swift, Keychain, OIDC réel ou APNs. Les choix de confidentialité/modération restent ceux à arbitrer dans #67/#77.
- Pas de modification de `STATUS.md` par ce worker : le coordinateur reprend les preuves exactes, sans transformer la syntaxe valide en scénario réussi.

## Validation effectivement réalisée

Le 23 octobre 2026 : `node --check` sur les deux fichiers `.mjs` et parsing YAML avec le package `yaml` déjà installé du dépôt. Ces vérifications ne chargent pas les scripts opérationnels et n'exécutent pas le SQL. Outil local observé : Node **26.8.1**, uniquement pour la syntaxe, pas une preuve d'exécution sous Node 24.

Non réalisés : démarrage/connexion Docker, pull d'image, migrations, fixtures, dump, restore, tests, validation runtime Node 24 et contrôle réseau. La syntaxe SQL a seulement été relue, non validée par PostgreSQL.
