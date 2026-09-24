# Recette locale de l’entrée par invitation

Le 24 septembre 2026 à 17:15 UTC, [check-entry.ts](../../scripts/dev/check-entry.ts) a terminé avec **18 contrôles réussis**, sortie `0` et nettoyage ciblé réussi, sur Windows, Edge `153.0.4234.48`, Keycloak `26.7.4`, Mailpit `1.31.2` et PostgreSQL `17.11`. Le navigateur utilise les vrais services : aucun jeton d’identité ni transport SMTP simulé.

Cette preuve couvre le chemin heureux décrit ci-dessous. Elle ne déclare ni F02 entier, ni les scénarios T/MOB, ni G1 ou le produit complet qualifiés.

## Reproduire

Préparer le [laboratoire d’identité local](dev-identity.md) et son extension `setup-web.ts` : comptes synthétiques existants, client confidentiel `drivy-web`, PKCE, scope `email` et serveur SMTP Mailpit. Les secrets restent dans les fichiers protégés `infra/dev/.state/runtime.json`, `accounts.json` et `web-runtime.json`. Aucun secret n’est requis dans la ligne de commande.

Les dépendances sont installées depuis les trois lockfiles (racine, `apps/web`, `infra/dev`). Node 24, Docker actif et Edge installé sont nécessaires. Pour un laboratoire déjà préparé :

```powershell
docker compose up -d --wait postgres
docker compose -f infra/dev/compose.yaml up -d
node --import tsx scripts/dev/setup-web.ts
npm run build --prefix apps/web
node node_modules/typescript/bin/tsc -p infra/dev/tsconfig.json
node --import tsx scripts/dev/check-entry.ts
```

Arrêter auparavant les aperçus API/web sur `3001` et `3002`. Ne pas exécuter deux instances de cette recette simultanément. Elle démarre puis ferme elle-même ses services et son profil navigateur éphémère. Aucun autre compte navigateur n’est utilisé. `DRIVY_BROWSER_CHANNEL=chrome` sélectionne Chrome installé ; la preuve ci-dessus concerne Edge.

| Service | Adresse locale utilisée |
|---|---|
| Base dédiée | `drivy_entry_test`, `127.0.0.1:55432` |
| API réelle | `http://127.0.0.1:3001` |
| Application/BFF | `http://127.0.0.1:3002/app` |
| Callback OIDC exact | `http://127.0.0.1:3002/app/bff/callback` |
| Issuer | `http://127.0.0.1:8081/realms/drivy-dev` |
| SMTP / consultation Mailpit | `127.0.0.1:1025` / `http://127.0.0.1:8025` |

Le script crée `drivy_entry_test` si elle est absente, applique les migrations puis réinitialise **uniquement** les tables de cette base jetable. Il vérifie le nom, l’hôte, le port, l’absence de paramètres URL et `current_database()` avant la réinitialisation. Il n’accepte aucune surcharge `DATABASE_URL`. `drivy_dev` sert uniquement à ouvrir la connexion qui crée éventuellement cette base ; ses tables ne sont ni migrées ni réinitialisées par `check-entry.ts`.

Les fixtures des deux écoles sont synthétiques. Les liens d’identité fictifs sont retirés de la base de recette ; seul le véritable sujet Keycloak de `demo-admin` est lié à sa Person fixture. Le compte invité est créé avec un identifiant unique, un mot de passe aléatoire et `emailVerified=false`, puis supprimé par son seul UUID en fin de parcours ou lors d’un échec géré.

## Preuves observées

| Étape réellement exécutée | Résultat vérifié |
|---|---|
| Bouton React puis formulaire Keycloak administrateur | Code PKCE S256, retour BFF, école Horizon réelle affichée. |
| Adoption de politique et création AP11 | Commandes API authentifiées, version/idempotence explicites, notice locale synthétique approuvée avant invitation. |
| Worker d’invitation et Mailpit | Livraison SMTP réelle ; lien avec jeton dans le fragment ; outbox `SENT` et charge chiffrée effacée après acceptation SMTP. |
| Première connexion du compte invité | Keycloak impose `VERIFY_EMAIL`. Le script ouvre le vrai lien reçu dans le courrier de vérification ; aucun réglage administratif ne marque l’adresse vérifiée. |
| Retour OIDC après vérification | Session BFF authentifiée avec adresse vérifiée ; `/me` reste `403` et aucun IdentityLink n’est créé par cette seule connexion. |
| Ouverture du vrai lien SMTP d’invitation | Fragment retiré de l’adresse ; aperçu de l’école, du rôle Élève et des textes de politique adoptés. |
| Lecture sans consentement de rattachement | Bouton désactivé avant la case de confirmation ; aucun IdentityLink créé par l’aperçu. |
| Case puis clic « Rejoindre cette école » | Acceptation via React/BFF/API, message de confirmation et école visible. |
| Relecture et SQL | Une école, rôle `LEARNER` seul ; **1 IdentityLink, 1 Membership, 1 LearnerProfile `MINIMAL`, 0 Training** pour cette nouvelle personne. |
| Rechargement | École retrouvée ; `localStorage` et `sessionStorage` vides. |
| Nettoyage | Utilisateur Keycloak éphémère supprimé et seulement les deux courriers identifiés de cette invocation supprimés. Aucun vidage global de Mailpit. |

L’adoption de la notice et AP11 passent par les vraies routes HTTP depuis le serveur de recette. Un observateur autour du retour OIDC garde l’access token administrateur uniquement en mémoire serveur pour ces deux commandes. Ce mécanisme n’ajoute pas d’écran d’administration web et ne retourne aucun jeton au navigateur.

Le résultat sans secret est écrit dans `infra/dev/.state/entry-check-result.json`, ignoré par Git et protégé comme le reste du laboratoire. Il porte `completed:true` seulement après la réussite du parcours et du nettoyage ; chaque nouvelle exécution commence par invalider l’ancienne preuve. La base dédiée reste disponible pour une inspection locale, avec ses seules données synthétiques. Aucune capture, trace réseau, adresse invitée ou jeton n’est journalisé.

Le nettoyage emploie la [route Mailpit de suppression sélective](https://mailpit.axllent.org/docs/api-v1/) avec une liste explicite non vide d’IDs. Un premier essai avait réussi les contrôles métier mais échoué sur la route de nettoyage du harness ; ses deux messages ont été supprimés de manière ciblée avant la nouvelle exécution complète indiquée en tête.

## Limites

Le compte invité est préparé par l’API administrative locale ; le formulaire public d’inscription n’est pas testé. Cette recette ne couvre pas les invitations expirées/révoquées, un changement de compte ou d’aperçu entre onglets, les pertes de réponse et reprises, l’archivage, les autres rôles, l’accessibilité assistée ni une restitution native. Les tests API/BFF correspondants restent des preuves distinctes.

L’environnement est HTTP sur loopback, avec des secrets de laboratoire et une connexion PostgreSQL d’opérateur local pour migrations/fixtures/inspection. Il ne qualifie pas le SMTP extérieur, HTTPS public, les permissions du compte PostgreSQL déployé ou le parcours iPhone. Les requêtes métier passent néanmoins dans l’API réelle, son contrôle JWT et son rôle applicatif SQL. Aucun serveur distant n’a été modifié pour cette recette.
