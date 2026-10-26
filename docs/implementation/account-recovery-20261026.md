# Récupération du compte — intégration préparée

Le 26 octobre 2026, le porteur choisit de préparer #50 et de sélectionner le relais SMTP ultérieurement. Aucun compte réel n'est réinitialisé, aucun envoi externe ni déploiement n'est effectué. **La fonctionnalité reste désactivée par défaut et l'issue reste ouverte.**

## Contrat et parcours

GET `/v1/account-recovery/options`, anonyme, sans query ni corps, renvoie `{data:{available:false,recoveryUrl:null},serverTime,requestId}`. Si la configuration autorise la récupération, `available` vaut true et `recoveryUrl` est l'origine publique contrôlée suivie exactement de `/app/recover`. Aucun email, sujet OIDC, jeton ou droit scolaire ne passe par cet endpoint. Il ne consulte ni la base ni un compte d'identité. Les réponses sont non mises en cache.

La configuration API utilise `ACCOUNT_RECOVERY_ENABLED=false` par défaut. Une activation explicite exige `PUBLIC_ORIGIN` (origine HTTPS seule, sans identifiant, chemin, query ou fragment ; HTTP loopback uniquement hors production). Le BFF utilise le même indicateur et son `WEB_ORIGIN` existant. Le contrat natif accepte uniquement la même origine que l'API publique. Sur la cible actuelle, API et portail sont sous la même origine ; ne pas activer avec une origine différente.

Le web ouvre une page de récupération séparée, vide le champ mot de passe et conserve la page de connexion ou d'invitation. Le portail vérifie sa disponibilité, puis un POST protégé par origine/CSRF et limitation d'entrée construit l'URL Keycloak depuis l'issuer configuré : `/login-actions/reset-credentials?client_id=…&ui_locales=fr`. Cette entrée autonome n'utilise pas de redirect_uri et ne connecte pas la personne dans Drivy. Le retour à la connexion est manuel. Aucun résultat d'ouverture ou de retour du navigateur n'est interprété comme un mail envoyé ou un mot de passe changé.

Le fournisseur conserve la responsabilité du lien signé, de son expiration et de son usage unique. Le thème Drivy donne la même réponse conditionnelle pour adresse connue, inconnue et panne SMTP. Si le canal n'est pas encore opérationnel, Drivy annonce que l'envoi n'est pas disponible. Si le fournisseur devient indisponible après l'ouverture, le navigateur affiche l'échec et la personne peut revenir à la connexion ; Drivy ne fabrique pas de confirmation.

## Sessions et données

Le parcours conserve l'identité OIDC ; il ne crée ni personne, ni rattachement, ni permission. La récupération d'accès ne récupère pas automatiquement les clés de messagerie ni l'historique chiffré.

La politique retenue est le choix explicite Keycloak « Se déconnecter des autres appareils ». Quand coché, les autres sessions et leurs jetons de renouvellement sont révoqués. Sinon, le changement n'est pas présenté comme une révocation générale. Les jetons d'accès déjà émis peuvent demeurer valides jusqu'à leur expiration (cinq minutes dans le realm de référence). Face ID reste un verrou local : il ne réinitialise pas le mot de passe et ne rétablit pas un refresh token révoqué. Le client reprend sa procédure habituelle de reconnexion à l'expiration/refus.

## Garde avant toute activation

Trois fermetures existent dans les références : indicateur API/BFF désactivé, `resetPasswordAllowed:false` du realm, refus 503 du chemin direct reset-credentials dans Caddy. Le refus couvre GET et POST et intervient avant le proxy d'identité ; aucune modification de la configuration en fonctionnement n'a été faite. L'indicateur ne constitue pas une détection de santé SMTP.

Le BFF limite les entrées anonymes à trente par adresse (préfixe /64 en IPv6) sur dix minutes. **Ce compteur ne protège pas les appels directs à Keycloak.** Le code officiel de ResetCredentialEmail n'applique pas de compteur d'envoi ; `bruteForceProtected` ne doit pas être considéré comme une protection contre les demandes de courrier.

Avant activation, installer et qualifier une limitation sur la frontière qui dessert directement `/identity/realms/drivy/login-actions/reset-credentials`, pour GET et POST, y compris lorsqu'on appelle cette URL sans passer par Drivy. La source d'adresse doit venir exclusivement du proxy de confiance ; un en-tête client ne doit pas changer la clé. Conserver le refus 503 tant que cette garde n'est pas disponible. Le choix du composant de limitation accompagne celui du service d'envoi ; il n'est pas imposé par cette préparation.

Procédure opératoire : sauvegarder la configuration et la base conformément au mandat ; configurer le SMTP privé du realm et le thème Drivy ; qualifier la limitation directe (seuil atteint → refus 429 sans courrier supplémentaire, autre adresse indépendante, fenêtre expirée → reprise) et le relais sur données synthétiques ; vérifier expiration, rejeu, panne et révocation ; activer resetPasswordAllowed puis l'indicateur API/BFF et remplacer le refus Caddy par la garde qualifiée. En cas d'échec, conserver/rétablir le refus Caddy et les deux désactivations. Aucun secret SMTP ne doit entrer dans Git ou les artefacts.

## Vérification

Exécuté localement avec Node 24 : huit tests API ciblés et 42 tests web (trois récupération et 39 BFF), types API/web, build web, contrôle de types du helper de recette. Ils vérifient l'absence d'énumération au niveau de l'endpoint options, les URL fixes, les valeurs par défaut, les refus CSRF, les corps/query interdits et le refus 429 du BFF suivi de la reprise après fenêtre. Ils ne prouvent pas un envoi SMTP.

La recette UI `scripts/dev/check-account-recovery.mjs` passe quatre cas Edge clair/sombre, disponibilité activée ou non, avec BFF synthétique : absence de service, panne à l'ouverture, panne de lecture et reprise, aucune erreur JavaScript ni débordement horizontal. Captures relues dans `proofs/account-recovery-20261026/`. Aucun fournisseur d'identité ni courrier n'est sollicité par cette recette UI.

La recette réelle existante est étendue dans `scripts/dev/check-school-opening.ts` avec `check-school-account-recovery.ts` : realm Keycloak 26.7.4 éphémère, thème Drivy, Mailpit local, identité synthétique créée puis supprimée, comparaison connu/inconnu, courrier réel, changement de mot de passe, ancien mot de passe refusé, refresh révoqué si choisi, lien consommé et expiré, SMTP en panne, absence de session BFF créée. Aucun lien, token, mot de passe ou journal réseau n'est sauvegardé. **Cette extension n'a pas encore été exécutée localement : Docker est indisponible.** Son résultat doit être obtenu dans la CI intégrée avant de qualifier le parcours. Les trois rôles, la conservation des rattachements après une récupération et la reprise physique Face ID restent à qualifier avant clôture #50.

Sources primaires lues pour Keycloak 26.7.4 : [entrée autonome et fin après actions](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/services/resources/LoginActionsService.java), [réponse uniforme et envoi de récupération](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/authentication/authenticators/resetcred/ResetCredentialEmail.java), [option de révocation des autres sessions](https://github.com/keycloak/keycloak/blob/26.7.4/services/src/main/java/org/keycloak/authentication/requiredactions/UpdatePassword.java). Le dossier de conception livré et son manifeste restent inchangés ; le présent document spécifie l'extension au contrat canonique.
