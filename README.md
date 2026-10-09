# Drivy

Refonte native iPhone/iPad centrée sur la leçon, les observations et le bilan pédagogique. La conception canonique se trouve dans [Commencer ici](Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md).

## Réalisation en cours

- `apps/ios` : application native de terrain pour moniteurs et élèves : connexion OIDC, agenda, dossiers par permis, démarrage explicite des leçons, GPS facultatif, observations, bilan et progression. Les demandes et brouillons locaux sont chiffrés.
- `apps/api` : service TypeScript/Fastify et PostgreSQL ; droits scolaires revérifiés au serveur, commandes idempotentes et partage automatique des leçons réalisées avec l’élève, hors contenus gardés privés par le moniteur.
- `apps/web` : bureau de l’école : configuration, catalogue, équipe, invitations, dossiers et planning.
- `docs/implementation` : décisions, périmètre réellement livré, tests et limites de qualification.

Voir [l’état exact et les dernières vérifications](docs/implementation/STATUS.md). Le laboratoire local G0 et l’administration de l’école sont retirés de l’app. Les cours collectifs et les packs ne constituent pas des parcours livrés du pilote.

## Construire et installer sur iPhone/iPad

Les builds récents sont disponibles dans les [GitHub Actions du dépôt](https://github.com/tomyrms/Drivy/actions). Choisir la branche et le commit indiqués dans le suivi de livraison, extraire l’artefact puis importer `Drivy.ipa` dans iLoader. Le porteur réalise la signature et l’installation. Les artefacts sont conservés 14 jours ; un lien vers un ancien build ne garantit pas leur disponibilité.

Le workflow **IPA d'essai · iLoader** compile et vérifie le paquet indépendamment des tests sur simulateurs. Sa réussite ne qualifie donc pas tous les parcours natifs. Le workflow **Refonte · iOS** exécute séparément les tests iPhone/iPad et ne produit son artefact `Drivy-unsigned-<commit>` qu'après leur réussite.

Pour requalifier une correction limitée aux tests, l’option manuelle `unit_only` relance `DrivyTests` sur iPhone. Pour une correction d’interface ciblée, `ui_test_suite` relance la classe UITest nommée sur iPhone et iPad. Ces deux options s’excluent, ne produisent aucune IPA et ne remplacent pas une campagne complète ; le suivi attribue les résultats au périmètre et au commit effectivement exécutés.

La passe de stabilité du 9 octobre exige la migration 023 et l’API correspondante avant l’installation de la nouvelle app : elles enregistrent le démarrage réel des leçons. Effectuer la sauvegarde avant cette mise à jour serveur ; voir [l’ordre de livraison](docs/implementation/stabilite-api-20261009.md#migration-et-conservation-des-données).

La cible minimale provisoire des essais est iOS/iPadOS 26.0. Ce n'est pas encore le minimum commercial. Les commandes utilisées par la CI sont dans [le script de construction IPA](scripts/ios/build-ipa.sh) et [les tests sur simulateurs](scripts/ios/test-simulator.sh).

## Serveur en développement

Node 24 et Docker Desktop démarré sont requis. Depuis la racine du dépôt, dans PowerShell :

```powershell
npm.cmd ci
docker compose up -d --wait postgres
```

Le service PostgreSQL utilise le port local `55432` et le volume du projet Compose `drivy-refonte`. Une seule fois, créer la base dédiée aux tests :

```powershell
docker compose exec -T postgres createdb -U drivy_dev drivy_test
```

Si `drivy_test` existe déjà, passer directement aux vérifications :

```powershell
$env:TEST_DATABASE_URL = 'postgres://drivy_dev:local-development-only@127.0.0.1:55432/drivy_test'
npm.cmd run typecheck
npm.cmd test
npm.cmd run build
```

La suite applique les migrations puis vide les tables de fixtures **de `drivy_test`** avant chaque cas. Cette base doit rester réservée à ces tests. L'absence de `TEST_DATABASE_URL`, ou un autre nom de base, produit une erreur. Les clés JWT de test sont éphémères ; aucun fournisseur OIDC externe n'est requis pour cette suite. `npm.cmd run test:unit` exécute uniquement les tests sans base et ne vérifie pas les parcours PostgreSQL.

Pour préparer la base de développement :

```powershell
$env:MIGRATION_DATABASE_URL = 'postgres://drivy_dev:local-development-only@127.0.0.1:55432/drivy_dev'
npm.cmd run migrate --workspace @drivy/api
```

Pour démarrer l'API, fournir `DATABASE_URL`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` et `CURSOR_SECRET` au processus, puis exécuter `npm.cmd run dev:api`. `HOST`/`PORT` valent par défaut `127.0.0.1`/`3001`. Aucun fichier `.env` n'est chargé automatiquement. Le [guide API](apps/api/README.md) décrit chaque variable, les rôles de base et le seed explicite `ALLOW_FIXTURES=true`.

Le fournisseur OIDC doit être configuré et les identités reliées à `(issuer, subject)` avant un parcours authentifié depuis un client. Aucun compte de démonstration n'est créé au démarrage. Le seed utilise exclusivement des identités synthétiques, sans provisionner un fournisseur ou émettre des jetons. Le [provisionnement opérateur](docs/implementation/deploiement-refonte.md) crée le premier compte et l'école DRAFT. [G1B](docs/implementation/g1b-school-setup.md) permet ensuite à l'ADMIN de configurer et activer l'école ; les tranches suivantes couvrent invitations, leçons et bilans ; leur qualification actuelle figure dans le suivi.

Le [banc OIDC local](docs/implementation/dev-identity.md) utilise un vrai Keycloak et des connexions navigateur PKCE ; ses 29 contrôles passent. Le [déploiement isolé](docs/implementation/deploiement-refonte.md) et sa [preuve HTTPS](docs/implementation/controle-oidc-deploye.md) documentent l'hébergement réellement raccordé. Les anciennes données et services restent distincts de la refonte.
