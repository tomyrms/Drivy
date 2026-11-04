# #97 — qualification réelle du parcours média (Swift → HTTPS/Fastify/PostgreSQL → destinataire)

Date : 5 novembre 2026. Base de travail : `6285017188caf42cfd930d38d268418d54e904f2`
(`tomyrms/issues-medias-relais-reel-97`). Ce lot prépare et exécute la partie **Node/PostgreSQL**
de la qualification média ; la partie **Swift/Xcode est préparée mais NON COMPILÉE et NON
EXÉCUTÉE** (aucun toolchain Apple sur ce poste). Aucun fichier produit, runtime, crypto, UI,
`scripts/ios`, workflow, `package.json`/lock, `STATUS.md`, conception ou registre n'est modifié.
Ce document ne clôt ni #97, ni #68, ni #65, ni #78.

## 1. Ce que ce lot ajoute

| Fichier | Rôle | Nature |
|---|---|---|
| `scripts/qualification/messaging-media-fixtures.mts` | Identités média synthétiques, seed idempotent, garde de séparation | Nouveau, test-only |
| `scripts/messaging-relay-qualification.mts` | Sème les fixtures média, accepte leurs trois sujets Bearer, publie `media` dans `/qualification/ready`, expose `buildQualificationRelay` (mêmes gardes, mêmes routes) | Extension additive |
| `scripts/messaging-media-relay-qualification.test.mjs` | Preuves Node sur PostgreSQL 17 réelle : gardes, seed, isolation, routes média | Nouveau |
| `apps/ios/DrivyTests/MessagingMediaRealRelayTests.swift` | Parcours média réel contre le relais HTTPS jetable | Nouveau, non compilé |
| `docs/implementation/messaging-media-97-real-relay.md` | Ce rapport | Nouveau |

Aucune route produit n'est ajoutée ou changée : le test construit le **même** relais de
qualification que le harnais iOS et injecte les requêtes dans l'instance Fastify. La seule
nouvelle surface côté serveur de qualification est un champ `media` **additif** dans
`/qualification/ready` ; les champs `ready`, `fixture`, `schoolId`, `adminId`, `instructorId`,
`learnerId` restent identiques, donc les consommateurs historiques ne changent pas.

## 2. Isolation des fixtures

Les gardes existantes du bootstrap sont **inchangées** : `NODE_ENV=test`,
`DRIVY_RELAY_ALLOW_RESET=1`, `TEST_DATABASE_URL` sur `drivy_test` en loopback sans paramètre,
certificat et clé TLS fournis. Aucune variable d'environnement nouvelle n'est introduite, donc
`scripts/ios/relay-qualification.sh` continue de fonctionner sans modification.

École et comptes média, tous synthétiques et disjoints des fixtures canoniques (vérifié par test) :

| Élément | Identifiant |
|---|---|
| École média | `1a000000-0000-4000-8000-000000000097` |
| École étrangère média | `1a000000-0000-4000-8000-000000000098` |
| Moniteur média | `2a000000-0000-4000-8000-000000000097` |
| Élève média | `2a000000-0000-4000-8000-000000000098` |
| Compte étranger | `2a000000-0000-4000-8000-000000000099` |
| Sujets Bearer | `media-fixture-instructor`, `media-fixture-learner`, `media-fixture-foreign` |

Le seed crée en plus les relations qui autorisent réellement une conversation privée
(`messaging_private_allowed`) : formation `ACTIVE` de l'élève et affectation valide du moniteur.
Il est idempotent (`ON CONFLICT DO NOTHING`), ne fait aucun `DELETE`, `TRUNCATE` ni mise à jour de
masse, et refuse un émetteur non synthétique (`MEDIA_FIXTURE_ISSUER_REQUIRED`) **avant** toute
connexion. Les trois sujets ne sont acceptés que par le `verifyToken` local du relais de
qualification : ils ne sont jamais ajoutés à l'authentification de production.

Conséquence pour le scénario historique : son élève canonique (`fixtureIds.alice`) reste sans
appareil et sans conversation au démarrage ; le test média ne dépend d'aucun ordre d'exécution
entre classes (école, comptes, coffres, espaces Keychain et racines temporaires distincts).

## 3. Preuves réellement exécutées (Node 24 + PostgreSQL 17)

Environnement : Node `v24.22.2` (portable, PATH processus seulement), PostgreSQL 17 jetable
`postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24`,
conteneur dédié `drivy-msgrelay97-pg` sur `127.0.0.1:15497`, base `drivy_test`, créé pour ce lot
(inventaire préalable : aucun conteneur ni port de ce nom n'existait). Dépendances installées par
`npm ci` depuis le `package-lock.json` existant, dans ce worktree uniquement.

```bash
node --test --import tsx scripts/messaging-media-relay-qualification.test.mjs
# tests 17 · pass 17 · fail 0

node --test --import tsx scripts/messaging-relay-qualification.test.mjs
# tests 9 · pass 9 · fail 0 (relais historique : aucune régression)

npx tsc --noEmit --target ES2023 --module NodeNext --moduleResolution NodeNext --strict \
  --skipLibCheck --esModuleInterop --types node --resolveJsonModule \
  scripts/qualification/messaging-media-fixtures.mts scripts/messaging-relay-qualification.mts
# aucune erreur

# Routes média déjà livrées, non modifiées par ce lot (garde-fou de non-régression) :
npx vitest run test/messaging-media.test.ts test/messaging-media.integration.test.ts
# Test Files 2 passed (2) · Tests 26 passed (26)
```

Contenu des preuves :

1. **Gardes de configuration** : production, opt-in absent, base distante, base non dédiée,
   paramètre de contournement, TLS absent, port invalide → refus
   `RELAY_QUALIFICATION_CONFIGURATION_REQUIRED`, sans écho de la valeur fournie.
2. **Séparation des fixtures** : aucune collision d'UUID avec les fixtures canoniques, UUID
   v4 syntaxiquement valides, sujets distincts de `demo-instructor`/`demo-alice`.
3. **Refus de seed** : émetteur `https://…example.com` ou vide rejeté avant toute connexion.
4. **Isolation et idempotence** (vraie base) : école canonique intacte (`Auto-école Horizon ·
   Démonstration`, `ACTIVE`), rôles média attendus, élève canonique et élève média sans appareil
   ni conversation, second seed sans aucune ligne supplémentaire.
5. **Readiness** : champs canoniques identiques, bloc `media` exact (école, moniteur, élève,
   école étrangère, compte étranger, `drivy-messaging-media-v1`).
6. **Authentification** : jeton inconnu → 401 ; jeton canonique sur l'école média → 403.
7. **Conversation privée média** : créée par les routes réelles, idempotente.
8. **Dépôt média** : sans appareil → 403 `MESSAGING_DEVICE_REQUIRED` ; appareil non enregistré →
   403 ; dépôt nominal → 200 `UPLOADED` avec SHA-256 du chiffré ; rejeu identique → 200 même
   hash ; octets différents sous le même `mediaId` → 409 `MEDIA_INTENT_CONFLICT`.
9. **Message porteur** : POST avec `media` → 200, référence `{mediaId, byteSize, deleted:false}`
   sans contenu en clair ; relecture par le destinataire via PostgreSQL ; téléchargement par le
   destinataire → 200 `application/octet-stream`, `Cache-Control: private, no-store`, en-tête
   `X-Drivy-Media-Sha256` égal au hash déposé, octets identiques ; école étrangère → 404
   `MEDIA_NOT_FOUND`.
10. **Annulation et suppression** : annulation avant attache → 200 puis 200 idempotent puis 404 ;
    annulation après attache → 409 `MEDIA_ALREADY_ATTACHED` ; suppression pour tous → tombstone
    (`deletedForEveryone`, `ciphertext: null`, `media.deleted: true`) et téléchargement → 404.

Ces preuves portent sur les **routes de fixture touchées** et sur les données synthétiques ; elles
ne constituent pas une preuve du parcours Swift (section 4).

## 4. Scénario natif préparé (non compilé, non exécuté)

`apps/ios/DrivyTests/MessagingMediaRealRelayTests.swift`, classe
`MessagingMediaRealRelayTests`, méthode `testRealRelayMediaJourney`. Elle est découverte par la
campagne `all` (`-only-testing:DrivyTests`), qui démarre déjà le relais HTTPS jetable.

Déroulé :

1. Configuration stricte (`DRIVY_RELAY_QUALIFICATION_URL` HTTPS loopback, sans identifiants ni
   chemin) ; absence = **échec**, jamais saut. Readiness média vérifiée sur le vrai serveur.
2. Conversation autorisée par les routes réelles ; deux vraies `MatrixMessagingCryptography`
   (deux coffres `MessagingCryptoVault`, deux espaces Keychain synthétiques isolés), deux
   files/caches média réels sur des racines temporaires distinctes, transports média construits
   avec les `deviceID` **réellement enregistrés** (`currentDeviceID`).
3. Image PNG synthétique 1×1 puis PDF synthétique rendu en mémoire : préparation réelle, mise en
   file, envoi par `MessagingMediaCoordinator` avec `MessagingHTTPMediaTransport` et
   `MessagingAPIClient` réels, reçu serveur validé.
4. Réouverture du coffre média et d'un nouveau coordinateur sur les mêmes racines et espaces
   Keychain : même `mediaID`, mêmes octets scellés, même enveloppe Megolm (aucun réchiffrement).
5. **Réponse perdue** : un décorateur transparent de `MessagingMediaMessageSending` exécute le
   POST réel jusqu'à son accusé durable puis jette **exactement une** réponse réussie. Le
   coordinateur rend `.pending(.resultUnknown)` — jamais un faux accusé, jamais un refus
   définitif. Le test vérifie alors qu'un seul message serveur porte le média, puis renvoie et
   retrouve le **même** identifiant serveur, une seule ligne, et l'enveloppe persistée inchangée.
   Il s'agit d'une **panne de remise contrôlée**, pas d'une coupure physique de réseau.
6. Destinataire : relecture serveur, provenance `matrixContent` explicite (contenu v3), référence
   `meta.media` concordante, puis ouverture par son vrai coordinateur : octets originaux, MIME,
   nom, dimensions et légende comparés exactement ; image et PDF.
7. Suppression réelle pour tous via l'API autorisée, relecture du tombstone : `open` refuse
   `.removed`, alors que le cache scellé contient **encore** les octets (le refus vient donc du
   point d'entrée serveur, pas d'un cache vide) ; téléchargement purgé → `.notFound` ; même
   compte hors de son école → `.accessChanged` (droits serveur, aucun élargissement).
8. Nettoyage des racines temporaires et des espaces Keychain créés par l'exécution, y compris sur
   échec (`defer`). Bornes : chaque échange est borné par les délais URLSession du transport média
   (20 s par requête, 30 s par ressource) et la durée de vie du relais jetable ; aucune attente de
   condition sans échéance, aucun `await` dans une autoclosure XCTest, aucune mutation d'acteur
   externe depuis une assertion.

Campagne exacte (workflow existant, aucun workflow nouveau) : `refonte-ios.yml` avec
`unit_only: true`, `unit_test_scope: all`, au SHA qui portera ce test. La preuve future doit
citer ce nom de test et ce SHA, et non le seul relais texte déjà vert sur `e2edc85e`.

## 5. Limites et points ouverts

- **Swift NON COMPILÉ / NON EXÉCUTÉ** : aucun Xcode ni simulateur ici. Les signatures employées
  sont celles réellement présentes dans ce worktree (génération des scénarios sur les APIs
  actuelles), mais la compilation fera foi.
- **Dépendance M97 correction1** : le coordinateur peut encore évoluer ; ce test est écrit sur
  les signatures présentes, le SHA de correction sera fourni par le coordinateur pour
  l'intégration. Aucun défaut produit n'a été masqué et aucune attente n'a été abaissée.
- La machine Megolm n'est pas rouverte en parallèle du même magasin scellé (deux écrivains sur un
  même store SQLCipher ne sont pas ouverts simultanément) : la réouverture porte sur le coffre
  média (file + cache + Keychain), pas sur un second magasin crypto concurrent.
- **Non prouvé par ce lot** : résidence suisse, sauvegarde/restauration et non-résurrection
  (`MED68-07/08/09` restent NON FOURNIS), appareil physique, VoiceOver, GPS, batterie. Aucun
  résultat Apple n'est simulé.
- Aucun secret, jeton, nom personnel, clé ni URL avec identifiants n'est journalisé ou versionné :
  les certificats du test Node sont générés éphémèrement sous le répertoire temporaire et
  supprimés, les clés Keychain et les racines média sont propres à chaque exécution.
