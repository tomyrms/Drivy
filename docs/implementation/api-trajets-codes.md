# Trajets de l’école, invitation par code et ancrage serveur

Décisions du porteur du 28 septembre 2026 ([décisions](decisions-2026-09-28.md)). Le contrat OpenAPI canonique 3.11.0 n’est pas modifié : tout ce qui suit est une extension. Migrations **014** et **015**.

## Trajets visibles par l’administration (migration 014)

| Règle | Détail |
|---|---|
| Lecture | Un membre ADMIN actif lit **toutes** les captures de son école, tous moniteurs et tous élèves, quel que soit l’état de la leçon ou du partage. `drivy.capture_private_access` (008) reçoit une seconde branche `is_current_school_admin`. |
| Moniteur | Inchangé : les trajets des formations auxquelles il est affecté (affectation courante). |
| Élève | Inchangé (012) : ses trajets finalisés d’une leçon réalisée, sauf `capture_hidden`. |
| Écriture | Aucune pour l’administration : `capture_insert`, `capture_update` et `chunk_insert` n’appellent pas cette fonction ; arrêt, finalisation et lots répondent 404. |
| Lots et replay | Suivent la session par leur politique existante (`chunk_read`) : un trajet lisible donne accès à ses mesures. Aucun contrôle « auteur » dans `captures.ts` ne bloquait la lecture. |
| Observations | Politiques inchangées (007, 009, 012) : auteur courant seulement, ou élève pour les observations non privées d’une leçon réalisée. Un administrateur relit donc le trajet **sans** ses observations (`observations: []` dans le replay, 404 sur la liste des observations de la leçon). Décision explicite : le trajet est une donnée d’exploitation, l’observation est une note pédagogique. |

### `GET /v1/schools/{schoolId}/captures?limit=1..100&cursor=…`

Enveloppe standard `{data:{items,nextCursor},requestId,serverTime}`. `limit` vaut 50 par défaut. Tri `authorizedAt` décroissant puis `id` décroissant ; les captures `publicationState = DELETED` sont exclues ; la RLS décide seule des lignes (moniteur, administrateur, élève, autre école : rien). Curseur opaque lié au compte, à l’école et à l’époque d’accès (`INVALID_CURSOR` 400 sinon). Aucun rôle particulier : 403 hors école, sinon les lignes lisibles.

Chaque élément est la projection de `GET /captures/{captureId}` (`id, schoolId, version, lessonId, learnerId, instructorMembershipId, deviceId, choiceId, authorizedAt, expiresAt, stoppedAt, cutoffAt, uploadDeadline, captureState, syncState, publicationState, deviceAssessmentId`) plus :

| Champ | Type |
|---|---|
| `learnerName` | string |
| `instructorName` | string |
| `lessonPlannedStart` | instant ISO 8601 UTC |
| `lessonTimeZone` | string (fuseau IANA de la leçon) |

Les noms viennent de `drivy.capture_trip_names(capture)` : un élève ne lit pas la fiche personne de son moniteur (politiques de `drivy.person`), et la fonction ne rend les deux noms que pour un trajet que l’appelant peut déjà lire.

## Invitation par code à usage unique (migration 015)

Aucun relais SMTP : le moniteur transmet un code (SMS, WhatsApp) que l’élève saisit dans l’app.

Schéma : `invitation.email` devient nullable ; `delivery` (`EMAIL` par défaut, ou `CODE`) ; contrainte `invitation_delivery_shape` : EMAIL ⇒ adresse ; CODE ⇒ pas d’adresse, rôle `LEARNER` seul, formation et moniteur (colonnes de 013). Le code n’est jamais stocké : `token_hash` porte son **HMAC-SHA256** à clé serveur, calculé sur le code **normalisé** (majuscules, sans espaces ni tirets) ; aperçu, acceptation, création et renvoi utilisent la même empreinte. Un code de 40 bits se devine hors ligne en quelques minutes sur un GPU à partir d’un simple SHA-256 : avec la clé, une base copiée ou une sauvegarde ne le permet plus. La clé se dérive par HKDF-SHA256 (étiquette `drivy/invitation-code/v1`) de `INVITATION_CODE_SECRET` s’il est défini (au moins 32 caractères, facultatif, prioritaire), sinon de `CURSOR_SECRET` : aucune configuration nouvelle n’est requise. Changer l’un de ces secrets invalide les codes en attente ; « Nouveau code » en génère un valide. Les jetons des liens e-mail (256 bits aléatoires) gardent leur SHA-256. 8 caractères de `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, tirés par `crypto.randomBytes` (256 est multiple de 32 : sans biais), affichés `XXXX-XXXX`, valables 7 jours, usage unique.

`drivy.invitation_target()` et les deux politiques de `drivy.invitation` qui lisaient jeton + adresse vérifiée acceptent aussi un code (`app.invitation_code_hash`, jamais mêlé à `app.invitation_hash`) : toutes les politiques de 003 (personne, identité, adhésion, dossier élève, opération) couvrent donc les deux flux.

### Création — `POST /v1/schools/{schoolId}/invitations`

Corps : `{operationId, delivery?: "EMAIL"|"CODE", email?, roles, training?}`. `delivery` vaut `EMAIL` par défaut : les clients existants ne changent pas. Pour `CODE` : pas d’`email`, `roles: ["LEARNER"]`, `training: {offeringId, instructorMembershipId}` obligatoire ; mêmes règles que 013 (le moniteur ne nomme que lui-même, l’administrateur tout moniteur actif, offre prête, `INVITATION_TRAINING_INVALID` sinon). Une forme incohérente répond 400 `INVALID_REQUEST`. Aucun e-mail n’est mis en file : la création réussit sans SMTP.

Réponse 201 `InvitationEnvelope` étendu : `{id, schoolId, version, maskedEmail, roles, status, expiresAt, delivery, code?}`. `maskedEmail` est `null` pour un code. `code` (`XXXX-XXXX`) figure **seulement** dans la réponse qui l’a généré (création, renvoi) ; il n’entre ni dans l’opération stockée ni dans une liste. Un rejeu idempotent rend l’invitation **sans** `code` (l’app propose « Nouveau code »). Le schéma canonique `Invitation` est fermé : les tests valident ces réponses contre `contracts/invitation-delivery.json`.

### Renvoi et révocation

`POST …/invitations/{id}/resend` sur un code génère un nouveau code (l’ancien cesse de correspondre aussitôt), prolonge de 7 jours et le rend dans `code`. `POST …/revoke` inchangé. Toutes les projections d’invitation (liste, renvoi, révocation) portent `delivery`.

### Aperçu — `POST /v1/invitations/code/preview`

Corps `{code}` ; connexion requise (toute identité, même sans compte Drivy ni adresse vérifiée). Réponse `{data:{schoolName, roles, trainingCategoryCode: string|null, expiresAt}}`. Toute autre issue : **404 `INVITATION_CODE_INVALID`**, identique pour code inconnu, expiré, utilisé, révoqué, émetteur sans droit ou école inactive.

### Acceptation — `POST /v1/invitations/code/accept`

Corps `{operationId, code}`, `Idempotency-Key = operationId`. Même transaction que l’acceptation par jeton (verrous, personne et lien OIDC, adhésion, dossier élève, formation et affectation, preuve AP72 `ACCEPT_INVITATION`), **sans adresse vérifiée** : `membership.invitation_email` et `learner_profile.contact_email` ne reçoivent l’adresse que si le fournisseur l’a vérifiée, sinon `null`. Réponse 201 : le contexte de membre canonique (`MemberContextEnvelope`). Un code déjà utilisé, révoqué, expiré ou inconnu répond 404 `INVITATION_CODE_INVALID`.

### Frein

Limiteur en mémoire par identité OIDC (émetteur + sujet), commun à l’aperçu et à l’acceptation : 10 codes refusés (`INVITATION_CODE_INVALID`) sur 15 minutes glissantes, puis **429 `INVITATION_CODE_ATTEMPTS`**, même avec un bon code, jusqu’à la sortie de la fenêtre. Un seul processus API : le compteur ne survit pas à un redémarrage ni ne se partage entre instances.

## Refus définitif sans transport e-mail

Sans configuration SMTP, créer ou renvoyer une invitation **par e-mail** répond **409 `INVITATION_DELIVERY_UNAVAILABLE`** (et non plus 503) : un 5xx est une incertitude pour les clients, qui verrouillent alors les autres écritures de l’école. Le refus survient avant tout effet, n’est pas conservé et n’est pas rejoué. Les codes ne sont pas concernés.

`GET /v1/schools/{schoolId}/invitation-options` (ADMIN ou INSTRUCTOR, sinon 403) : `{data:{emailInvitationsAvailable: boolean, codeInvitationsAvailable: true}}`, pour masquer l’invitation par e-mail quand aucun transport n’est configuré.

## Formation d’une invitation acceptée

L’offre d’une invitation a pu être republiée depuis son envoi. À l’acceptation (jeton ou code), la formation s’ouvre sur la **dernière version prête** de la même `offering_key` (`drivy.invitation_ready_offering`, qui s’appuie sur `catalogue_offering_ready`) ; la politique d’insertion de formation (013) accepte toute version de l’offre invitée. Si aucune version n’est prête, l’adhésion est acceptée et la réponse porte **`trainingOpened: false`** (champ absent dans le cas normal) ; l’audit `InvitationAccepted` ajoute `trainingNotOpened` aux champs modifiés ; un rejeu de la même opération rend la même annonce. Un élève qui suit déjà l’offre n’est pas signalé.

## Ancrage serveur des observations (F3)

Une observation prise pendant un trajet n’avait pas de position : l’app n’envoie une ancre que si elle en a une, et le serveur n’en accepte qu’après l’acquittement du lot. À la **finalisation** de la capture, et pour toute observation **tardive** créée après elle, le serveur place chaque observation non retirée et non ancrée de la leçon dont l’instant `observedAt` tombe dans la capture (de `authorizedAt` à la borne de collecte) sur la mesure la plus récente qui ne la suit pas, à 60 secondes au plus (`segmentId` + `pointSequence`). « Ne la suit pas » est la règle de `validateAnchor` : une réécriture par l’app avec l’ancre posée par le serveur reste valide. Sans mesure assez proche, l’observation reste sans position. Un lot illisible n’ancre rien et n’échoue pas la finalisation. L’observation placée gagne une version, le brouillon lié aussi ; l’audit de finalisation ajoute `observationAnchors`. La finalisation prend désormais le verrou de la leçon avant celui de la capture, comme les observations.

## Preuves

CI « Refonte · vérifications » (PostgreSQL 17 réel) : `capture-trips.integration.test.ts`, `capture-anchoring.integration.test.ts`, `g1c.integration.test.ts` (blocs « Invitation par code » et « offre republiée ») ; tests sans base : `invitation-code.test.ts`, `capture-anchoring.test.ts`.

## Déploiement

Migrations **014** (remplace `capture_private_access`, ajoute `capture_trip_names`) et **015** (`email` nullable, colonne `delivery` avec défaut `EMAIL`, contrainte de forme, remplacement de `invitation_target()` et `invitation_training_allowed()`, ajout de `invitation_code_category()` et `invitation_ready_offering()`, deux `ALTER POLICY`). Aucune réécriture de table : l’ajout de colonne avec défaut constant et `DROP NOT NULL` sont instantanés ; les invitations existantes valent `EMAIL` et satisfont la contrainte. Aucune nouvelle table. Sauvegarde de la base avant, comme toute mise en production.
