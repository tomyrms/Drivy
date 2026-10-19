# Connexion native et inscription réservée aux codes

Décision du porteur, 15 octobre 2026 : personne ne crée de compte sans y avoir été invité ; l’app et le web proposent la même entrée, « Se connecter » ou « J’ai un code », sans page de navigateur.

## Ce qui change

- **Inscription libre fermée** chez le fournisseur d’identité (`registrationAllowed: false`). Un compte ne se crée qu’avec un code ou un lien valable, par l’API.
- **Connexion par formulaire** dans l’app et sur le web. Le mot de passe va au point de jeton du realm (`grant_type=password`) : directement depuis l’app (client public `drivy-apple`), par le BFF côté web (client confidentiel `drivy-web`). Il n’est ni conservé ni journalisé, et l’API Drivy ne le voit qu’à la création du compte.
- **« J’ai un code »** lit le code sans connexion, puis propose de créer le compte (prénom, nom, e-mail, mot de passe) ou de se connecter à un compte existant. Le code n’est consommé qu’ensuite, connecté, par les routes habituelles :
  - code d’élève : rejoindre l’école (`/v1/invitations/code/accept`), avec l’écran existant de l’app ;
  - code d’ouverture : créer son école (`/v1/school-openings`), dans l’app (écran natif « Ouvrir ton école ») ou sur le web (formulaire existant) ;
  - lien d’invitation reçu par e-mail : le compte ne se crée qu’à l’adresse invitée, qui est alors tenue pour vérifiée.
- **Codes d’ouverture courts** : `XXXX-XXXX` (alphabet des codes d’invitation, 40 bits), avec un lien `…/app/ouvrir#token=XXXX-XXXX`. Leur empreinte est le HMAC à clé serveur des codes d’invitation ; les anciens jetons longs restent acceptés.

## Routes ajoutées

| Route | Contrat |
|---|---|
| `POST /v1/access-codes/preview` | Sans connexion. `{code}` : code court ou jeton long d’ouverture. Rend `kind` (`LEARNER_INVITATION` ou `SCHOOL_OPENING`), le nom de l’école pour un élève, l’échéance. Tout refus répond `404 ACCESS_CODE_INVALID`. |
| `POST /v1/accounts` | Sans connexion. `{code,firstName,lastName,email,password}`. Vérifie le code (ou le lien d’invitation avec l’adresse invitée), puis crée l’utilisateur Keycloak par le client de service `drivy-accounts` (rôle `manage-users`). `201 {kind,email}` ; `409 ACCOUNT_EXISTS`, `400 ACCOUNT_PASSWORD_REJECTED`, `503 ACCOUNT_CREATION_UNAVAILABLE` sans configuration. |
| BFF `POST /app/bff/password-login`, `/app/bff/access-code`, `/app/bff/accounts` | Mêmes règles d’entrée que la connexion (origine, CSRF anonyme, limite par adresse). Un code d’ouverture est gardé dans la session et survit à sa rotation. |

Freins par adresse (`TRUST_PROXY` = adresse de Caddy) : 10 codes refusés par quart d’heure, 30 créations de compte par heure (une classe sur le Wi-Fi de l’école partage une adresse). Le fournisseur garde sa protection contre la force brute par compte.

## Configuration

API : `ACCOUNT_ADMIN_URL` (fournisseur local, `http://127.0.0.1:8081/identity`), `ACCOUNT_ADMIN_REALM`, `ACCOUNT_ADMIN_CLIENT_ID`, `ACCOUNT_ADMIN_CLIENT_SECRET`, `TRUST_PROXY`. Realm : `infra/deploy/drivy-realm.json` et `drivy-web-client.json` (accès direct activé pour `drivy-apple` et `drivy-web`, client `drivy-accounts`).

## Limites connues

- La confirmation renforcée (étape sensible, `prompt=login`) passe encore par la page du fournisseur, dans l’app comme sur le web.
- Aucun « mot de passe oublié » : le realm n’a ni réinitialisation ni relais SMTP. Un oubli se règle par l’opérateur.
- Sur le web, un élève qui crée son compte avec son code est renvoyé vers l’app pour rejoindre son école (le web est le bureau).
- Les écrans iOS sont vérifiés par compilation et tests unitaires sur le runner Apple ; leur rendu n’a pas été vu sur un appareil.
