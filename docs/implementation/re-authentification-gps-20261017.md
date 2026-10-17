# Confirmation d’identité pour le réglage GPS — 17 octobre 2026

Le changement du module GPS exige une authentification récente vérifiée au serveur. Après la connexion par formulaire introduite le 15 octobre, cette preuve pouvait manquer alors que le mot de passe venait d’être accepté. La correction porte sur l’heure d’authentification émise par Keycloak et sur la confirmation d’identité dans le web Drivy.

Cette note remplace, **pour le parcours web de confirmation du réglage GPS**, la limite de [connexion-native-20261015.md](connexion-native-20261015.md) indiquant que la confirmation renforcée passe par la page du fournisseur. Elle ne décrit aucun changement du parcours de réauthentification natif Apple. La connexion initiale native utilise le même fournisseur corrigé, mais cela ne qualifie pas son interface de confirmation renforcée.

## Cause vérifiée

La connexion par formulaire utilise `grant_type=password`, directement depuis le client Apple ou par le BFF web. Dans Keycloak **26.7.4**, le traitement Direct Grant valide les identifiants, attache la session puis génère les jetons, sans enregistrer la note de session `AUTH_TIME`. Le flow navigateur enregistre cette note lors de sa finalisation. Le mapper OIDC standard ne produit le claim `auth_time` que si la note existe.

L’API Drivy refuse donc correctement une commande sensible avec `REAUTH_REQUIRED` lorsque ce claim est absent. Refaire le même Direct Grant sans corriger le fournisseur ne peut pas produire la preuve manquante.

`iat` indique l’émission d’un jeton et peut avancer à chaque renouvellement. Il ne prouve pas une nouvelle vérification des identifiants et ne remplace jamais `auth_time`. L’heure de réception du jeton par Drivy n’est pas utilisée non plus.

Sources primaires correspondant à la version exécutée :

- [ResourceOwnerPasswordCredentialsGrantType, Keycloak 26.7.4](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/protocol/oidc/grants/ResourceOwnerPasswordCredentialsGrantType.java#L106) : validation du flow Direct Grant, attachement de session et génération des jetons.
- [AuthenticationManager, Keycloak 26.7.4](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/services/managers/AuthenticationManager.java#L880) : enregistrement d’`AUTH_TIME` à la fin du flow navigateur.
- [UserSessionNoteMapper, Keycloak 26.7.4](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/protocol/oidc/mappers/UserSessionNoteMapper.java#L77) : absence du claim lorsque la note de session manque.
- [TokenManager, Keycloak 26.7.4](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/protocol/oidc/TokenManager.java#L431) : transfert des notes de l’authentication session vers la user session.

## Correction du fournisseur

Le fournisseur `drivy-direct-grant-auth-time` est une petite implémentation de l’Authenticator SPI de Keycloak, dans `infra/identity/direct-grant-auth-time/`. Il exige un utilisateur et la note `PASSWORD_VALIDATED=true` posée par le validateur de mot de passe. Sinon il refuse le flow sans écrire de note. Après validation, il enregistre `AUTH_TIME=Time.currentTime()` comme note destinée à la session utilisateur.

Le flow `drivy-direct-grant` conserve les contrôles standard de Keycloak 26.7.4 dans cet ordre :

1. Identifiant utilisateur : `REQUIRED`.
2. Mot de passe : `REQUIRED`.
3. OTP : sous-flow conditionnel lorsque l’utilisateur l’a configuré, avec les validateurs standard.
4. Fournisseur Drivy d’heure d’authentification : `REQUIRED`.

Le fichier `infra/identity/direct-grant-flow.json` sert à la création du realm isolé de recette. Un renouvellement de jeton ne rejoue pas ce flow : la preuve conserve son heure initiale. Une nouvelle validation du mot de passe ouvre une nouvelle session et produit une nouvelle heure. Le flow navigateur et son écriture d’`AUTH_TIME` restent inchangés.

La compilation utilise Java 21 et les JAR de la distribution Keycloak **26.7.4**, verrouillée par `infra/deploy/runtime-lock.json`. Il n’y a aucun téléchargement de dépendances Maven. Le script refuse des versions de bibliothèques Keycloak absentes ou mélangées, exécute les quatre tests Java, puis crée un JAR sans manifeste implicite et à date fixe :

```sh
node infra/identity/build-provider.mjs --distribution /chemin/keycloak-26.7.4 --output /chemin/drivy-direct-grant-auth-time.jar
```

La recette télécharge l’archive officielle et vérifie son SHA256 avant extraction et compilation :
`04823c336b797a7e18889a44262a7a64e6bf624cbbcc518c85e2622176ff2eee`.

Deux compilations locales successives ont produit le même JAR, de SHA256 :
`d7cb34188254e5a715857e38bb61d2730775c1c841806b10520dfc81d9e9dbce`.
Cette égalité est une mesure sur ces deux compilations locales, pas une affirmation de reproductibilité entre toutes les versions de compilateur.

## Confirmation dans le web Drivy

Le réglage GPS relit la session avant l’envoi. Si la preuve est trop ancienne ou absente, le web ouvre « Confirmer votre identité » dans Drivy. Le mot de passe reste en mémoire pour cette demande et n’entre ni dans un brouillon ni dans le journal des commandes. Un refus `REAUTH_REQUIRED` reçu de l’API entre cette lecture et la commande ouvre également cette confirmation.

`POST /app/bff/reauthenticate` reçoit `{email,password}` avec une session connectée, une origine attendue, un CSRF valide et une limitation des tentatives. Il vérifie le nouveau résultat OIDC avant de remplacer les jetons :

- Le `subject` doit être celui du compte déjà connecté.
- Le claim `auth_time` de l’ID token vérifié doit être une preuve récente. La limite par défaut est de 300 secondes, configurable entre 30 et 900 secondes ; la dérive future admise est de cinq secondes.
- Un mauvais mot de passe, un autre compte, une preuve manquante ou une indisponibilité du fournisseur conservent la session existante. Une confirmation concurrente est refusée.
- Une confirmation réussie conserve le même compte et les intentions de session, puis renouvelle le cookie et le CSRF.

`GET /app/bff/session` expose `reauthenticationRequired`, sans exposer l’horodatage d’authentification. Le BFF s’appuie sur les claims vérifiés par le client OIDC ; l’API vérifie séparément le jeton d’accès, les droits scolaires et la fraîcheur de la preuve.

Après confirmation d’identité, la revue du réglage GPS reste ouverte. Un nouveau clic « Activer » ou « Désactiver » est nécessaire. Confirmer son identité ne modifie aucun module et ne démarre aucun trajet. La commande conserve son contrôle de version, son identifiant d’opération et sa confirmation durable.

## Vérifications et état de qualification

| Vérification | Résultat au moment de cette note |
|---|---|
| Compilation contre la distribution Keycloak 26.7.4 dont le SHA est vérifié | Réussie avec le JDK 21 local |
| Gardes Java du fournisseur | **4 réussies** : mot de passe validé, note absente, note fausse, utilisateur absent |
| Keycloak local réel, distribution officielle et flow importé | **13 contrôles réussis**, sans Docker ; serveur local arrêté après la preuve |
| Jetons d’accès et d’identité locaux | Signatures, issuer et audience vérifiés ; même `auth_time` récent pour le même sujet |
| Renouvellement réel après passage à la seconde suivante | `auth_time` conservé, sans rajeunissement |
| Nouvelle validation du mot de passe | Nouvelle preuve plus récente |
| Mauvais mot de passe | `invalid_grant`, aucun jeton délivré |
| Typecheck `infra/dev`, syntaxe du script de build, contrôle du diff | Réussis |
| Tests web du lot, locaux et CI | **289 tests réussis dans 25 fichiers**, après protection des commandes et relecture de l’identité et des droits avant reprise de la revue ; [CI finale `d97dfa9`](https://github.com/tomyrms/Drivy/actions/runs/39042838403) |
| Recette intégrée navigateur → BFF → Keycloak → API → PostgreSQL avec ce fournisseur | **150 contrôles réussis** sur `d97dfa9` ([CI](https://github.com/tomyrms/Drivy/actions/runs/39042840471), [résultat](assets/parcours-comptes-20261017/browser-checks.json)), après les compléments de contexte et de focus |

La recette versionnée `scripts/dev/check-school-opening.ts` compile le fournisseur, monte son JAR en lecture seule dans l’image Keycloak verrouillée et importe le flow. Elle vérifie les claims signés, le renouvellement, la nouvelle connexion, les refus de confirmation BFF sans perte de session, la rotation du cookie/CSRF et l’activation GPS après un clic explicite, avec contrôle en base. [État GPS confirmé après écriture durable](assets/re-authentification-gps-20261017/gps-enabled-synthetic.png).

Trois parcours navigateur sur réponses synthétiques vérifient la preuve déjà fraîche, la confirmation avant envoi et le refus 401 entre la lecture et l’envoi. Annuler, saisir un mauvais mot de passe ou utiliser un autre compte conserve la revue ; une confirmation réussie n’émet aucun PUT automatique. L’inspection de la [capture du compte différent](assets/re-authentification-gps-20261017/different-account-synthetic.png) vérifie que l’erreur reste dans le formulaire. Les commandes et saisies d’une autre personne sont purgées avant réaffichage de l’école, et les réponses tardives ne peuvent pas les recréer ; une reconnexion du même compte conserve sa demande à vérifier. [Treize contrôles du fournisseur local](assets/re-authentification-gps-20261017/keycloak-local-checks.json).

Les jetons et identifiants de connexion synthétiques restent en mémoire pendant les assertions. Les artefacts n’enregistrent que les résultats de contrôle et les écrans métier autorisés. La preuve locale n’est pas une preuve de déploiement, de fonctionnement GPS physique ou de réauthentification native Apple. L’état de livraison et les résultats de CI sont suivis dans [STATUS.md](STATUS.md).

La revue finale a ajouté cinq essais dans le vrai `ManagementConsole` sur réponses synthétiques : code élève depuis la gestion vers l’invitation, code d’ouverture vers le formulaire école, connexion simple conservant la page de confidentialité, confirmation du même compte suivie d’un seul PUT explicite, et remplacement du compte par un autre onglet avec fermeture de l’ancienne revue et zéro PUT. Le formulaire attend désormais la relecture de `/me` et des accès scolaires ; une personne, une adhésion ou une époque d’accès différente interdit de reprendre l’ancienne intention.
