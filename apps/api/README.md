# API Drivy · accès G1A et configuration G1B

Serveur TypeScript/Fastify, PostgreSQL et authentification OIDC. G1A ouvre un dossier et une formation selon les droits relus en base. G1B permet à un ADMIN de configurer une école provisionnée, d’adopter explicitement sa notice/politique de données, puis de l’activer. Les routes canoniques suivent OpenAPI **3.11.0** ; la petite extension `data-policy` possède son [schéma séparé](contracts/g1b-data-policy.json). Les invitations, la création de formations, les leçons et leur synchronisation restent à réaliser.

| Route GET | Réponse `data` | Portée |
|---|---|---|
| `/v1/me` | `Me` | Personne liée à `(issuer, subject)` ; ses appartenances actives |
| `/v1/schools/:schoolId` | `School` | Membre actif de cette école |
| `/v1/schools/:schoolId/learners` | `LearnerPage` | ADMIN : école ; INSTRUCTOR : affectations courantes ; LEARNER : soi |
| `/v1/schools/:schoolId/learners/:learnerId` | `Learner` | Même portée que la liste |
| `/v1/schools/:schoolId/trainings` | `TrainingPage` | ADMIN : données administratives ; INSTRUCTOR : formations affectées ; LEARNER : soi |
| `/v1/schools/:schoolId/trainings/:trainingId` | `Training` | Même portée que la liste |

Réponse : `{ "data": ..., "requestId": "...", "serverTime": "..." }`. Pages : `{ "items": [...], "nextCursor": null }`. Erreurs `application/problem+json`. Toutes les réponses sont `Cache-Control: no-store`. Les lectures unitaires versionnées portent un ETag fort. L’accès administratif livré ne donne accès à aucun texte pédagogique, capture ou document.

Les écoles du sélecteur viennent de `me.memberships` ; aucune route supplémentaire de découverte d’école n’est créée. Les listes sont triées par `(created_at, id)` et limitées à 50 objets par défaut, 100 maximum. Le curseur chiffré lie personne, école, epoch d’accès, filtres et taille de page ; il expire après une heure. Les dates purement civiles restent `YYYY-MM-DD`.

## Configuration ADMIN G1B

Les chemins suivants sont relatifs à `/v1/schools/:schoolId`. Le rôle ADMIN actif est vérifié au serveur ; une école DRAFT permet ces seules commandes de configuration, sans autoriser des mutations scolaires courantes.

| Méthode et chemin | Effet / réponse |
|---|---|
| GET `/setup` | Progression et prérequis, sans création lors du GET |
| PATCH `/setup` | Sauvegarde versionnée de l’étape et de la progression ; aucune approbation implicite |
| GET `/readiness` | Préparation à l’activation et quatre capacités distinctes |
| PATCH base scolaire (AP06) | Nom, fuseau et contacts ; version des réglages conservée |
| GET `/data-policy` | Notice, conservation, contact et preuve d’adoption ; initialement DRAFT et vide |
| PUT `/data-policy` | Nouvelle révision immuable, après adoption explicite des textes affichés |
| POST `/activate` | Activation si les prérequis et les versions relus sont valides |
| GET `/operations/:operationId` | Preuve de commit pour son auteur dans cette école, sans texte ni coordonnées |

Chaque commande exige `operationId` UUID, `Idempotency-Key` identique et `If-Match` fort de la ressource concernée. L’activation contrôle en plus `expectedConfigurationVersion` et `reviewAcknowledged:true`. L’adoption de la politique incrémente aussi les versions scolaires : recharger School/readiness avant activation. Le résultat métier, sa preuve durable et l’audit sont atomiques ; aucune réponse réussie ne précède le commit.

L’activation exige identité/contact/fuseau de l’école, ADMIN actif et textes adoptés. Cocher DATA ou REVIEW ne suffit pas. CAN_USE_WORKSPACE exige ensuite School ACTIVE ; planification, capture scolaire et publication de cours restent non prêtes dans G1B. Un résultat HTTP incertain conserve sa clé et son contenu ; un 404/403 de recherche d’opération ne prouve jamais l’absence d’un ancien commit. Le [contrat G1B détaillé](../../docs/implementation/g1b-school-setup.md) précise champs, versions, limites, erreurs et reprise.

## Hébergement effectif

L’API G1A et Keycloak 26.7.4 sont accessibles en HTTPS sur l’hébergement choisi : base API `https://drivy.shulker.ch/refonte`, issuer exact `https://drivy.shulker.ch/identity/realms/drivy`. La refonte utilise Node 24.21.0 et des bases PostgreSQL 16.14 neuves, UTF8, avec vérification TLS du certificat PostgreSQL. L’ancienne API reste distincte. L’accès administrateur Keycloak n’est pas publié.

Le compte initial `luc` appartient comme ADMIN à « Luc auto école », sans élève ni formation. L’école reste DRAFT tant que son ADMIN n’a pas adopté de politique et confirmé son activation ; le provisionnement et la migration 002 ne fabriquent aucune approbation. L’adresse de contact `luc@example.com` est une adresse d’essai explicitement autorisée ; aucun email n’a été envoyé.

G1B est implémenté et validé côté serveur. La version effectivement déployée, les preuves HTTPS/OIDC et les recettes des clients sont consignées dans [STATUS.md](../../docs/implementation/STATUS.md). Voir [le déploiement](../../docs/implementation/deploiement-refonte.md) et [le contrôle OIDC HTTPS exécuté](../../docs/implementation/controle-oidc-deploye.md). Les tests locaux de G1B ne constituent pas une preuve de son parcours natif ou de son déploiement.

## Démarrer

Node 24 ; installation depuis la racine avec `npm ci`. Les tests ont été exécutés sur PostgreSQL 16.14 et 17.11. En développement, depuis la racine :

```text
npm run migrate --workspace @drivy/api
npm run seed --workspace @drivy/api
npm run dev --workspace @drivy/api
```

Les variables sont fournies au processus ; ce package ne charge ni ne crée implicitement un fichier `.env`.

| Variable | Usage |
|---|---|
| `DATABASE_URL` | Connexion de l’API ; rôle sans SUPERUSER/BYPASSRLS en production, autorisé à `SET ROLE drivy_app` |
| `MIGRATION_DATABASE_URL` | Connexion DDL distincte, uniquement scripts de migration/fixtures |
| `OIDC_ISSUER` | Issuer exact accepté et issuer des liens d’identité des fixtures |
| `OIDC_AUDIENCE` | Audience dédiée à l’API, pas l’identifiant du client web |
| `OIDC_JWKS_URL` | Endpoint JWKS fixe du fournisseur approuvé |
| `CURSOR_SECRET` | Secret aléatoire d’au moins 32 caractères, propre à l’environnement |
| `NODE_ENV` | `development`, `test` ou `production` |
| `HOST`, `PORT` | Par défaut `127.0.0.1`, `3001` |
| `ALLOW_FIXTURES` | `true` exigé par le script seed ; interdit avec `NODE_ENV=production` |
| `TEST_DATABASE_URL` | Base dédiée nommée exactement `drivy_test` pour tests d’intégration |

L’authentification accepte uniquement un Bearer signé RS256/ES256, avec issuer, audience API, subject, émission et expiration vérifiés via `jose`. Un fournisseur HTTP n’est accepté qu’en local hors production. Une identité inconnue n’est pas créée par `GET /me` ; elle reçoit 403. Aucun mot de passe, token de démonstration, auth automatique ou rôle issu d’une claim client n’est accepté comme autorisation. Le fournisseur hébergé est raccordé ; le client natif utilise AppAuth/PKCE. La qualification du parcours sur appareil reste distincte de celle du serveur.

## Migrations et fixtures

`migrate` utilise un verrou PostgreSQL, une transaction par fichier SQL et une empreinte SHA-256. Un fichier déjà appliqué ne peut pas changer silencieusement. La migration 001 est conservée ; 002 ajoute G1B et initialise la configuration des écoles existantes sans accord ni activation. Les treize tables métier gardent ENABLE/FORCE RLS.

Le rôle `drivy_app` est sans login ni privilège de contournement RLS. En hébergement, le propriétaire de migration distinct n’est ni SUPERUSER, BYPASSRLS, CREATEDB ni CREATEROLE ; le rôle applicatif est précréé, avec ADMIN OPTION accordée à ce propriétaire pour la migration 001. Le runtime reçoit seulement le droit de prendre `drivy_app` ; l’API exécute `SET LOCAL ROLE drivy_app` dans chaque transaction. Les lectures utilisent un instant cohérent. Les commandes verrouillent accès global, école et appartenance puis relisent les droits avant le commit. Les droits d’écriture G1B sont bornés par table/colonne et RLS ; les preuves, audits et révisions restent immuables pour le runtime.

Le seed est exclusivement admis dans `drivy_dev` ou `drivy_test`, avec `ALLOW_FIXTURES=true` explicite. Il insère des données synthétiques sans supprimer ni remplacer les données déjà présentes. Les noms et emails `example.invalid` ne correspondent pas à des personnes clientes. Il ne provisionne pas un fournisseur OIDC. Les subjects synthétiques attendus sont `demo-admin`, `demo-instructor`, `demo-alice`, `demo-bob`, `demo-other-instructor`, `demo-foreign` ; les UUID sont exportés dans `scripts/fixtures.ts`. Les comptes hébergés suivent le provisionnement contrôlé décrit dans le guide de déploiement, jamais ce seed.

Les modules GPS, packs et cours sont désactivés dans les fixtures. Le moniteur est affecté à la formation d’Alice dans Horizon, et administrateur de Rivage : les deux écoles permettent d’éprouver l’isolation. Les offres sont des références internes synthétiques ; leur administration et la qualification de politiques/référentiels de formation restent hors de G1B.

## Vérification

```text
npm run typecheck --workspace @drivy/api
npm test --workspace @drivy/api
npm run build --workspace @drivy/api
```

`npm test` **échoue** si `TEST_DATABASE_URL` ne désigne pas `drivy_test`. La suite G1B remet à zéro le schéma et le registre de migrations de cette seule base, applique 001 sous un propriétaire non privilégié, insère des fixtures préexistantes, puis applique 002 et contrôle son backfill sous FORCE RLS. Les tables de fixtures sont ensuite vidées avant chaque cas. Cette base est exclusivement réservée aux tests, sans exécution concurrente d’une autre suite ou d’un service. `test:unit` exécute uniquement les tests JWT/configuration/curseurs, sans preuve d’intégration SQL.

Le 24 septembre 2026, **57 tests** ont réussi sur PostgreSQL **16.14 et 17.11** : les 34 tests G1A et 23 tests G1B. Typecheck et build ont également réussi. Les tests d’intégration signent des JWT avec des clés éphémères locales et exécutent les requêtes sous `drivy_app`. Les réponses canoniques sont validées contre l’OpenAPI original ; `data-policy` est validé contre son schéma d’extension, sans le présenter comme une route canonique.

Les preuves couvrent accès croisé, multi-rôles, affectations, révocation, pagination, FK et unicité d’offre ; elles ajoutent initialisation sans accord, adoption versionnée, activation non circulaire, commandes concurrentes/rejouées, configuration périmée, révocation pendant attente d’un verrou et rollback intégral provoqué par un échec réel d’audit. AP72 est vérifié pour auteur/école sans contenu personnel. Ces résultats ne prouvent ni une livraison email, ni un parcours natif, ni une collecte GPS.

## Persistance admise et limites

| Table | Parcours servi | Invariant |
|---|---|---|
| `person` | Identité globale indépendante des écoles | `/me`, statut de compte |
| `identity_link` | Un fournisseur ne doit pas fusionner deux personnes par email | Unicité issuer/subject |
| `school` | Identité et contexte scolaire propre | `/schools/:id` |
| `membership` | Droits et révocation distincts de l’identité | Rôles/grants embarqués ; unicité personne/école ; epoch |
| `learner_profile` | Coordonnées et archive propres à l’école | Listes et détail du dossier |
| `offering_version` | Cible stable de la formation | Version d’offre, catégorie, clé logique ; administration différée |
| `training` | Plusieurs formations et leur cycle propre | FK composites ; une ACTIVE/PAUSED par dossier/clé d’offre |
| `instructor_assignment` | Autorisation temporelle par formation | Membre INSTRUCTOR, même école, bornes temporelles |
| `school_setup` | Progression de configuration G1B | Un état par école ; les étapes ne valent pas approbation |
| `school_data_policy` | Notice et conservation adoptées | Révisions immuables ; auteur et date, aucune adoption initiale |
| `school_settings_version` | Historique des réglages scolaires | Versions immuables liées à la politique applicable |
| `operation` | Reprise de commande sans double effet | Clé unique par auteur, contexte/type/hash vérifiés |
| `audit_event` | Trace des effets G1B | Même commit que l’effet et sa preuve ; aucun texte ni coordonnées |

L’école et l’identité hébergées proviennent du provisionnement contrôlé ; les dossiers/formations des tests proviennent seulement des fixtures. Les commandes d’administration livrées sont celles de G1B ci-dessus. L’adoption d’un texte conserve la décision de l’ADMIN, sans certifier sa conformité juridique ni exécuter automatiquement la conservation décrite. Invitations, création/acceptation d’un premier dossier, administration des formations, suppression et procédures de rétention restent à livrer. Le registre technique de migrations n’est pas un concept métier supplémentaire.

La RLS forme la barrière entre écoles ; les requêtes applicatives imposent en plus les affectations et l’accès à soi. Les autorisations ne viennent jamais des sélecteurs d’écran. Les requêtes, filtres de recherche, headers d’authentification, JWT et données de réponse ne sont pas journalisés ; seules des références de requête non sensibles accompagnent les erreurs génériques.
