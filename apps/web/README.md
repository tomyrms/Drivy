# Drivy web et session BFF

Client React/TypeScript distinct du client Swift ; serveur Fastify avec session de même origine. Il sert la connexion, la liste des écoles du compte, la lecture/acceptation d’une invitation et le **web de gestion** de l’administration (`/app/gestion/{schoolId}/…`).

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
- `POST /app/bff/logout {}` détruit la session locale et demande la révocation du refresh token. Le client relit le CSRF et attend la confirmation avant d’effacer son état ; un refus ou une réponse perdue laisse une erreur et permet de réessayer. Il ne prétend pas effacer la session SSO du fournisseur ; la prochaine connexion exige le formulaire. L’invitation préparée est aussi supprimée : rouvrir le lien pour changer de compte.

Les sessions sont en mémoire d’un **seul processus**, bornées à 10 000, avec 10 minutes d’inactivité anonyme, 30 minutes authentifiée et 2 heures absolues. Un redémarrage déconnecte les navigateurs. Pas de promesse multi-instance ni de continuité du brouillon après fermeture ; aucune donnée scolaire ou refresh token dans localStorage, IndexedDB ou service worker. Les droits restent relus par l’API à chaque opération.

## Web de gestion (administration)

Les activités d’ordinateur de l’administrateur quittent l’iPhone pour une console de bureau : navigation latérale avec menu sur petit écran, liste + panneau de détail, formulaires à libellés permanents et confirmation des commandes sensibles. La direction « Encre et papier » et les tokens de `client/styles.css` sont propres au web ; clair/sombre, contraste accru et couleurs forcées restent pris en charge.

| Écran (chemin) | Lectures | Écritures (commande, If-Match) |
|---|---|---|
| Préparation (`apercu`) | école, readiness, data-policy, listes du catalogue et des champs | — (prochaines étapes calculées) |
| Agenda (`agenda`) | leçons de la semaine, élèves actifs ou archivés, moniteurs | Lecture seule ; démarrage et fin dans l’app. `actualStart` distingue une leçon commencée ; un horaire dépassé sans démarrage reste « En attente ». |
| Disponibilités (`disponibilites`) | moniteurs, horaires et absences | Ajout et retrait versionné des horaires et absences |
| Dossiers (`eleves`) | élèves, formations, affectations, permis, progression, bilans publiés | Ouverture et transition des formations, affectation/retrait du moniteur, permis, archivage/restauration |
| Trajets (`trajets`) | captures autorisées dans l’école, filtre élève ou pages de l’historique | Lecture seule |
| Formations (`formations`) | offres et versions liées de catalogue | Navigation contextuelle vers offres, compétences, procédures et tarifs |
| Configuration (`configuration`) | école, setup, data-policy, readiness | `PATCH /` coordonnées (version école) · `PUT data-policy` adoption (version politique) · `PATCH setup` avancement (version setup) · `POST activate` (version école + `expectedConfigurationVersion`) |
| Champs du profil (`champs-profil`) | profile-field-policies, data-policy (+ notice liée `?noticeVersionId=`) | `POST profile-field-policies` (If-Match version école) · `POST …/{id}/publish` (version politique) |
| Offres (`offres`) | offerings, curricula, policy-versions | `POST offerings` (nouvelle version, désactivée sauf activation cochée) |
| Référentiels (`referentiels`), Procédures (`procedures`) | curricula / policy-versions | `POST curricula` / `POST policy-versions` : révision immuable, approbation cochée + motif + accusé de relecture |
| Prestations et tarifs (`prestations`), Conditions commerciales (`conditions`) | service-products / commercial-terms | `POST service-products` / `POST commercial-terms` (autorisation `CONFIGURE_CATALOG`) |
| Équipe et accès (`equipe`) | members | `PATCH members/{id}` rôles, autorisations, motif (version membre ; `REAUTH_REQUIRED` → reconnexion) |
| Invitations (`invitations`) | invitations | `POST invitations` · `POST …/{id}/resend` · `POST …/{id}/revoke` (version invitation) |

L’entrée sans rubrique ouvre l’agenda d’une école active, sinon sa préparation. Les liens et le retour navigateur conservent les identifiants de sélection et les filtres autorisés. Changer de semaine, filtre, dossier ou page masque immédiatement les données de l’ancien contexte ; une relecture du même contexte conserve les données avec erreur explicite si elle échoue.

Rien n’est approuvé implicitement : approbation et activation sont décochées par défaut, et « Approuver… » sur un brouillon crée une nouvelle version identique approuvée (les versions existantes ne sont jamais réécrites). Les droits affichés viennent de `/v1/me`, relu après confirmation d’une commande et au retour depuis le cache de navigation (rôle Administration requis pour ouvrir la console, `CONFIGURE_CATALOG` pour le commercial) ; ils masquent ou désactivent seulement, l’API reste l’autorité.

**Commandes et reprise AP72.** Chaque écriture reçoit un `operationId` envoyé aussi comme `Idempotency-Key` ; l’If-Match porte la version affichée (`"n"`). Aucun succès n’est affiché avant une réponse 200/201 vérifiée (école, version postérieure). Règles (`client/command-core.ts`, reprises de `SchoolCommandOutbox.swift`) :

- réponse perdue, 408, 429, 5xx, session perdue pendant la réponse, CSRF périmé : la demande reste **incertaine** ; le panneau « Demande à vérifier » (sur tous les écrans) nomme la demande (type, date) et propose « Vérifier auprès de l’école » (`GET operations/{operationId}`, reçu comparé : opération, type, ressource, version) puis « Renvoyer la même demande » (mêmes corps, clé et If-Match) ;
- tout refus 4xx (hors 408, 429 et `IDEMPOTENCY_MISMATCH`), avec ou sans code lisible, tant qu’aucun envoi antérieur n’a pu atteindre l’école : libérée, saisie conservée, rechargement proposé ; après une incertitude, le même refus ne prouve rien et la demande reste à vérifier ;
- vérification 404 (l’école ne retrouve pas la demande) : le panneau le dit et propose « Renvoyer la même demande » ou « Abandonner la demande… » (confirmation) ; un refus de ce renvoi est alors définitif. Après abandon, arrêt du suivi ou refus d’un renvoi, les rubriques relisent l’école ;
- vérification refusée (403) ou reçu illisible : « Arrêter le suivi… » devient disponible, avec avertissement ;
- une seule demande en attente par école ; les autres écritures sont désactivées avec leur raison.

La demande complète vit en mémoire de la page. `sessionStorage` (onglet courant) garde seulement ses identifiants (`operationId`, école, type, ressource, version, date), jamais le contenu saisi : après un rechargement ou une reconnexion, le résultat peut encore être vérifié ; si l’école ne l’a pas enregistré, la modification est à refaire. « Arrêter le suivi » n’est proposé qu’avec un avertissement (contenu perdu, refus lors d’une reprise, reçu absent, vérification refusée ou illisible). La déconnexion efface ce suivi.

### Routes BFF de gestion

`GET|POST|PATCH|PUT /app/bff/schools/{schoolId}/…` n’est **pas** un proxy ouvert : `server/school-routes.ts` déclare chaque couple méthode + chemin (UUID stricts, aucun segment vide/encodé/`..`, requête limitée à `limit`, `cursor` ou `noticeVersionId` selon la route, sans doublon). Tout autre chemin répond 404 sans utiliser le jeton ; `server/upstream.ts` revérifie la liste avant l’appel.

| Méthode | Chemin sous `/v1/schools/{schoolId}` | If-Match |
|---|---|---|
| GET | ``, `setup`, `readiness`, `data-policy`, `operations/{id}`, `members`, `invitations`, `offerings`, `curricula`, `policy-versions`, `commercial-terms`, `service-products`, `profile-field-policies` | — |
| PATCH | ``, `setup`, `members/{id}` | requis |
| PUT | `data-policy` | requis |
| POST | `activate`, `invitations/{id}/resend`, `invitations/{id}/revoke`, `profile-field-policies`, `profile-field-policies/{id}/publish` | requis |
| POST | `invitations`, `offerings`, `curricula`, `policy-versions`, `commercial-terms`, `service-products` | refusé |

Lectures : session requise. Écritures : Origin exacte, `X-CSRF-Token`, `Content-Type: application/json`, corps objet sous la limite de la route, `Idempotency-Key` UUID égal à `operationId` du corps, If-Match fort `"n"` exigé (428) ou refusé selon la route. Seuls `Authorization`, `Accept`, `Content-Type`, `Idempotency-Key` et `If-Match` partent vers l’API, sans cookie ni redirection ; l’ETag fort de l’API est renvoyé, les réponses restent `no-store`, les erreurs ne gardent que le code. Un 401 `REAUTH_REQUIRED` conserve la session (reconnexion demandée) ; tout autre 401 amont la détruit. `POST /app/bff/login {returnTo?}` accepte un retour vers `/app/gestion/…` seulement. Le serveur statique sert `/app/gestion` et `/app/gestion/*`.

### Reste à qualifier ou à construire

- Pas de test navigateur automatisé en CI : la console a été relue par captures Chromium locales sur un faux BFF synthétique (clair, sombre, 390 px). Aucun essai avec l’API et Keycloak réels, ni lecteur d’écran réel.
- Hors des parcours web implémentés : capture GPS, démarrage/fin de leçon, édition détaillée du profil administratif d’un élève, règlements, packs/cours collectifs et documents. Les disponibilités, dossiers, formations et affectations existent dans les rubriques ci-dessus.
- Les listes chargent au plus 1 000 éléments (10 pages) ; au-delà, la liste est signalée partielle.

Passe de stabilité du 9 octobre 2026 : [corrections, contrôles locaux et limites](../../docs/implementation/stabilite-web-20261009.md). Les refus de permis, formation, archivage ou accès gardent la saisie et présentent l’erreur dans le dialogue ouvert.

## Preuves de cette tranche

Tests BFF : liste blanche de gestion, CSRF et propagation Idempotency-Key/If-Match/ETag (`test/school-bff.test.ts`, dont un échange HTTP réel), règles de commande et reprise AP72 (`test/command-core.test.ts`), cookie/CSRF, state et rotation, expiration, déconnexion pendant refresh, refresh concurrent, absence de jetons dans les réponses, changement d’invitation/notice entre onglets, reprise après réponse perdue et reprise sans droits mis en cache. Deux tests HTTP vérifient le header d’idempotence AP04 et le refus des redirections amont. `check-web.ts` exerce Edge, Keycloak, BFF et PostgreSQL réels, avec le bouton React et l’école synthétique affichée. Ce contrôle de connexion ne qualifie ni l’email d’invitation complet, ni un déploiement web public, ni un appareil Apple.

Sources de bibliothèques : [openid-client](https://github.com/panva/openid-client), [cookie Fastify](https://github.com/fastify/fastify-cookie), [Vite](https://vite.dev/guide/).
