# API Drivy · accès, configuration et invitations

Serveur TypeScript/Fastify, PostgreSQL et authentification OIDC. G1A ouvre un dossier et une formation selon les droits relus en base. G1B permet à un ADMIN de configurer une école provisionnée, d’adopter explicitement sa notice/politique de données, puis de l’activer. G1C ajoute les invitations et leur acceptation explicite, sans créer de formation. Les routes canoniques suivent OpenAPI **3.11.0** ; les extensions `data-policy` et `invitations/preview` possèdent leurs schémas séparés dans `contracts/`. La création de formations, les leçons et leur synchronisation restent à réaliser.

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

## Invitations G1C

Une école ACTIVE peut inviter : ADMIN choisit les rôles, INSTRUCTOR propose seulement LEARNER et gère ses propres invitations. AP10 liste avec `limit`/`cursor` ; AP11 crée ; AP12 renvoie avec rotation du secret ; AP13 révoque. Les écritures utilisent Idempotency-Key ; renvoi/révocation exigent aussi If-Match. Une réponse réussie signifie invitation enregistrée, sans promesse de réception du mail.

Le destinataire ouvre `/app/invitation#token=…`, se connecte et consulte le preview authentifié avant confirmation AP04. Seule une claim `email_verified: true` accompagnant l'adresse dans le JWT validé est admise ; aucun email du corps ne prouve une identité. L'acceptation sérialise l'identité OIDC et crée/réutilise personne, lien, adhésion et profil élève minimal dans le commit contenant preuve et audit. Aucune formation ni affectation n'est créée. Un émetteur INSTRUCTOR n'obtient donc pas automatiquement accès au dossier accepté.

L'invitation stocke SHA-256 du secret ; l'outbox stocke temporairement un payload AES-256-GCM. Le worker SMTP distinct revérifie droits, état et expiration, puis efface le payload après acceptation SMTP ou annulation. SENT ne signifie pas DELIVERED. Le risque résiduel de doublon après crash SMTP et la reprise sont décrits dans [G1C](../../docs/implementation/g1c-invitations.md). L'événement InvitationAccepted est audité et son état est visible dans AP10 ; le centre de notifications F11 reste une tranche distincte.

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
| `INVITATION_WEB_URL` | URL du parcours navigateur, HTTPS en production, sans query ni fragment initial |
| `INVITATION_OUTBOX_KEY` | Clé aléatoire AES-256 de 64 caractères hexadécimaux ; même coffre pour API et worker |
| `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM` | Transport du worker ; TLS vérifié obligatoire en production |
| `SMTP_USER`, `SMTP_PASSWORD` | Authentification SMTP si requise, jamais journalisée |
| `MAIL_DATABASE_URL` | Connexion du worker séparée, autorisée à prendre seulement `drivy_invitation_mailer` |
| `TEST_SMTP_PORT`, `TEST_MAILPIT_URL` | Mailpit de recette, défauts 1025 et `http://127.0.0.1:8025` |

L’authentification accepte uniquement un Bearer signé RS256/ES256, avec issuer, audience API, subject, émission et expiration vérifiés via `jose`. Un fournisseur HTTP n’est accepté qu’en local hors production. Une identité inconnue n’est pas créée par `GET /me` ; elle reçoit 403. Aucun mot de passe, token de démonstration, auth automatique ou rôle issu d’une claim client n’est accepté comme autorisation. Le fournisseur hébergé est raccordé ; le client natif utilise AppAuth/PKCE. La qualification du parcours sur appareil reste distincte de celle du serveur.

## Migrations et fixtures

`migrate` utilise un verrou PostgreSQL, une transaction par fichier SQL et une empreinte SHA-256. Un fichier déjà appliqué ne peut pas changer silencieusement. Les migrations 001/002 sont conservées. 003 ajoute les invitations et l'outbox ; les quinze tables métier gardent ENABLE/FORCE RLS. Aucune migration ne crée une invitation ni n'adopte une politique pour l'utilisateur.

Avant 003, un administrateur prépare les rôles avec [prepare-invitation-mailer.sql](scripts/prepare-invitation-mailer.sql), puis génère le mot de passe du login worker côté serveur et configure son accès PostgreSQL TLS/HBA propre. Ce script ne s'exécute jamais automatiquement. Le propriétaire de migration n'a pas besoin de CREATEROLE si le rôle NOLOGIN est précréé. Le worker démarre séparément avec `npm run mail:worker --workspace @drivy/api` après build (`mail:worker:dev` en développement). L'absence de configuration SMTP ferme la création et le renvoi avec 503 ; aucune requête HTTP ne lance un transport implicite.

Le rôle `drivy_app` est sans login ni privilège de contournement RLS. En hébergement, le propriétaire de migration distinct n’est ni SUPERUSER, BYPASSRLS, CREATEDB ni CREATEROLE ; le rôle applicatif est précréé, avec ADMIN OPTION accordée à ce propriétaire pour la migration 001. Le runtime reçoit seulement le droit de prendre `drivy_app` ; l’API exécute `SET LOCAL ROLE drivy_app` dans chaque transaction. Les lectures utilisent un instant cohérent. Les commandes verrouillent accès global, école et appartenance puis relisent les droits avant le commit. Les droits d’écriture G1B sont bornés par table/colonne et RLS ; les preuves, audits et révisions restent immuables pour le runtime.

Le seed est exclusivement admis dans `drivy_dev` ou `drivy_test`, avec `ALLOW_FIXTURES=true` explicite. Il insère des données synthétiques sans supprimer ni remplacer les données déjà présentes. Les noms et emails `example.invalid` ne correspondent pas à des personnes clientes. Il ne provisionne pas un fournisseur OIDC. Les subjects synthétiques attendus sont `demo-admin`, `demo-instructor`, `demo-alice`, `demo-bob`, `demo-other-instructor`, `demo-foreign` ; les UUID sont exportés dans `scripts/fixtures.ts`. Les comptes hébergés suivent le provisionnement contrôlé décrit dans le guide de déploiement, jamais ce seed.

Les modules GPS, packs et cours sont désactivés dans les fixtures. Le moniteur est affecté à la formation d’Alice dans Horizon, et administrateur de Rivage : les deux écoles permettent d’éprouver l’isolation. Les offres sont des références internes synthétiques ; leur administration et la qualification de politiques/référentiels de formation restent hors de G1B.

## Vérification

```text
npm run typecheck --workspace @drivy/api
npm test --workspace @drivy/api
npm run build --workspace @drivy/api
```

`npm test` **échoue** si `TEST_DATABASE_URL` ne désigne pas `drivy_test`. La suite G1B remet à zéro le schéma et le registre de migrations de cette seule base, applique 001 sous un propriétaire non privilégié, insère des fixtures préexistantes, puis applique 002/003 et contrôle le backfill sous FORCE RLS. Les tables de fixtures sont ensuite vidées avant chaque cas. Cette base est exclusivement réservée aux tests, sans exécution concurrente d’une autre suite ou d’un service. G1C exige Mailpit réel, avec échec si le service attendu n'est pas disponible. `test:unit` exécute uniquement les tests JWT/configuration/curseurs, sans preuve d’intégration SQL.

Le 24 septembre 2026, **89 tests** ont réussi sur PostgreSQL **16.14 et 17.11** : 34 G1A, 23 G1B et 32 G1C. Typecheck et build ont également réussi. Les tests d’intégration signent des JWT avec des clés éphémères locales et exécutent les requêtes sous `drivy_app`. Les réponses canoniques sont validées contre l’OpenAPI original ; `data-policy` et `invitations/preview` sont validés contre leurs schémas séparés, sans les présenter comme des routes canoniques.

Les preuves couvrent accès croisé, multi-rôles, affectations, révocation, pagination, FK et unicité d’offre ; elles ajoutent initialisation sans accord, adoption versionnée, activation non circulaire, commandes concurrentes/rejouées, configuration périmée, révocation pendant attente d’un verrou et rollback intégral provoqué par un échec réel d’audit. G1C ajoute e-mail vérifié, acceptation concurrente, rotation/révocation de liens, SQL worker séparé et SMTP Mailpit réel avec purge du secret. AP72 est vérifié pour auteur/école sans contenu personnel. Les résultats G1C exacts sont consignés dans [sa qualification](../../docs/implementation/g1c-invitations.md#qualification). Ils ne prouvent ni une livraison SMTP externe, ni un parcours natif, ni une collecte GPS.

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
| `invitation` | Invitation et acceptation explicite | Secret haché, e-mail vérifié, versions, expiration et auteur |
| `invitation_mail` | Livraison SMTP séparée du commit métier | Payload chiffré et effacé, claim exclusif avec lease, retries bornés |

L’école et l’identité hébergées proviennent du provisionnement contrôlé ; les dossiers/formations des tests sont synthétiques. G1C permet l'entrée d'un premier élève par invitation acceptée, avec un profil à compléter. L’adoption d’un texte conserve la décision de l’ADMIN, sans certifier sa conformité juridique ni exécuter automatiquement la conservation décrite. Administration des formations, centre de notifications, suppression et procédures de rétention restent à livrer. Le registre technique de migrations n’est pas un concept métier supplémentaire.

La RLS forme la barrière entre écoles ; les requêtes applicatives imposent en plus les affectations et l’accès à soi. Les autorisations ne viennent jamais des sélecteurs d’écran. Les requêtes, filtres de recherche, headers d’authentification, JWT et données de réponse ne sont pas journalisés ; seules des références de requête non sensibles accompagnent les erreurs génériques.
