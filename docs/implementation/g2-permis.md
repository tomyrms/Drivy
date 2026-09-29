# G2 — contrôle humain du permis (AP29/AP30)

Tranche du 25 septembre 2026 (plan P0-3). Références : [R07](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/regles-etats.md#r07), F03 (`identites-formations.md`), matrice `roles-permissions.md`, schémas `PermitCommand`/`PermitCheck`/`PermitCheckPage` d’OpenAPI 3.11.0. Code : `apps/api/src/permits.ts`, migration `010_permit_checks.sql`.

## Règle appliquée

- Une décision est **humaine et explicite** : `APPROVED` exige `physicalSeen:true` (examen de l’original attesté) ; `REJECTED` exige un motif non blanc. Le serveur impose contrôleur (`reviewerMembershipId`) et date (`reviewedAt`) ; le client ne les fournit pas.
- **Catégorie réelle** : `categoryCode` doit être celle de l’offre de la formation (`422 CATEGORY_MISMATCH`). Aucune valeur d’une autre catégorie n’est reprise.
- **Aucune durée inventée** : `validUntil` est la date lue sur la pièce, ou `null` si aucune date n’est saisie. Le serveur ne calcule jamais d’échéance. `isExpired` est dérivé de `validUntil` et de la date locale de l’école ; ce n’est pas un statut stocké. Approuver une pièce déjà échue est refusé (`422 PERMIT_EXPIRED`).
- **Pièce déposée non disponible** : `documentId` non nul reçoit `409 DOCUMENT_NOT_READY` tant que le circuit F09 n’existe pas ; une contrainte SQL (`permit_document_not_ready`) garantit la même chose en base.
- **Historique append-only** : chaque décision est une ligne immuable ; la décision courante est la plus récente (`reviewed_at`, puis ordre d’insertion). Un rejet ultérieur remplace une approbation sans l’effacer.
- **Habilitation** : grant explicite `permit_review` **et** (ADMIN, ou INSTRUCTOR actuellement affecté à la formation). Sans grant : `403 PERMIT_REVIEW_REQUIRED` (code du dossier F03). Hors périmètre : 404. Lecture AP29 : ADMIN, élève sur sa formation, moniteur affecté habilité.
- **If-Match** vise la version de la **formation** (description AP30) ; la décision incrémente `training.version` dans le même commit. Deux décisions concurrentes sur la même version : une seule réussit, l’autre reçoit `412 VERSION_CONFLICT`.

## Effet sur les leçons et le constat

`permitWarning` n’est plus codé en dur. Chaque projection de leçon (AP39–AP44, AP49, AP50, publication) appelle `drivy.lesson_permit_warning(training, date locale de la leçon)` : l’avertissement vaut `false` seulement si la décision courante est `APPROVED`, de la catégorie actuelle de la formation, et non échue à la date du rendez-vous. Aucun contrôle, un rejet, une autre catégorie ou une date dépassée laissent `true`.

AP49 exige `anomalyReason` **uniquement** lorsque `permitWarning` est vrai ; sinon il reste facultatif (`completion_anomaly_reason` NULL si absent). Sans contrôle enregistré, le comportement antérieur est inchangé. On peut toujours planifier avec un contrôle en attente (R07). Une leçon réellement tenue reste enregistrable avec anomalie motivée ; l’application ne délivre aucune autorisation légale.

## Persistance et sécurité

Table `permit_check` sous RLS forcée (lecture `permit_read_allowed`, insertion `permit_review_allowed` + contrôleur = membre courant). Nouvelle politique UPDATE sur `training` limitée à la colonne `version` et aux contrôleurs habilités. Effet, incrément de version, preuve `operation` (`RECORD_PERMIT_CHECK`), audit `PermitReviewed` (motif tronqué à 1 000 caractères) : un seul commit. AP72 renvoie la preuve si le contrôle reste lisible.

## Écarts documentés

- Réponse AP30 : `200 PermitCheck` avec `ETag` = version du PermitCheck (toujours `"1"`, ressource immuable). Pour une décision suivante, relire la formation afin d’obtenir son nouvel ETag.
- AP29 trie par ordre d’enregistrement croissant (curseur opaque comme les autres listes) ; la dernière entrée est la décision courante.
- Aucun événement `lesson_event_outbox` : il est propre aux leçons et aucun consommateur n’existe. `PermitReviewed` est tracé dans l’audit.
- `PENDING` n’est jamais écrit : sans pièce déposée, l’absence de décision est l’état en attente.

## Tests

`apps/api/test/lesson-outcomes.integration.test.ts`, bloc « AP29/AP30 » (PostgreSQL réel, rôle `drivy_app`) : lecture par rôle, 403 sans grant, 428/412, catégorie, pièce non prête, schéma invalide, date échue, rejeu et `IDEMPOTENCY_MISMATCH`, incrément de version, AP72, validation OpenAPI `PermitCheckEnvelope`/`PermitCheckPageEnvelope`, bascule de `permitWarning`, constat sans anomalie, rejet ultérieur, date antérieure à la leçon, affectation retirée, pagination.

## Reste

Écran web admin et badge iOS (hors périmètre API). Contrôle par pièce déposée après F09 (la pièce remplacée devra repasser à PENDING et incrémenter la version de formation).
