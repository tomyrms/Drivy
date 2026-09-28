# Rejoindre une école dans l’application

L’entrée **Compte → Rejoindre une école**, disponible sans école ni Person déjà liée, ouvre le parcours natif. L’écran d’un compte connecté non encore lié propose également **J’ai une invitation**. Il faut utiliser le compte OIDC correspondant à l’adresse destinataire vérifiée par le serveur.

## Parcours

1. Coller le lien complet reçu. Seuls l’origine HTTPS configurée, le chemin canonique `/app/invitation` (ou ce chemin sous le préfixe API configuré) et un fragment `token=` contenant les 43 caractères base64url canoniques sont admis. Le lien n’est jamais chargé comme une URL authentifiée : les requêtes restent dirigées vers l’API configurée.
2. `POST /v1/invitations/preview` vérifie le destinataire et affiche l’école, les rôles, l’adresse masquée, l’expiration et la notice exacte portée par l’invitation.
3. L’utilisateur prend explicitement connaissance de la notice et confirme les rôles affichés. La case est initialement vide. Un second aperçu doit être identique avant le premier envoi ; tout changement impose une nouvelle lecture.
4. `POST /v1/invitations/accept` emploie une opération UUID conservée durablement et `Idempotency-Key` identique. La réussite affichée exige le reçu AP72 `ACCEPT_INVITATION` / `Membership` correspondant, enregistré dans le Trousseau.
5. L’application relit `/me`. **Ouvrir mon école** recharge encore le contexte actuel, vérifie le même principal et sélectionne l’appartenance reçue. Une preuve historique ne donne pas accès à une appartenance supprimée ou suspendue depuis.

L’annulation de ce parcours conserve la session OIDC existante. Elle ne déconnecte jamais automatiquement l’utilisateur en cas de lien destiné à un autre compte. Les invitations expirées, révoquées et utilisées par une autre personne ont des messages distincts. Une invitation déjà acceptée par ce même compte est confirmée selon le contrat AP04, sans nouvelle personne ni nouvelle affectation.

## Intention globale et confidentialité

L’acceptation précède parfois l’existence d’une Person scolaire. Elle utilise donc un journal distinct de l’outbox scolaire, lié au serveur, à l’issuer et au subject OIDC. Les claims décodées localement servent **seulement au partitionnement du journal** ; elles ne prouvent ni identité, ni email, ni rôle. Chaque appel emploie le jeton frais de ce même principal, vérifié côté serveur.

Le journal est une entrée du Trousseau système chiffré, `AfterFirstUnlockThisDeviceOnly`, sans synchronisation iCloud. Le corps exact, le jeton d’invitation et la notice affichée sont conservés avant émission ; aucune copie en fichier, préférence, journal ou URL HTTP n’est créée. L’écriture est relue avant émission et avant chaque renvoi. Un reçu confirmé remplace le corps secret : le jeton est supprimé de l’entrée et la dernière preuve reste disponible après redémarrage.

Un résultat incertain reste conservé, même après 401, 403, 404, révocation ou expiration au retour. **Vérifier** recherche AP72 ; **Renvoyer** réutilise les mêmes octets et UUID. Seul un rejet métier explicite du tout premier envoi d’une nouvelle opération peut libérer celle-ci pour correction. Une réponse 201 suivie d’un échec de récupération du reçu reste incertaine. Aucun autre lien ne remplace une demande en attente.

## Livraison

Modules isolés `SchoolJoinAPI` et `SchoolJoinUI`, raccord limité à `SchoolRootView`. Aucun changement des identités, de la base serveur ou des modules de dossier et de capture. Le collage natif constitue l’entrée livrée. Le gestionnaire de liens valide aussi les URL transmises par iOS ; cette tranche ne configure pas les domaines associés ni la signature nécessaires à l’ouverture universelle depuis un email.

Revue statique des contrats et invariants effectuée. Aucun nouveau test de masse n’a été lancé. La compilation Apple de cette tranche doit être confirmée par la CI groupée ; aucune qualification sur appareil n’est revendiquée.
