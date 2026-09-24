# Drivy web et session BFF

Client React/TypeScript distinct du client Swift ; serveur Fastify avec session de même origine. Cette tranche sert la connexion, la liste des écoles du compte et la lecture/acceptation d’une invitation. Le web de gestion complet reste à construire.

## Développement local

Depuis la racine, après le provisionnement de l’identité décrit dans `docs/implementation/dev-identity.md` :

```powershell
npm ci --prefix apps/web
docker compose -f infra/dev/compose.yaml up -d mailpit
node --import tsx scripts/dev/setup-web.ts
npm run typecheck --prefix apps/web
npm test --prefix apps/web
npm run build --prefix apps/web
node --import tsx scripts/dev/check-web.ts
```

`setup-web.ts` configure uniquement Keycloak sur loopback : client confidentiel `drivy-web`, callback exact `http://127.0.0.1:3002/app/bff/callback`, PKCE S256, scopes `openid profile email`, inscription d’identité et vérification email avec Mailpit local. Le client Apple reçoit aussi le scope email. Les secrets sont créés dans `infra/dev/.state/web-runtime.json`, protégé et ignoré. Aucun identifiant n’est créé dans la base métier par ce script.

Pour une session de développement persistante, lancer `scripts/dev/run-api.ts` et `scripts/dev/run-web.ts` dans deux terminaux après le build, puis ouvrir `http://127.0.0.1:3002/app`. Le contrôle `check-web.ts` exige ces ports libres et démarre ses propres serveurs. Mailpit est accessible uniquement sur `127.0.0.1:8025`, SMTP sur `127.0.0.1:1025` ; il conserve des messages synthétiques locaux, sans relai extérieur.

Le lockfile de `apps/web` reste séparé du serveur API. Les commandes de racine ciblent encore l’API ; les vérifications web sont explicitement appelées par CI.

## Configuration du serveur

Variables obligatoires : `WEB_ORIGIN` (origine HTTPS sans chemin), `API_BASE_URL` (préfixe API, par exemple `/refonte`), `OIDC_ISSUER`, `OIDC_WEB_CLIENT_ID`, `OIDC_WEB_CLIENT_SECRET`. Ne pas utiliser de variable `VITE_*` pour un secret. `WEB_HOST` vaut `127.0.0.1` et `WEB_PORT` vaut `3002` par défaut. Le client confidentiel doit avoir son callback exact `${WEB_ORIGIN}/app/bff/callback` et l’audience d’accès `drivy-api`.

`WEB_DEVELOPMENT=true` autorise uniquement les origines loopback et ne peut pas être activé sous `NODE_ENV=production`. Il utilise un cookie local au nom distinct. Le serveur normal exige HTTPS et `__Host-drivy-session; Secure; HttpOnly; SameSite=Lax; Path=/`, sans Domain. Le proxy doit exclure `/app` et `/app/bff` des logs contenant URLs/cookies, et servir le BFF uniquement depuis l’origine configurée.

## Contrat et continuité

- `GET /app/bff/session` donne l’état de connexion et une valeur CSRF, jamais les jetons OIDC. Les POST JSON exigent cette valeur dans `X-CSRF-Token` et l’Origin exacte.
- `POST /app/bff/login {}` prépare state/nonce/PKCE ; callback vérifié et consommé une fois. L’identifiant et la valeur CSRF de session sont renouvelés après connexion. Les signatures ID token sont vérifiées par JWKS en plus des claims et de TLS.
- Le lien `/app/invitation#token=…` est nettoyé immédiatement dans le navigateur. `POST /app/bff/invitation {token}` retient l’invitation en mémoire serveur durant l’aller-retour OIDC. Le jeton n’est jamais placé dans une query string ou un stockage navigateur.
- `POST /app/bff/invitation/preview {}` rend l’école, le rôle, la notice et une confirmation opaque. `POST /app/bff/invitation/accept {invitationId,confirmation}` vérifie l’aperçu présenté, puis envoie AP04 avec `operationId` et `Idempotency-Key` identiques. Une seconde fenêtre ne peut pas changer la cible du premier clic.
- Une réponse perdue conserve l’intention et sa clé. Réessayer relit l’autorisation API ; aucun contexte de membership n’est accepté depuis un cache. Fermer/remplacer cette intention est refusé tant que son résultat reste incertain. Après perte de session serveur, rouvrir le même lien et se reconnecter permet la récupération métier contrôlée par AP04, sans recréer un dossier déjà accepté.
- `POST /app/bff/logout {}` détruit la session locale et demande la révocation du refresh token. Il ne prétend pas effacer la session SSO du fournisseur ; la prochaine connexion exige le formulaire. L’invitation préparée est aussi supprimée : rouvrir le lien pour changer de compte.

Les sessions sont en mémoire d’un **seul processus**, bornées à 10 000, avec 10 minutes d’inactivité anonyme, 30 minutes authentifiée et 2 heures absolues. Un redémarrage déconnecte les navigateurs. Pas de promesse multi-instance ni de continuité du brouillon après fermeture ; aucune donnée scolaire ou refresh token dans localStorage, IndexedDB ou service worker. Les droits restent relus par l’API à chaque opération.

## Preuves de cette tranche

Tests BFF : cookie/CSRF, state et rotation, expiration, déconnexion pendant refresh, refresh concurrent, absence de jetons dans les réponses, changement d’invitation/notice entre onglets, reprise après réponse perdue et reprise sans droits mis en cache. Deux tests HTTP vérifient le header d’idempotence AP04 et le refus des redirections amont. `check-web.ts` exerce Edge, Keycloak, BFF et PostgreSQL réels, avec le bouton React et l’école synthétique affichée. Ce contrôle de connexion ne qualifie ni l’email d’invitation complet, ni un déploiement web public, ni un appareil Apple.

Sources de bibliothèques : [openid-client](https://github.com/panva/openid-client), [cookie Fastify](https://github.com/fastify/fastify-cookie), [Vite](https://vite.dev/guide/).
