# Identité OIDC réelle sur le poste de développement

Cet environnement relie un vrai fournisseur OIDC à l’API G1A et aux seules fixtures synthétiques locales. Il sert au développement de la connexion Apple et à la vérification des droits. Il n’ouvre aucun service sur le réseau local ou Internet.

La conception recommande un fournisseur maintenu et cite ZITADEL comme candidat à qualifier ; elle ne rend pas ce choix obligatoire ([ADR identité](../../Drivy_Conception_v3_17_2026-09-20/04-technique/architecture-decisions.md), [exploitation](../../Drivy_Conception_v3_17_2026-09-20/05-realisation/deploiement-exploitation.md)). Keycloak est ici un choix d’implémentation du laboratoire local, sans qualification d’hébergement de production.

## Démarrage reproductible

Prérequis : Node 24, npm, Docker Compose avec daemon actif, Microsoft Edge installé. Les ports loopback `55432`, `8081` et `3001` doivent être disponibles. Depuis la racine du dépôt :

```powershell
npm ci
npm ci --prefix infra/dev --ignore-scripts
node --import tsx scripts/dev/setup.ts
node --import tsx scripts/dev/check.ts
```

`setup.ts` démarre PostgreSQL via le compose racine, puis Keycloak via [le compose séparé](../../infra/dev/compose.yaml). Il applique les migrations existantes à `drivy_dev`, ajoute les fixtures synthétiques, crée six vrais comptes et relie leurs UUID `sub` aux personnes en base. Il ne lit pas les anciennes données Drivy. Cette commande reste une opération de développement explicite : le démarrage normal de l’API ne crée aucun compte ni donnée.

Une seconde exécution conserve les comptes, leurs mots de passe et les liens vérifiés. Une configuration existante incohérente ou des secrets locaux perdus font échouer la commande ; elle ne réaffecte pas silencieusement un compte. Les fixtures utilisent `ON CONFLICT DO NOTHING` et ne réinitialisent pas un état métier modifié manuellement.

`check.ts` exige le port `3001` libre. Il démarre lui-même l’API réelle pour la durée des contrôles puis la ferme. Il ne faut donc pas lancer `run-api.ts` en parallèle. Le contrôle utilise Edge dans un profil éphémère distinct du profil personnel, sans screenshot, trace ou export de session. Pour Chrome installé :

```powershell
$env:DRIVY_BROWSER_CHANNEL = 'chrome'
node --import tsx scripts/dev/check.ts
```

Pour laisser l’API disponible pendant un développement client, après les contrôles :

```powershell
node --import tsx scripts/dev/run-api.ts
```

Le lanceur charge les variables nécessaires depuis l’état local ; il n’est pas nécessaire de recopier un secret dans le terminal. Arrêter avec Ctrl+C. Pour arrêter les conteneurs en conservant leurs volumes :

```powershell
docker compose -f infra/dev/compose.yaml stop
docker compose stop postgres
```

## Contrat d’environnement

| Élément | Valeur locale |
|---|---|
| Issuer | `http://127.0.0.1:8081/realms/drivy-dev` |
| Discovery | `http://127.0.0.1:8081/realms/drivy-dev/.well-known/openid-configuration` |
| Client public | `drivy-apple`, sans secret client |
| Callback exact | `ch.drivy.qualification:/oauth/callback` |
| Flux | Authorization Code, PKCE `S256` obligatoire, `state` et `nonce` |
| Scopes demandés | `openid profile` |
| Scopes Keycloak par défaut | `basic`, `profile` ; aucun scope optionnel |
| Audience d’accès API | `drivy-api` |
| API | `http://127.0.0.1:3001`, chemins `/v1/...` |
| Base | `drivy_dev`, PostgreSQL sur `127.0.0.1:55432` |

Le scope Keycloak `basic` contient le mapper `sub`, nécessaire au lien d’identité de l’API. L’audience `drivy-api` est ajoutée uniquement à l’access token, pas à l’ID token. La connexion par password grant, le flux implicite et les comptes de service du client Apple sont désactivés. Le renouvellement utilise le refresh token standard avec rotation ; aucun `offline_access` n’est demandé. Voir les [scopes et mappers Keycloak](https://www.keycloak.org/docs/26.7.0/server_admin/) et le [mapper d’audience](https://www.keycloak.org/admin-api/protocol-mappers).

Le provisionnement utilise séparément `admin-cli` dans le realm administratif `master`, seulement sur loopback, pour appeler l’API d’administration. Ce mécanisme ne sert pas à connecter l’utilisateur Apple. Le compte administratif aléatoire est propre à ce laboratoire.

Le lanceur configure `NODE_ENV=development`, `HOST=127.0.0.1`, `PORT=3001`, `DATABASE_URL`, `OIDC_ISSUER`, `OIDC_AUDIENCE`, `OIDC_JWKS_URL` et `CURSOR_SECRET`. L’API conserve sa vérification JOSE des signatures, issuer, audience et claims requis, puis relit les droits dans PostgreSQL. Aucun vérificateur d’identité simulé n’est injecté.

## Comptes synthétiques et secrets

| Identifiant | Droit préparé |
|---|---|
| `demo-admin` | Administration de l’école Horizon |
| `demo-instructor` | Moniteur Horizon affecté à Alice ; administration de Rivage |
| `demo-alice` | Élève Horizon, son propre dossier |
| `demo-bob` | Élève Horizon, autre dossier |
| `demo-other-instructor` | Monitrice Horizon sans affectation |
| `demo-foreign` | Élève Rivage |

Les mots de passe sont créés aléatoirement et écrits uniquement dans `infra/dev/.state/accounts.json`. Le compte bootstrap et la clé des curseurs sont dans `runtime.json`, et l’environnement du conteneur dans `keycloak.env`, dans le même répertoire ignoré par Git. Le script restreint ce répertoire au compte Windows courant et à SYSTEM, ou applique `0700`/`0600` sur POSIX. Ne pas joindre ces fichiers aux issues, artefacts ou captures. La valeur PostgreSQL de développement reste celle, explicitement locale et publique, du compose racine.

Les données Keycloak sont conservées dans le volume `drivy-identity-dev_keycloak-data`. Les fichiers privés et ce volume forment un état cohérent : ne pas supprimer une seule moitié pour tenter de remettre un mot de passe à zéro. Aucune suppression de volume ou réinitialisation destructive n’est automatisée.

## Contrôles réalisés et limites

Le 24 septembre 2026, deux exécutions complètes ont réussi sur Windows, Docker, PostgreSQL 17.11, Keycloak 26.7.4 et Edge `153.0.4234.48` : **29 contrôles**. Le provisionnement a également été réexécuté sans recréer les comptes. Le dernier rapport local, sans jeton ni mot de passe, est `infra/dev/.state/check-result.json`.

Les contrôles couvrent la discovery, l’obligation PKCE, le refus d’un callback inconnu et du password grant Apple, puis six connexions réelles par formulaire navigateur. Ils vérifient signatures, audience, nonce, UUID sujet et `/v1/me`, les dossiers et formations autorisés, les refus entre élèves/écoles/affectations, le refus d’un ID token dans l’API, un mauvais vérificateur PKCE, le rejeu d’un code, la rotation du refresh token et sa non-réutilisation. Une révocation de membership est vérifiée avec un access token encore valide, puis restaurée avec une nouvelle `accessEpoch` dans la seule fixture locale.

Le navigateur soumet le vrai formulaire Keycloak avec ses cookies. Le contrôle capture la réponse de redirection vers le schéma Apple et annule cette navigation, puis échange le code contre le fournisseur réel. Il ne lance pas d’application Windows associée à ce schéma. Le test ne qualifie donc pas `ASWebAuthenticationSession`, le Keychain, le callback iOS ou le parcours Swift.

Vérifications supplémentaires : `npx tsc -p infra/dev/tsconfig.json` réussi ; `npm audit --prefix infra/dev --omit=dev` n’a signalé aucune vulnérabilité connue lors de cette exécution. Ces constats ne remplacent pas les tests API, les tests natifs ou la recette physique G0.

Un iPhone physique interprète `127.0.0.1` comme sa propre machine. Cet environnement Windows n’est donc pas accessible depuis l’iPhone. Un simulateur sur un autre Mac ne peut pas non plus utiliser le loopback Windows. Il faudra un environnement HTTPS distinct, son issuer/client et ses comptes propres ; ouvrir les ports Windows au LAN ne fait pas partie de ces scripts. Keycloak fonctionne ici en `start-dev` avec son stockage local H2 : cette composition n’est pas un déploiement de production.

## Versions et sources

L’image est verrouillée sur `quay.io/keycloak/keycloak:26.7.4@sha256:82a77884f3af238beab1e7afd63b5f530e1b5c0590bd7aa60b40a40463e29b2c` (index multiarchitecture vérifié dans le registre). Le [démarrage Docker officiel](https://www.keycloak.org/getting-started/getting-started-docker) et les [paramètres du conteneur](https://www.keycloak.org/server/containers) documentent cette version et le bootstrap. Le provisionnement emploie l’[API REST administrative](https://www.keycloak.org/docs-api/latest/rest-api/index.html).

`playwright-core` est verrouillé à `1.63.0` avec son lockfile indépendant dans `infra/dev`; aucun binaire de navigateur n’est téléchargé par l’installation. Edge ou Chrome est fourni par le poste, et sa version réelle figure dans le rapport. Les [canaux navigateur Playwright](https://playwright.dev/docs/browsers#google-chrome--microsoft-edge) décrivent cette utilisation. Les versions serveur restent celles du lockfile racine.
