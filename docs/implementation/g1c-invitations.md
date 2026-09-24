# G1C — invitations et entrée dans une école

Cette tranche applique [F02](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/identites-formations.md#f02), [R02/R05/R11/R12](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md) et AP04/AP10–13 de l'[OpenAPI](../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml). Les six critères ci-dessous suivent la [définition READY](../../Drivy_Conception_v3_17_2026-09-20/05-realisation/roadmap-backlog.md#definition-ready). Le dossier canonique reste inchangé. Elle ne crée aucune formation et n'adopte aucune politique au nom d'un utilisateur.

## READY avant implémentation

1. **Action utilisateur.** Un ADMIN d'une école ACTIVE invite une adresse dans les rôles choisis. Un INSTRUCTOR invite uniquement LEARNER et gère ses propres invitations. Le destinataire ouvre un lien navigateur, se connecte auprès de l'IdP, lit école/rôles/notice et confirme explicitement.
2. **Source de vérité.** PostgreSQL décide des droits actuels, de l'état de l'invitation et de l'unicité école/personne. L'identité globale est `(issuer, subject)` ; un e-mail ne fusionne jamais deux personnes. Seul `email_verified: true` dans le JWT validé fournit l'adresse d'acceptation. Le jeton aléatoire n'est conservé dans l'invitation que sous SHA-256.
3. **Échec et concurrence.** Transaction unique effet/preuve/audit/outbox ; verrous identité, école, adhésions puis invitation ; If-Match pour renvoi/révocation ; operationId et Idempotency-Key identiques. Renvoi invalide immédiatement l'ancien jeton. Révocation ou perte des droits de l'émetteur empêche l'acceptation. Un réessai exact restitue la preuve ; une clé réutilisée avec un autre contenu échoue.
4. **Persistance minimale.** Invitation, outbox e-mail chiffrée AES-256-GCM, personne/lien OIDC/adhésion et profil élève minimal à l'acceptation. Le contenu du mail est effacé après acceptation SMTP, révocation, remplacement ou expiration. Les révisions de notice existantes et l'audit transactionnel sont réutilisés. Aucune formation, affectation, position GPS ou mot de passe applicatif.
5. **Contrat et UI.** DTO canoniques Invitation et MemberContext. Extension authentifiée `POST /v1/invitations/preview {token}` : école, rôles, expiration et notice avant acceptation, sans écriture. Le lien `/app/invitation#token=…` garde le secret hors URL HTTP. États vide/chargement/erreur/confirmation et commandes incertaines conservées par les clients.
6. **Preuve attendue.** PostgreSQL réel : T005–T008, isolation école/auteur, e-mail non vérifié/différent, concurrence création/acceptation, droits retirés sous verrou, If-Match, replay, rollback, aucun profil/formation anticipé, migration propriétaire sans SUPERUSER/BYPASSRLS/CREATEROLE. SMTP réel local Mailpit : contenu contrôlé, envoi, purge du secret et annulation des anciens liens. Aucun envoi externe dans la recette.

## Contrat livré

AP10 accepte seulement `limit` (1–100, défaut 50) et `cursor`. ADMIN lit toutes les invitations de son école ; INSTRUCTOR seulement les siennes pour LEARNER. AP11 répond 201 ; AP12/AP13 répondent 200. Renvoi et révocation sont autorisés pour PENDING ou EXPIRED. Aucun jeton ni adresse complète n'est retourné aux listes scolaires.

AP72 utilise `CREATE_INVITATION`, `RESEND_INVITATION`, `REVOKE_INVITATION`, ressource `Invitation`. Les preuves restent limitées à leur auteur et à ses droits actuels. `ACCEPT_INVITATION` porte la ressource `Membership`. Après perte de session, réouvrir un jeton déjà accepté par la même personne permet de confirmer son contexte actuel, sans deuxième adhésion ni deuxième événement InvitationAccepted ; un autre compte est refusé.

Le [schéma du preview](../../apps/api/contracts/g1c-invitation-preview.json) est séparé du canon. La notice est la révision adoptée portée par l'invitation ; un renvoi prend la dernière révision adoptée. Son affichage n'est pas enregistré comme consentement juridique ou choix GPS. Les rôles ADMIN existants, grants actifs et liens OIDC sont conservés lorsqu'une invitation complète une appartenance existante ; une appartenance révoquée ne récupère que les rôles nouvellement proposés, sans anciens grants. L'adresse vérifiée persistée à l'acceptation permet de détecter ALREADY_MEMBER ; les contacts administratifs non vérifiés ne sont pas utilisés pour fusionner des personnes.

Un nouveau compte OIDC doit être inscrit et son adresse vérifiée auprès de l'IdP avant acceptation. L'API ne crée pas de compte fournisseur et ne transforme jamais une adresse déclarée en adresse vérifiée. Le profil élève reste MINIMAL et l'étape PROFILE reste à compléter ; les noms légaux ne sont pas déduits du nom d'affichage. L'état ACCEPTED est visible pour l'émetteur et l'ADMIN dans AP10 et l'événement est audité ; le centre de notifications F11 et le reste de F21 restent des verticales distinctes.

Erreurs métier : `INVITATION_ALREADY_PENDING`, `ALREADY_MEMBER`, `INVITATION_ROLE_FORBIDDEN`, `INVITATION_USED`, `INVITATION_REVOKED`, `INVITATION_EXPIRED`, `INVITATION_IDENTITY_MISMATCH`, `SCHOOL_NOT_ACTIVE`, `VERSION_CONFLICT`, `INVALID_REQUEST`, `PRECONDITION_REQUIRED`. `IDEMPOTENCY_MISMATCH` reste non résolu côté client. Un 4xx après une demande incertaine n'autorise jamais son oubli. L'absence de transport configuré répond `503 INVITATION_DELIVERY_UNAVAILABLE`.

## Transport et exploitation

API : `INVITATION_WEB_URL`, `INVITATION_OUTBOX_KEY` (64 caractères hexadécimaux), `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_FROM`, éventuellement `SMTP_USER`/`SMTP_PASSWORD`. HTTPS est obligatoire pour le lien hors loopback de développement. SMTP exige TLS avec vérification du certificat en production ; le loopback Mailpit de recette utilise le port 1025.

Le worker séparé utilise `MAIL_DATABASE_URL`, sous un rôle dédié membre de `drivy_invitation_mailer`, sans SUPERUSER ni BYPASSRLS. Aucun accès HTTP utilisateur ne déclenche implicitement un worker. L'installation doit créer ce rôle NOLOGIN et accorder au propriétaire de migration ADMIN OPTION avant la migration 003 lorsque ce propriétaire n'a pas CREATEROLE. Le login worker doit être distinct du login API. [prepare-invitation-mailer.sql](../../apps/api/scripts/prepare-invitation-mailer.sql) prépare les rôles sans mot de passe ; génération du secret côté serveur et HBA/TLS restent des opérations explicites d'installation. Démarrage après build : `npm run mail:worker --workspace @drivy/api`.

Un commit API signifie « invitation enregistrée », pas « message reçu ». SENT signifie acceptation SMTP, pas livraison finale ni lecture. SMTP ne fournit pas d'idempotence fiable : un crash entre son acceptation et l'enregistrement peut produire un doublon ; le Message-ID est stable et le lien n'autorise toujours qu'une acceptation. Les droits et la validité sont revérifiés avant envoi. Un message déjà parti ne peut être rappelé ; révoquer ou renvoyer rend son ancien lien inutilisable.

Références primaires transport : [Nodemailer SMTP](https://nodemailer.com/smtp), [sécurité des messages](https://nodemailer.com/message).

## Qualification

Le 24 septembre 2026, **89 tests sur 89 passent sur PostgreSQL 16.14 et 17.11** : 34 G1A, 23 G1B, 32 G1C. `npm run typecheck --workspace @drivy/api` et `npm run build --workspace @drivy/api` réussissent. La suite G1B applique 003 sous un propriétaire sans SUPERUSER, BYPASSRLS ni CREATEROLE et vérifie les quinze tables FORCE RLS.

Les preuves G1C comprennent les réponses Invitation/MemberContext/AP72 validées contre OpenAPI, le schéma de preview séparé, l'absence d'effet du preview, les refus d'e-mails non vérifiés/différents, la concurrence entre émetteurs ou entre deux subjects partageant une adresse, le replay sans doublon, la préservation du dernier ADMIN/lien/grants, la révocation pendant attente, et la rotation du secret pendant attente pour destinataire neuf **et** ADMIN. Une panne d'audit réelle annule identité, adhésion, profil, consommation et preuve.

Mailpit reçoit réellement le message SMTP ; le test vérifie le lien fragment et la purge du payload après SENT. Les tests vérifient aussi claim concurrent de deux workers, erreur SMTP sans faux succès, annulation après révocation/expiration, corruption du ciphertext et impossibilité pour le worker de muter les adhésions. Les tokens et coordonnées synthétiques ne sont pas journalisés dans les résultats.

Ce résultat ne constitue pas une preuve de livraison externe, d'inscription navigateur complète, de parcours iOS ou de déploiement. Les fichiers G1C sont gelés pour la recette intégrée locale ; aucune mutation distante ni aucun envoi externe n'a été exécuté pour cette tranche.
