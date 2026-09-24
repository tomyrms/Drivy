# API Drivy · première tranche G1A

Serveur TypeScript/Fastify, PostgreSQL et authentification OIDC. Les six lectures ci-dessous utilisent les routes et enveloppes du contrat canonique OpenAPI **3.11.0**. L’API ouvre un dossier et une formation selon les droits relus en base. Elle ne livre pas encore la création d’école, les invitations, les leçons ni leur synchronisation.

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

## Démarrer

Node 24 ; installation depuis la racine avec `npm ci`. PostgreSQL 17 pour les tests exécutés. Depuis la racine :

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

L’authentification accepte uniquement un Bearer signé RS256/ES256, avec issuer, audience API, subject, émission et expiration vérifiés via `jose`. Un fournisseur HTTP n’est accepté qu’en local hors production. Une identité inconnue n’est pas créée par `GET /me` ; elle reçoit 403. Aucun mot de passe, token de démonstration, auth automatique ou rôle issu d’une claim client n’est accepté comme autorisation. Le fournisseur OIDC et le parcours de connexion des clients restent à raccorder.

## Migrations et fixtures

`migrate` utilise un verrou PostgreSQL, une transaction par fichier SQL et une empreinte SHA-256. Un fichier déjà appliqué ne peut pas changer silencieusement. Le rôle `drivy_app` est créé sans login ni privilège de contournement RLS ; la connexion de migration reçoit ce rôle. Pour une connexion runtime distincte, l’opérateur lui accorde ce rôle ; l’API exécute `SET LOCAL ROLE drivy_app` dans chaque transaction de lecture.

Le seed est exclusivement admis dans `drivy_dev` ou `drivy_test`, avec consentement explicite par variable. Il insère des données synthétiques sans supprimer ni remplacer les données déjà présentes. Les noms et emails `example.invalid` ne correspondent pas à des personnes clientes. Il ne provisionne pas un fournisseur OIDC. Les subjects synthétiques attendus sont `demo-admin`, `demo-instructor`, `demo-alice`, `demo-bob`, `demo-other-instructor`, `demo-foreign` ; les UUID sont exportés dans `scripts/fixtures.ts`. Un vrai fournisseur doit émettre le subject exact ou un opérateur doit créer un lien vérifié dans un prochain parcours de provisionnement.

Les modules GPS, packs et cours sont désactivés dans les fixtures. Le moniteur est affecté à la formation d’Alice dans Horizon, et administrateur de Rivage : les deux écoles permettent d’éprouver l’isolation. Les offres sont des références internes synthétiques ; leur activation et la qualification de politiques/référentiels restent à construire en G1B.

## Vérification

```text
npm run typecheck --workspace @drivy/api
npm test --workspace @drivy/api
npm run build --workspace @drivy/api
```

`npm test` **échoue** si `TEST_DATABASE_URL` ne désigne pas `drivy_test`. La suite exécute les migrations puis vide les tables de fixtures de cette base avant chaque cas. Elle ne doit jamais cibler une base utilisée par un autre service. `test:unit` exécute uniquement les tests JWT/configuration/curseurs, sans preuve d’intégration SQL.

Les tests d’intégration signent des JWT avec des clés éphémères locales, exécutent les requêtes sur PostgreSQL avec le rôle `drivy_app`, et valident les réponses contre les schémas du document OpenAPI original. Ils couvrent notamment accès croisé, multi-rôles, moniteur non affecté, révocation avec JWT encore valide, RLS scolaire, pagination, FK composites et unicité par clé logique d’offre.

## Persistance admise et limites

| Table | Pourquoi elle existe dès G1A | Invariant / lecture |
|---|---|---|
| `person` | Identité globale indépendante des écoles | `/me`, statut de compte |
| `identity_link` | Un fournisseur ne doit pas fusionner deux personnes par email | Unicité issuer/subject |
| `school` | Identité et contexte scolaire propre | `/schools/:id` |
| `membership` | Droits et révocation distincts de l’identité | Rôles/grants embarqués ; unicité personne/école ; epoch |
| `learner_profile` | Coordonnées et archive propres à l’école | Listes et détail du dossier |
| `offering_version` | Cible stable de la formation | Version d’offre, catégorie, clé logique ; détail G1B différé |
| `training` | Plusieurs formations et leur cycle propre | FK composites ; une ACTIVE/PAUSED par dossier/clé d’offre |
| `instructor_assignment` | Autorisation temporelle par formation | Membre INSTRUCTOR, même école, bornes temporelles |

Dans ce premier incrément, leur création vient du seed de développement. Aucune API d’administration provisoire n’est exposée. Aucune suppression scolaire/publique n’est livrée : les tables ne sont pas proposées pour des données réelles avant les commandes d’administration, l’audit, les procédures de rétention et les parcours correspondants. Le registre technique de migrations n’est pas un concept métier supplémentaire.

La RLS forme la barrière entre écoles ; les requêtes applicatives imposent en plus les affectations et l’accès à soi. Les autorisations ne viennent jamais des sélecteurs d’écran. Les requêtes, filtres de recherche, headers d’authentification, JWT et données de réponse ne sont pas journalisés ; seules des références de requête non sensibles accompagnent les erreurs génériques.
