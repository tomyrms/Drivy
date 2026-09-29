# G2 — issues réelles d’une leçon : absence, correction, retrait du bilan

Tranche du 25 septembre 2026 (plan P0-4). Références : R14, R16, R18–R20, R23/R24, F07 « Matrice détaillée de correction », `api.md` (CorrectOutcome, « Arbitrage encadré »), `modele-donnees.md` (OutcomeApproval), schémas `ReasonCommand`, `CorrectOutcomeCommand`, `ApproveOutcomeCommand`, `OutcomeApproval`, `Lesson`, `Ack`. Code : `apps/api/src/lesson-outcomes.ts` ; migration `011_lesson_outcomes.sql`.

Toutes les routes sont sous `/v1/schools/{schoolId}/lessons/{lessonId}`, exigent `operationId` = `Idempotency-Key` et `If-Match` de la **leçon**. Effet, preuve (`operation`), audit, événement `lesson_event_outbox` et preuves métier sont dans le même commit ; aucun appel réseau sous verrou ; ordre de verrous partagé (personnes, école, appartenance, leçon, compte, approbation).

## AP44 · POST `/no-show` (MarkNoShow)

- ADMIN ou moniteur de la leçon actuellement affecté. Élève : 403 ; autre moniteur ou affectation retirée : 404.
- Précondition : `PLANNED` et fin prévue passée (`409 LESSON_NOT_ENDED` sinon ; aucune absence automatique). Déjà résolue : `409 LESSON_CLOSED`.
- Effet : `NO_SHOW`, motif conservé (`no_show_reason`), occupations futures (tampon) libérées, occupations écoulées gardées, événement `LessonNoShow`.
- **Aucune pénalité** (R14/R23) : un compte de leçon est ouvert **sans charge**. Les frais d’absence éventuels restent une décision financière explicite à livrer avec les règlements.
- Réponse `200 Lesson`, ETag de leçon.

## AP88 · POST `/outcome-approvals` (approveOutcomeCorrection)

- Moniteur désigné de la leçon, actuellement affecté (mêmes droits que la publication AP54). ADMIN seul, élève ou autre moniteur : 404.
- Corps canonique `{operationId, proposal, expectedPublicationVersion}`. La proposition est contrôlée comme une correction (transition admise, version du compte, publication courante) sans être exécutée.
- Crée `OutcomeApproval` : hash SHA-256 canonique de la proposition (hors `operationId`/`pedagogicalApprovalId`), versions de leçon/compte/publication liées, validité **10 minutes**, consommation unique. Réponse `200 OutcomeApproval` (version 1 ; 2 après consommation).

## AP50 · POST `/correct-outcome` (correctOutcome)

- **ADMIN** uniquement (R16). La transaction relit leçon, compte (`expectedAccountVersion`, sinon `409 ACCOUNT_VERSION_CONFLICT`) et, si un bilan publié doit être retiré, exige `pedagogicalApprovalId` (`409 PEDAGOGICAL_APPROVAL_REQUIRED`).
- Approbation : absente/consommée/autre leçon → `409 APPROVAL_INVALID` ; expirée → `409 APPROVAL_EXPIRED` ; contenu, versions ou droits de l’approbateur changés → `409 APPROVAL_INVALID`. Un responsable qui a lui-même approuvé doit présenter un `auth_time` récent (`401 REAUTH_REQUIRED`).
- Transitions **livrées** : `COMPLETED → CANCELLED|NO_SHOW`, `CANCELLED → NO_SHOW` (rendez-vous terminé), `NO_SHOW → CANCELLED`. Effets :
  - retrait atomique du bilan publié (même mécanisme qu’AP57), `publicationVersion+1` ;
  - contre-écriture `REVERSAL` exacte des charges de réalisation, compte `version+1` (aucun paiement n’existe encore : pas de remboursement à simuler) ;
  - heures réelles effacées de la leçon mais conservées dans `lesson_outcome_correction` (état précédent, révision retirée, montant contre-passé, approbation, auteur, motif) ;
  - approbation consommée ; événement `LessonOutcomeCorrected`.
- Transitions **refusées explicitement** (`409 OUTCOME_CORRECTION_NOT_READY`, sans effet) : vers `PLANNED` (nouveau créneau et rapprochement) et vers `COMPLETED` (création d’un brouillon pour le moniteur et charge initiale ou ajustement). Même résultat : `422 OUTCOME_UNCHANGED`. Leçon encore planifiée : `409 LESSON_OUTCOME_CONFLICT`. Heures ou créneau fournis pour une issue sans réalisation : `422 OUTCOME_FIELDS_INVALID`.

## AP57 · POST `/report-publication/withdraw` (withdrawPublication)

- Moniteur désigné et affecté (mêmes droits qu’AP54). ADMIN seul et élève : 404.
- Effet : pointeur `currentPublishedRevisionId` retiré, `publicationVersion+1`, preuve `report_publication_withdrawal`, brouillon de l’auteur rebasé sur la nouvelle version, événement `ReportPublicationWithdrawn`. Aucun bilan publié : `409 NO_PUBLISHED_REPORT`. Réponse `200 Ack`.
- **Révisions conservées** : le moniteur actuellement affecté relit toujours l’historique (AP55/AP56). L’élève ne lit plus aucune révision de séquence ≤ celle retirée (politique RLS restrictive `revision_withdrawn_scope`). La progression (vue `training_progress`) suit le pointeur courant et se recalcule dans le même commit.
- Republication : même brouillon, `expectedPublicationVersion` = nouvelle version, `correctionReason` obligatoire ; la séquence suivante est attribuée (`max+1`) et seule elle redevient visible pour l’élève.

## Changements de comportement existant

- `publicationVersion` compte désormais publications **et** retraits ; la séquence de révision est calculée séparément (`max(sequence)+1`). Sans retrait, les valeurs restent identiques à l’ancienne implémentation.
- AP43 (annulation) ouvre aussi un compte de leçon sans charge ; la migration crée ce compte pour les leçons déjà `CANCELLED`/`NO_SHOW`. AP65 répond donc `200` (0 centime) au lieu de 404 pour une leçon annulée.
- Correctif découvert par les tests : AP48 avec `lessonId` échouait en 404 pour l’élève (verrou `FOR UPDATE` sur une leçon qu’il ne peut pas modifier). La lecture n’est plus verrouillée ; le verrou d’école sérialise déjà les résultats.

## Écarts et extensions de contrat

Aucun champ ajouté aux schémas canoniques. Codes d’erreur nommés introduits : `LESSON_NOT_ENDED`, `NO_PUBLISHED_REPORT`, `ACCOUNT_VERSION_CONFLICT`, `PEDAGOGICAL_APPROVAL_REQUIRED`, `APPROVAL_INVALID`, `APPROVAL_EXPIRED`, `OUTCOME_CORRECTION_NOT_READY`, `OUTCOME_UNCHANGED`, `OUTCOME_FIELDS_INVALID` (en plus de `LESSON_OUTCOME_CONFLICT` et `FINANCIAL_RECONCILIATION_REQUIRED` du dossier). AP57 ne renvoie pas d’ETag (réponse `Ack` non versionnée) : relire la leçon. Les motifs sont bornés à 1 000 caractères (limite des autres motifs et de l’audit).

## Tests

`apps/api/test/lesson-outcomes.integration.test.ts` (PostgreSQL réel) : AP44 avant/après fin, rôles, autre école, affectation retirée, concurrence par version (un 200, un 412), rejeu, compte sans charge, AP72 ; AP57 droits, 428/412, rejeu, masquage élève, historique moniteur, progression, `NO_PUBLISHED_REPORT`, republication motivée ; AP88/AP50 approbation, contenu modifié, approbation inconnue ou consommée, contre-écriture, retrait, historique, transition entre issues, refus des transitions non livrées, réauthentification du cumul des rôles. Les réponses sont validées contre `LessonEnvelope`, `AckEnvelope`, `OutcomeApprovalEnvelope`, `AccountEnvelope`.

## Reste

Transitions vers `PLANNED`/`COMPLETED`, frais d’absence et d’annulation selon conditions figées, correction ciblée des heures, AP51 (brouillon de correction par un autre auteur), notification des élèves (outbox sans consommateur).
