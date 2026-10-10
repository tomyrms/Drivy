# G2 — préparation, constat et bilan partagé

Implémentation du 24 septembre 2026, migration `007_lesson_reports.sql`, après les leçons de 006. Le dossier canonique reste intact. Références : [F06/F07](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/planning-lecons.md), [F08](../../Drivy_Conception_v3_17_2026-09-20/03-fonctionnel/bilans-documents.md), R15/R17–20/R23/R33/R36/R40/R46 et les DTO [OpenAPI](../../Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml).

## Parcours livré

Le moniteur désigné et actuellement affecté prépare sa leçon, lit le souhait distinct de l’élève, constate une réalisation et conserve son brouillon privé. Il sauvegarde les trois textes et, uniquement s’il les choisit, des observations de compétences contextualisées. Une commande distincte publie une révision immuable. L’élève lit alors cette révision et sa progression ; les autres moniteurs actuellement affectés peuvent lire les bilans partagés. ADMIN seul n’accorde aucun accès à la préparation, au brouillon ou aux révisions pédagogiques.

Le constat en `UNIT_PRICE` crée, dans le même commit, l’état COMPLETED, les heures réelles, le brouillon, un compte et sa charge INITIAL au prix convenu. Le montant reçu vaut réellement zéro : aucun paiement n’est généré. Le registre de consommation des packs n’est pas livré ; `ENTITLEMENT_NOT_READY` bloque ce mode sans aucun effet partiel. Le permis n’étant pas encore contrôlable dans cette tranche, le constat exige un `anomalyReason` explicite et conserve le signalement ; il ne valide pas le permis. La fin réelle doit suivre le début et ne peut dépasser l’heure serveur de plus de cinq minutes. Aucune durée/prix n’est déduite du GPS.

## Contrat raccordé

Toutes les routes sont préfixées par `/v1/schools/{schoolId}`. Les écritures portent `operationId`, un `Idempotency-Key` identique et un `If-Match` fort de la ressource indiquée. Les corps et réponses reprennent le canon, enveloppés par `data`, `requestId`, `serverTime`.

| API | Route | Commande AP72 → ressource | Version If-Match |
|---|---|---|---|
| AP45/46 | GET/PUT `/lessons/{lessonId}/preparation` | `SAVE_PREPARATION` → `Preparation` | préparation |
| AP47/48 | GET/PUT `/trainings/{trainingId}/wish` | `SAVE_WISH` → `Wish` | souhait |
| AP49 | POST `/lessons/{lessonId}/complete` | `COMPLETE_LESSON` → `Lesson` | leçon |
| AP52/53 | GET/PUT `/report-drafts/{draftId}` | `SAVE_REPORT_DRAFT` → `ReportDraft` | brouillon |
| AP54 | POST `/report-drafts/{draftId}/publish` | `PUBLISH_REPORT_DRAFT` → `ReportRevision` | brouillon |
| AP55 | GET `/lessons/{lessonId}/reports` | — | — |
| AP56 | GET `/report-revisions/{revisionId}` | — | — |
| AP58 | GET `/trainings/{trainingId}/progress` | — | — |
| AP65 | GET `/lessons/{lessonId}/account` | — | compte en lecture |

AP49 renvoie exactement `{lesson,draft,account}` et un ETag de leçon. Aucun `expectedAccountVersion` n’est ajouté au corps canonique : le compte est créé à la réalisation. Le reçu AP72 référence la leçon et sa version. Les identifiants de `Preparation`/`Wish` diffèrent des identifiants de route ; le reçu de publication référence la nouvelle révision, de version 1, et non le brouillon.

Extension de reprise documentée : GET `/lessons/{lessonId}/report-drafts?limit=50&cursor=…` renvoie `{items: ReportDraft[],nextCursor}`. Elle retrouve le brouillon de l’auteur courant après perte de la réponse AP49. Limite 1–100, curseur opaque lié à auteur/école/epoch/leçon. Aucune création ni transmission à l’élève lors de ce GET. La version courante conserve un brouillon par leçon et auteur ; après publication son ETag augmente et `basePublicationVersion` rejoint le pointeur courant. Une correction repart de ce brouillon, exige un nouveau motif et produit une nouvelle révision sans modifier la précédente. AP51, transferts de responsabilité et retrait AP57 restent à raccorder séparément.

`PublishCommand` exige toujours `captureSelection:null` et `textObservationSelection:[]` pour ce parcours sans capture scolaire. Toute sélection non vide reçoit `OBSERVATION_PUBLICATION_NOT_READY` ; aucune capture G0, position ou annotation n’est importée. `attachmentIds` doit rester vide (`ATTACHMENT_NOT_READY` autrement) tant que le pipeline F09 n’est pas livré. Les tableaux vides en sortie correspondent à l’absence réelle de ces objets serveur. Les futures observations LIVE devront être rattachées dans la transaction AP49 avant de rendre leurs endpoints accessibles ; cette tranche ne prétend pas implémenter AP162–164.

Les champs texte du bilan sont limités à 4 000 points de code Unicode, souhait à 500, motif à 1 000. Zéro à trois objectifs ; vingt repères manuels privés ; cent observations de compétences au plus, sans doublon. Le référentiel est celui de l’offre de la formation. Les limites de corps HTTP acceptent les bornes Unicode annoncées : préparation/constat/publication 100 000 octets, sauvegarde du bilan 350 000 octets. Les repères ne génèrent aucune position enregistrée. Omettre `plannedWaypoints` conserve les repères, `[]` les vide.

## Persistance et atomicité

Six tables sont nécessaires : `lesson_preparation`, `training_wish`, `report_draft`, `report_revision`, `lesson_account`, `charge_entry`. Les préparations et souhaits vides sont créés par triggers avec leur parent et initialisés pour les parents existants ; aucun GET n’écrit. Il n’y a ni contenu inventé ni adoption implicite.

Toutes ont RLS forcée. Les fonctions d’autorisation relisent l’appartenance active et l’affectation pédagogique ; l’auteur privé est contrôlé indépendamment d’un éventuel rôle ADMIN. La charge et la révision sont append-only pour le rôle d’exécution. La charge INITIAL est unique par compte. Les snapshots internes conservent identifiant/version/libellé du référentiel relu ; la réponse canonique ne reçoit aucun champ supplémentaire.

Les commandes utilisent l’ordre de verrous partagé : personnes concernées, école, appartenance de l’auteur, leçon puis préparation/brouillon/compte. L’idempotence, l’effet, l’audit et l’événement `lesson_event_outbox` sont commités ensemble. AP72 relit les droits actuels avant d’exposer seulement la preuve de commit. Le retrait d’un rôle ou d’une affectation ne rend pas un ancien brouillon accessible via la reprise.

La vue `training_progress`, avec `security_invoker`, ne lit que les révisions pointées comme courantes. Elle sélectionne par compétence la dernière réalisation (`actualEnd`, puis `lessonId` stable). Une correction remplace les observations de sa propre leçon dans cette projection ; une observation omise laisse celle d’une leçon antérieure lorsqu’elle existe. Ni brouillon ni arrivée réseau tardive ne gagne sur une réalisation plus récente. Publication, pointeur et projection deviennent visibles dans le même commit. L’événement durable n’est pas une notification envoyée : aucun worker de notification n’est revendiqué.

## Refus utilisables par les écrans

`VERSION_CONFLICT` (412), `PUBLICATION_VERSION_CONFLICT` (409), `IDEMPOTENCY_MISMATCH` (409), `LESSON_CLOSED`/`LESSON_NOT_COMPLETED` (409), `REPORT_INCOMPLETE` (422), `CORRECTION_REASON_REQUIRED` (422), `ANOMALY_REASON_REQUIRED` (422), `INVALID_ACTUAL_INTERVAL` (422), `WISH_LESSON_INVALID` (422), `CURRICULUM_VERSION_MISMATCH` (409), `ATTACHMENT_NOT_READY` (409), `ATTACHMENT_SELECTION_INVALID` (422), `OBSERVATION_PUBLICATION_NOT_READY` (409), `ENTITLEMENT_NOT_READY` (409). Un identifiant hors portée donne 404. Une ancienne commande incertaine reste conservée tant que sa preuve n’est pas réconciliée ; un refus actuel ne prouve pas l’absence d’un commit antérieur.

## Vérification effectuée

Typecheck TypeScript réussi. Migration 007 exécutée sous le rôle propriétaire réel de recette sans SUPERUSER/BYPASSRLS/CREATEROLE, dans une transaction annulée : 34 tables sur 34 protégées par RLS forcée avec 001–006. Contrôle HTTP nominal séparé sur PostgreSQL 17 local et données strictement synthétiques : préparation GET/PUT, Complete, rejeu exact avec une seule charge, reprise du brouillon, refus 404 du brouillon pour élève et ADMIN seul, publication, lecture élève, refus ADMIN seul et lecture de progression. Le compte observé a 9 000 centimes dus et zéro reçu. Ce contrôle ne qualifie pas le planning complet, un fournisseur OIDC, une capture physique, des notifications ni les clients natifs ; aucune campagne exhaustive ou action distante n’a été lancée.

**Mise à jour du 25 septembre 2026 :** AP49 n’exige plus `anomalyReason` lorsque le permis est approuvé et valide à la date de la leçon ([g2-permis.md](g2-permis.md)). Le retrait AP57 et la correction AP50/AP88 sont livrés ([g2-issues-lecon.md](g2-issues-lecon.md)) ; `publicationVersion` compte aussi les retraits, la séquence de révision est calculée séparément. AP45–AP58 et AP65 ont désormais des tests PostgreSQL ([tests-planning-bilan.md](tests-planning-bilan.md)) ; ils ont révélé et corrigé un 404 d’AP48 avec `lessonId` pour l’élève.
