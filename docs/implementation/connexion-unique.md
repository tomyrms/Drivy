# Connexion unique sur l’appareil

Décision du porteur du 28 septembre 2026 : on se connecte une fois par appareil, puis l’app s’ouvre directement. Pas de formulaire natif de mot de passe : la saisie reste sur la page du fournisseur d’identité, aux couleurs de Drivy.

## Ce qui change

| Avant | Maintenant |
|---|---|
| Page Keycloak standard, « Identifiant » seulement | Thème `drivy`, e-mail ou identifiant |
| Session de 30 minutes d’inactivité, 2 heures au plus : nouvelle connexion plusieurs fois par jour | Session hors ligne de 30 jours d’inactivité, 180 jours au plus |
| Aucun verrou local | Face ID, Touch ID ou code de l’appareil après 5 minutes en arrière-plan, proposé après la première connexion |

## Serveur d’identité (appliqué le 28 septembre 2026 sur CT114)

- Realm `drivy` : `loginTheme=drivy`, `loginWithEmailAllowed=true`, `displayNameHtml` en logotype, `offlineSessionIdleTimeout=2592000`, `offlineSessionMaxLifespanEnabled=true`, `offlineSessionMaxLifespan=15552000`. La session navigateur (web de gestion) reste à 30 minutes / 2 heures.
- Client `drivy-apple` : scope optionnel `offline_access`. `directAccessGrantsEnabled` reste `false`.
- État précédent sauvegardé dans `/root/drivy-realm.before-20260928.json` (CT114, root 0600).
- Thème : `infra/identity/themes/drivy`, copié dans `runtime/keycloak/themes/drivy`, puis redémarrage de `drivy-refonte-identity` (environ 10 secondes). Il hérite de `keycloak.v2` et n’ajoute qu’une feuille de style et des libellés ; aucun gabarit n’est remplacé.
- Cloudflare garde `/identity/resources/*` en cache 30 jours sous le même chemin : chaque modification du CSS change son nom (`drivy-N.css`).

Contrôlé en HTTPS public : la page d’autorisation avec `offline_access` répond 200, charge `drivy-2.css`, affiche « Connexion », « E-mail ou identifiant », « Mot de passe », « Se connecter », en clair et en sombre à largeur de téléphone. Aucun identifiant n’a été saisi.

## App iOS

- `OIDCPolicy.scopes` ajoute `offline_access` (connexion et réauthentification).
- `AppLock` : verrouille au lancement si le réglage est actif, puis après 5 minutes en arrière-plan ; le déverrouillage utilise `deviceOwnerAuthentication` (biométrie ou code). Le verrou masque l’interface sans toucher au Trousseau ni à une collecte GPS en cours.
- Réglage « Ouvrir avec Face ID » dans le compte ; proposition unique après la première connexion.

## Reste à qualifier

- Première connexion et réouverture sur l’iPhone du porteur avec le prochain IPA.
- « Mot de passe oublié » : exige un relais e-mail, pas encore raccordé (`resetPasswordAllowed=false`).
- Les sessions déjà ouvertes avant cette version n’ont pas de jeton hors ligne : elles expirent encore au bout de 2 heures, puis la prochaine connexion donne la session longue.
