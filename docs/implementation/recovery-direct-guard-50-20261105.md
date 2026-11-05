# Garde directe de récupération — composant local qualifié (#50)

5 novembre 2026, base `e2edc85ed092237016620079d52d11eb7a2d02b5`. Ce lot livre un **composant local
optionnel** et sa **recette réelle synthétique**. Il ne remplace pas le refus 503 de Caddy, ne modifie ni
`app.ts`, ni `config.ts`, ni `infra/`, ni le realm, ni les flux d'authentification ou de droits. Aucun service
homelab n'est lu ou modifié, aucun envoi SMTP externe n'est effectué. **#50 reste ouverte** : SMTP réel et
reprise physique Face ID restent distincts.

## Ce qui est livré

| Fichier | Rôle |
|---|---|
| `apps/web/server/recovery-direct-guard.ts` | Frontière HTTP étroite : configuration validée, adresse prouvée, compteur, transfert borné du flux Keycloak |
| `apps/web/server/recovery-direct-guard-main.ts` | Point d'entrée séparé, **jamais lancé par l'application web actuelle** |
| `apps/web/server/rate-limit.ts` | Capacité additive `retryAfterSeconds(key)` uniquement ; `allow()` et ses usages sont inchangés |
| `apps/web/test/recovery-direct-guard.test.ts` | 38 tests du point d'entrée HTTP réel, sans conteneur |
| `scripts/dev/check-recovery-direct-guard-50.ts` | Recette intégrée Keycloak 26.7.4 + Mailpit, opt-in, conteneurs jetables |

Aucun second moteur de récupération : la garde ne crée ni lien, ni jeton, ni mot de passe, ni session.

## Contrat de la frontière

### 1. Configuration explicite, échec fermé

Toute valeur absente, hors bornes ou ambiguë lève `RECOVERY_GUARD_CONFIG_INVALID` ; le message ne contient
aucune valeur. Variables et valeurs par défaut :

| Variable | Défaut | Règle |
|---|---|---|
| `RECOVERY_GUARD_HOST` | `127.0.0.1` | Boucle locale par défaut ; une autre adresse exige `RECOVERY_GUARD_ALLOW_NON_LOCAL=true` |
| `RECOVERY_GUARD_PORT` | — | Obligatoire, 1–65535 |
| `RECOVERY_GUARD_UPSTREAM_ORIGIN` | — | `http(s)://hôte[:port]` seul : ni identifiants, ni chemin, ni requête, ni fragment |
| `RECOVERY_GUARD_IDENTITY_PATH` | `/` | `http-relative-path` de Keycloak (`/` ou `/identity`) ; segments sûrs, ni `.`, ni `..`, ni `%`, ni `//` |
| `RECOVERY_GUARD_REALM` | — | `[A-Za-z0-9][A-Za-z0-9._-]{0,63}` |
| `RECOVERY_GUARD_PUBLIC_HOST` | — | `hôte[:port]` vu par le navigateur ; ni espace, ni barre, ni saut de ligne |
| `RECOVERY_GUARD_PUBLIC_SCHEME` | `https` | `http` n'est accepté que pour un hôte public de boucle locale |
| `RECOVERY_GUARD_TRUSTED_PROXIES` | vide | Liste **explicite** d'IP/CIDR ; vide = adresse du socket uniquement |
| `RECOVERY_GUARD_LIMIT` | `30` | 1–600 |
| `RECOVERY_GUARD_WINDOW_MS` | `600000` | 1 s–24 h |
| `RECOVERY_GUARD_CAPACITY` | `4096` | 1–100000 entrées |
| `RECOVERY_GUARD_UPSTREAM_TIMEOUT_MS` | `10000` | 0,5–120 s |
| `RECOVERY_GUARD_MAX_BODY_BYTES` | `16384` | 256 o–1 Mio |
| `RECOVERY_GUARD_MAX_RESPONSE_BYTES` | `1048576` | 4 Kio–16 Mio |

Le chemin servi est calculé une fois : `${IDENTITY_PATH}/realms/${REALM}/login-actions/reset-credentials`.
`/` + `drivy` donne `/realms/drivy/login-actions/reset-credentials`.

### 2. Une seule route, comparée octet par octet

- Seules `GET` et `POST` sont acceptées ; toute autre méthode reçoit `405` avec `Allow: GET, POST`.
- Seul le chemin exact de récupération est servi. Toute autre route — autre realm, autre action Keycloak,
  barre finale, `.`/`..`, `%2e`, `%2f`, `//`, cible absolue `http://…` — reçoit `404` localement.
  Le chemin n'est ni décodé, ni normalisé : aucune traversée ni proxy ouvert.
- La requête brute est bornée à 4096 octets ; les caractères de contrôle dans la requête sont refusés (`400`).
- La requête (query) est transmise telle quelle mais ne peut changer ni l'origine, ni le chemin amont.
- `GET` avec corps (`Content-Length ≠ 0` ou `Transfer-Encoding`) → `400`.
- `POST` exige `application/x-www-form-urlencoded` (charset UTF-8 toléré) sans `Content-Encoding`, sinon `415`.

### 3. Adresse prouvée, jamais devinée

- **Mode direct** (aucun pair configuré) : l'adresse est celle du socket ; `Forwarded`, `X-Forwarded-For`,
  `X-Real-IP` et `X-Original-Forwarded-For` sont ignorés.
- **Mode proxy** (liste explicite) : le pair doit appartenir à un CIDR/IP configuré, sinon `403`. Seule la
  **dernière** valeur de `X-Forwarded-For` est lue (le proxy de confiance l'écrase ou l'ajoute) ; une chaîne
  malformée, une valeur vide ou une adresse invalide est refusée (`403`). Aucune confiance n'est déduite des
  plages privées, ni de `Forwarded`, `X-Real-IP` ou `X-Original-Forwarded-For`.
- `clientKey()` existant est réutilisé : IPv4 inchangée, IPv4 projetée (`::ffff:a.b.c.d`) ramenée à l'IPv4,
  IPv6 regroupée au préfixe `/64`.

### 4. Compteur : portée exacte

- 30 requêtes `GET`+`POST` **partagées** par adresse prouvée sur 10 minutes, cohérent avec l'entrée anonyme du BFF.
- Le compteur est consulté **après** la preuve d'adresse et **avant** la lecture du corps et le transfert :
  un refus `429` ne produit aucun envoi supplémentaire.
- `Retry-After` donne l'attente utile (secondes entières restantes de la fenêtre), sans décrire aucun compte.
- Table bornée (`capacity`) : quand elle est pleine de fenêtres vivantes, un balayage est tenté puis les
  nouvelles clés sont **refusées** (`429`), jamais ajoutées.
- **Portée réelle : un seul processus local, en mémoire.** Un redémarrage rouvre le budget complet. Ce n'est
  ni une limite distribuée, ni une limite persistante ; activer un cluster ou une persistance serait un autre
  choix, pas une dépendance silencieuse.

### 5. Transfert honnête du flux Keycloak

- Origine et chemin amont sont fixés par la configuration ; `Host` et `X-Forwarded-Host` sont réécrits avec
  l'hôte public configuré, `X-Forwarded-Proto`/`X-Forwarded-Port` avec le schéma/port publics. Un client ne
  peut pas changer la cible.
- En-têtes de requête relayés, liste fermée : `accept`, `accept-language`, `content-type`, `cookie`, `origin`.
  Ne sont jamais transmis : `Forwarded`, `X-Real-IP`, `X-Original-Forwarded-For`, `Authorization`, `Referer`,
  `If-None-Match`, `Accept-Encoding`, ni un `Host` client.
- En-têtes de réponse relayés, liste fermée : `content-type`, `content-language`, `location`, `set-cookie`,
  `content-security-policy`, `x-frame-options`, `x-content-type-options`, `referrer-policy`,
  `strict-transport-security`, `x-xss-protection`, `x-robots-tag`. Statut et `Location` sont conservés tels
  quels ; `Set-Cookie` du fournisseur (session de flux) est préservé. Aucun cookie Drivy n'est créé.
- Aucun cache : `Cache-Control: no-store` et `Pragma: no-cache` sur toute réponse ; les deux en-têtes sont
  aussi imposés vers l'amont.
- Corps de requête borné (`16384` o par défaut), réponse bornée (`1 Mio`), délai de socket et échéance absolue
  (10 s par défaut), socket client fermé → requête amont détruite. Aucun retry, en particulier jamais de
  `POST` rejoué.
- Panne du fournisseur (connexion refusée, délai, réponse `5xx`, réponse trop grande, encodage non identité) :
  `502` générique « La récupération est momentanément indisponible. », sans corps amont ni détail. Une réponse
  `4xx` du fournisseur est relayée telle quelle (page d'erreur Keycloak), ce qui ne décrit aucun compte.
- La garde n'interprète jamais une réponse comme « courrier envoyé » et ne crée aucune session applicative.

## Exemple de configuration — NON ACTIF

À revoir avant toute activation ; rien de ceci n'est appliqué par ce lot.

```sh
# Garde locale, sur l'hôte qui porte déjà Keycloak (192.168.1.153).
RECOVERY_GUARD_HOST=192.168.1.153        # joignable par Caddy (192.168.1.147) uniquement
RECOVERY_GUARD_ALLOW_NON_LOCAL=true      # confirmation explicite de l'écoute privée
RECOVERY_GUARD_PORT=8082
RECOVERY_GUARD_UPSTREAM_ORIGIN=http://127.0.0.1:8081
RECOVERY_GUARD_IDENTITY_PATH=/identity
RECOVERY_GUARD_REALM=drivy
RECOVERY_GUARD_PUBLIC_HOST=drivy.shulker.ch
RECOVERY_GUARD_PUBLIC_SCHEME=https
RECOVERY_GUARD_TRUSTED_PROXIES=192.168.1.147
```

```caddyfile
# NON ACTIF — remplace le refus 503 seulement après qualification du SMTP réel et de cette garde.
handle /identity/realms/drivy/login-actions/reset-credentials {
    reverse_proxy 192.168.1.153:8082 {
        header_up -Forwarded
        header_up X-Forwarded-For {remote_host}
        header_up -X-Real-IP
        header_up -X-Original-Forwarded-For
        header_up -X-Forwarded-Access-Token
    }
}
```

Le cloisonnement est une condition, pas une conséquence :

1. le port de la garde n'est joignable que depuis le pair Caddy configuré (pare-feu ou écoute privée) ;
2. Caddy route le chemin exact vers la garde et **aucune autre route publique n'atteint le chemin
   `reset-credentials` de Keycloak** — y compris après normalisation Caddy (barres, casse, encodage) ; le
   bloc ci-dessus doit rester **à la place du refus 503**, avant `handle @drivyIdentityPublic` ;
3. Keycloak reste injoignable depuis le réseau public sur son port HTTP ;
4. les autres chemins `/identity/*` continuent d'aller directement à Keycloak ; la garde les refuse
   localement si on les lui présente ;
5. si Keycloak doit voir l'adresse réelle du client, la garde doit figurer dans `proxy-trusted-addresses` de
   `infra/deploy/keycloak.conf` (aujourd'hui seule `192.168.1.147` y est). À défaut, `hostname` fixe continue
   de produire les URL publiques, mais l'adresse vue par Keycloak est celle de la garde.

Sans ces cinq points, la garde ne protège pas la production et le refus 503 doit rester en place.

## Qualification exécutée

Environnement : Windows, Node `24.22.2` portable (aucune installation globale), dépendances des seuls
lockfiles du dépôt installées dans ce worktree.

| Commande | Résultat |
|---|---|
| `node node_modules/vitest/vitest.mjs run test/recovery-direct-guard.test.ts` (dans `apps/web`) | **38/38 réussis, exit 0** |
| `node node_modules/vitest/vitest.mjs run` (suite web complète) | **81 fichiers, 880 réussis, 1 échec attendu, exit 0** |
| `npm run typecheck` (dans `apps/web`) | exit 0 |
| `npm run build` (dans `apps/web`) | exit 0 |
| `node node_modules/typescript/bin/tsc -p infra/dev/tsconfig.json` | exit 2 — **uniquement les trois diagnostics préexistants** (`check-v3-agenda-acceptance.ts`, `check-v3-entry.ts`, `measure-web-entry.ts`), fichiers identiques à `HEAD` |
| `RECOVERY_DIRECT_GUARD_RECIPE=1 npx tsx scripts/dev/check-recovery-direct-guard-50.ts` | **24 contrôles réussis, exit 0** |

Preuve RED : le fichier de tests a d'abord échoué sur le module absent (`Cannot find module
'../server/recovery-direct-guard.js'`, 0 test). Preuve de force : en désactivant localement l'appel au
compteur, **6 tests échouent** (seuil, partage GET/POST, adresses, en-têtes forgés, capacité, fenêtre) ;
restauration → 38/38.

### Ce que couvre le test HTTP (sans conteneur)

Seuil 30 puis refus de la 31e ; compteur partagé `GET`/`POST` ; adresses distinctes ; IPv6 `/64` et IPv4
projetée ; expiration à horloge injectée (60 s → 30 s → reprise) ; table bornée saturée puis balayée ;
`Forwarded`/`X-Forwarded-For`/`X-Real-IP`/`X-Original-Forwarded-For` forgés sans effet en mode direct ; pair
non configuré refusé ; adresse absente/invalide refusée ; configuration invalide (23 cas) ; route échappée,
barre finale, `%2e`, autre realm, autre action, cible absolue ; méthode et type de contenu hors périmètre ;
corps trop grand ; amont fixé et en-têtes interdits non transmis ; `Location` et `Set-Cookie` préservés ;
panne, délai, réponse trop grande et `5xx` → `502` générique identique ; `POST` jamais rejoué ; aucun cookie
de session Drivy.

### Recette réelle synthétique

Conteneurs `drivy-r50-guard-kc` et `drivy-r50-guard-mailpit`, digests déjà verrouillés par le dépôt :
Keycloak `26.7.4@sha256:82a77884…`, Mailpit `v1.31.2@sha256:74d609a4…`. Ports loopback inventoriés avant
création (18081, 18025, 18026, puis 18090–18093 pour les quatre gardes de recette) ; noms et ports en
collision refusés. Realm `drivy-guard-e2e` et compte
`@example.invalid` créés par la recette uniquement, thème Drivy monté en lecture seule, SMTP vers Mailpit.
Aucune base PostgreSQL, aucun BFF, aucune API Drivy.

Contrôles réellement observés (24) :

- `GET` du chemin direct : `200`, formulaire `username`, cookie de flux `AUTH_SESSION_ID` du fournisseur,
  aucun cookie Drivy ;
- `POST` d'une adresse connue : `200`, phrase conditionnelle du thème, **+1 courrier réel** dans Mailpit ;
- adresse inconnue : même statut et **même phrase**, aucun courrier supplémentaire ;
- 30 requêtes `GET`/`POST` autorisées, **31e refusée `429`** avec `Retry-After` utile et **aucun courrier**
  après le refus ;
- seconde adresse prouvée : budget indépendant, son propre courrier ;
- `Forwarded`, `X-Real-IP`, `X-Original-Forwarded-For` forgés : la clé ne change pas (−1 budget), une autre
  adresse reste indépendante ;
- pair non configuré et adresse absente : `403` fermés, aucun courrier ;
- autre action Keycloak et traversée de chemin : `404` locaux ;
- fenêtre courte contrôlée (3 s) : deux autorisations, refus, puis reprise après expiration — sans attendre
  dix minutes ;
- mot de passe synthétique toujours accepté par Keycloak (`password grant`) et identité OIDC inchangée
  (`id`, adresse, `emailVerified`) : la garde ne crée ni ne modifie aucun compte ;
- artefact final : contenu sérialisé contrôlé **avant** écriture, aucun `@`, lien, jeton, cookie ni mot de passe.

Compteurs anonymes de l'artefact : `allowed=34`, `refusedLimit=3`, `refusedAddress=2`, `refusedRoute=2`,
`unavailable=0`, `mails=2`. Nettoyage : realm supprimé, gardes fermées, conteneurs `rm --force`, fichier
d'environnement temporaire supprimé ; aucun conteneur ni fichier résiduel constaté.

## Limites et risques

1. **Portée du compteur** : un processus, en mémoire, remis à zéro au redémarrage. Aucune limite distribuée,
   aucun état partagé, aucun compteur persistant.
2. **Confiance réseau** : la clé vaut ce que vaut le proxy de confiance. Si Caddy n'écrase pas
   `X-Forwarded-For`, un client pourrait choisir sa clé ; le contrat exige l'écrasement, et Caddy le fait
   déjà pour `/app`. La garde ne peut pas prouver l'écrasement au-delà du pair.
3. **Cloisonnement non installé** : le refus 503 reste en place ; aucune route Caddy, aucun realm, aucune
   configuration Keycloak n'a été modifiée.
4. **Réponses uniformes mesurées au niveau affiché** : statut + phrase. Latence et taille de réponse ne sont
   pas mesurées ; elles ne sont pas rendues identiques par la garde.
5. **`4xx` du fournisseur relayés** : la page d'erreur Keycloak est transmise telle quelle pour les statuts
   `< 500` ; les `5xx` et pannes sont remplacés par le message générique.
6. **Pas de protection volumétrique** : la garde limite les requêtes par adresse, pas la bande passante ni
   les connexions ; cela reste le rôle du proxy et du pare-feu.
7. **Aucune preuve de production** : Mailpit et le realm jetable ne qualifient ni le SMTP réel, ni le routage
   public, ni un cluster, ni Face ID.
8. **Rejeu/expiration des jetons d'action** : non touchés par ce lot, déjà qualifiés par
   `recuperation-qualification-50-20261104.md` ; non rejoués ici.

## Reste à faire avant activation

Choisir et qualifier le SMTP réel ; vérifier l'écrasement d'en-tête et le cloisonnement Caddy ; ajouter la
garde aux adresses de confiance de Keycloak si nécessaire ; sauvegarder configuration et base ; remplacer le
refus 503 par la route qualifiée ; activer `resetPasswordAllowed` puis l'indicateur API/BFF ; conserver les
trois fermetures en cas d'échec. Restent également hors de ce lot : parcours iOS complet, reprise physique
Face ID, exécution CI distante, éventuelle limite distribuée.

## Sources primaires (Keycloak 26.7.4)

- [`LoginActionsService.java`](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/services/resources/LoginActionsService.java) :
  `GET`/`POST` `reset-credentials`, création de session d'authentification pour un `client_id` sans
  `redirect_uri`, `POST` avec `key` pour les jetons d'action.
- [`ResetCredentialEmail.java`](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/authentication/authenticators/resetcred/ResetCredentialEmail.java) :
  message uniforme `EMAIL_SENT` pour adresse connue, inconnue et panne SMTP ; **aucun compteur d'envoi**,
  donc `bruteForceProtected` ne protège pas les demandes de courrier.
- [Guide « Configuring a reverse proxy »](https://www.keycloak.org/server/reverseproxy) : `xforwarded`,
  `proxy-trusted-addresses` explicites, priorité de `X-Forwarded-Port`, obligation d'écraser les en-têtes,
  et nécessité de restreindre l'accès réseau à Keycloak.
- `infra/deploy/keycloak.conf` : `hostname=https://drivy.shulker.ch/identity`, `http-relative-path=/identity`,
  `proxy-headers=xforwarded`, `proxy-trusted-addresses=192.168.1.147`.

## Hygiène des artefacts

`artifacts/recovery-direct-guard-50/result.json` (ignoré par Git) ne contient que statut, version de Node,
digests d'images, ports loopback, compteurs et libellés de contrôles. Ni adresse, ni lien, ni jeton, ni
cookie, ni mot de passe, ni trace HTTP. Le contrôle de motifs est exécuté sur le contenu sérialisé **avant**
écriture.
