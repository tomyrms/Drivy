# Contrôle HTTPS avec une identité sonde indépendante

Cette procédure contrôle le fournisseur déployé sans connecter le compte `luc`, sans changer son mot de passe temporaire et sans créer de données scolaires fictives. **Exécution HTTPS réussie le 24 septembre 2026**, puis nettoyage de la sonde confirmé. La [preuve datée sans credentials](proofs/oidc-https-2026-09-24.json) conserve les statuts observés.

## Résultat observé

Le navigateur Edge `153.0.4234.48` a effectué une vraie connexion Authorization Code + PKCE S256 contre l’issuer public. La sonde a été créée via l’administration loopback de CT114, sans email ni lien métier ; ses credentials sont restés dans des fichiers privés transférés par SSH. Aucun changement de mot de passe du compte principal ni aucune écriture dans la base métier n’ont été effectués.

| Contrôle HTTPS | Résultat |
|---|---|
| Discovery / échange du code | `200` / `200` |
| PKCE absent / méthode `plain` | Refusés par le fournisseur |
| Signatures, issuer, audiences, nonce et UUID sujet | Vérifiés |
| Access token vers `/refonte/v1/me` | `403 IDENTITY_NOT_LINKED` attendu |
| ID token utilisé comme autorisation API | `401` |
| Refresh token / accès avec le jeton renouvelé | `200` / `403 IDENTITY_NOT_LINKED` attendu |
| Rejeu de l’ancien refresh token | `400` |
| Nettoyage | Sessions révoquées ; compte supprimé et absence vérifiée (`404` admin) ; fichiers privés supprimés du conteneur, de Proxmox et du poste |

## Préparation par l’opérateur du serveur

Après validation de l’issuer `https://drivy.shulker.ch/identity/realms/drivy`, créer un compte sonde dans le realm `drivy` via l’administration locale Keycloak. Employer un identifiant inédit `probe-oidc-<suffixe-aléatoire>` (suffixe de 8 à 40 lettres minuscules, chiffres ou tirets), un mot de passe aléatoire d’au moins 32 caractères, `enabled=true`, `temporary=false` et aucune action obligatoire. Aucun prénom, nom ou email n’est nécessaire avec le profil minimal configuré par le bootstrap. Il s’agit du seul compte dont le mot de passe est préparé pour ce contrôle.

Ne pas réutiliser un compte préexistant inconnu. En cas de réponse de création incertaine, rapprocher son UUID et le journal opérateur avant de continuer. Ne jamais réinitialiser le mot de passe de `luc` pour faciliter le test. Ne créer ni `Person`, ni `IdentityLink`, ni membership, élève ou formation pour la sonde.

Conserver son identifiant, son mot de passe et son UUID fournisseur dans un fichier JSON privé `0600` contenant exactement les propriétés `username`, `password`, `subject`. Transférer ce fichier par le canal SSH autorisé vers `infra/dev/.state/deployed-probe.json` sur le poste de contrôle. Ce répertoire privé est créé et protégé par le [démarrage local](dev-identity.md). Ne pas afficher le fichier, le joindre à un artefact ou le committer.

## Exécution sur le poste

Avec Node24, les dépendances racine et `infra/dev` installées, puis Edge disponible :

```powershell
node scripts/dev/check-deployed-identity.mjs
```

Le script refuse tout identifiant ne commençant pas par `probe-oidc-`. Ses destinations sont fixées à `https://drivy.shulker.ch` ; il n’accepte pas de remplacement d’issuer, de domaine ou de compte dans la ligne de commande. Il utilise un navigateur isolé, sans trace, screenshot ni profil personnel. Il capture uniquement le callback Apple de l’opération, sans ouvrir un gestionnaire Windows.

Le contrôle valide discovery HTTPS, refus de PKCE absent ou `plain`, Authorization Code avec PKCE S256, `state`, `nonce`, signature, audience `drivy-api` et véritable `sub`. La requête `/refonte/v1/me` doit répondre `403 IDENTITY_NOT_LINKED` : le jeton fournisseur est reconnu, mais la sonde ne dispose d’aucun compte métier. Un ID token doit être refusé avec `401`. Le renouvellement, l’accès avec le jeton renouvelé puis le rejeu de l’ancien refresh token vérifient la rotation standard.

Le résultat daté sans credentials est écrit seulement après réussite dans `infra/dev/.state/deployed-check-result.json`. Le mot de passe de la sonde n’est jamais changé par ce script. Si Keycloak impose une action obligatoire, le contrôle s’arrête ; l’opérateur examine uniquement le compte sonde.

## Nettoyage et portée de la preuve

Après collecte du résultat, l’opérateur révoque les sessions puis désactive ou supprime uniquement l’UUID sonde qu’il a créé, et supprime son fichier de credentials privé. Ces mutations de nettoyage ne sont pas exécutées automatiquement par le contrôle navigateur.

Une réussite prouve l’intégration HTTPS/OIDC/API de la sonde, pas les droits du compte `luc`, son premier changement de mot de passe, ni le callback `ASWebAuthenticationSession` sur appareil. Le bootstrap du compte principal possède ses propres preuves de liaison et de reprise ; l’application iPhone conserve sa recette distincte.
