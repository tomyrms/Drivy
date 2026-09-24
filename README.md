# Drivy

Refonte native iPhone/iPad centrée sur la leçon, les observations et le bilan pédagogique. La conception canonique se trouve dans [Commencer ici](Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md).

## Réalisation en cours

- `apps/ios` : code du laboratoire G0, local, avec GPS facultatif, observations et stockage SQLCipher. La compilation Apple et les essais natifs restent à exécuter ; aucun IPA validé n'est encore annoncé.
- `apps/api` : six lectures G1A implémentées, identité OIDC et permissions scolaires, PostgreSQL. Typecheck, build et **33 tests ont réussi localement**, dont 20 tests d'intégration avec PostgreSQL réel.
- `docs/implementation` : décisions, protocole de recette et preuves de la réalisation.

Voir [l'état exact](docs/implementation/STATUS.md). Le produit complet comprend aussi planning, bilans partagés, cours collectifs, packs et web de gestion ; ces fonctions restent à réaliser. Le laboratoire G0 ne contient aucune donnée scolaire ni publication serveur.

## Construire et installer sur iPhone/iPad

Le workflow **Refonte · iOS** est configuré pour compiler et tester sur macOS. Après une exécution réussie, son artefact `Drivy-unsigned-<commit>` doit contenir l'IPA destiné à la signature avec iLoader, son empreinte SHA-256 et les informations du build. La présence du workflow ne prouve pas que la compilation a réussi. L'identité Apple reste utilisée dans iLoader sur le poste du porteur.

La cible minimale provisoire des essais est iOS/iPadOS 26.0. Ce n'est pas encore le minimum commercial. Les instructions détaillées sont dans [la recette G0](docs/implementation/recette-g0.md).

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

La suite applique les migrations puis vide les tables de fixtures **de `drivy_test`** avant chaque cas. Cette base doit rester réservée à ces tests. L'absence de `TEST_DATABASE_URL`, ou un autre nom de base, produit une erreur. Les clés JWT de test sont éphémères ; aucun fournisseur OIDC externe n'est requis pour cette suite. `npm.cmd run test:unit` exécute seulement les 13 tests de JWT/configuration/curseurs et ne vérifie pas PostgreSQL.

Pour préparer la base de développement :

```powershell
$env:MIGRATION_DATABASE_URL = 'postgres://drivy_dev:local-development-only@127.0.0.1:55432/drivy_dev'
npm.cmd run migrate --workspace @drivy/api
```

Pour démarrer l'API, fournir `DATABASE_URL`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` et `CURSOR_SECRET` au processus, puis exécuter `npm.cmd run dev:api`. `HOST`/`PORT` valent par défaut `127.0.0.1`/`3001`. Aucun fichier `.env` n'est chargé automatiquement. Le [guide API](apps/api/README.md) décrit chaque variable, les rôles de base et le seed explicite `ALLOW_FIXTURES=true`.

Le fournisseur OIDC doit être configuré et les identités reliées à `(issuer, subject)` avant un parcours authentifié depuis un client. Aucun compte de démonstration n'est créé au démarrage. Le seed utilise exclusivement des identités synthétiques, sans provisionner un fournisseur ou émettre des jetons. L'API G1A est en lecture : elle ne crée pas encore les écoles, invitations, leçons ou bilans.
