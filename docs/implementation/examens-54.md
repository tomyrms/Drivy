# Suivi des examens théorique et pratique (issue #54)

1er novembre 2026, branche `claude/examens-54`, base `master` `d4257f07`. Extension hors contrat canonique (OpenAPI 3.11.0 conservé) : [contracts/exams.json](../../apps/api/contracts/exams.json). Aucun test, typage ni compilation n'a été lancé pour ce lot, à la demande du porteur ; rien n'est déployé.

## 1. Décisions du porteur (1er novembre 2026)

Les quatre points que l'issue laissait « à cadrer avant développement » ont été tranchés par le porteur, à chaque fois sur la proposition recommandée :

- **Droits** : l'administration et le moniteur actuellement affecté à la formation saisissent, modifient, reportent et renseignent le résultat. L'élève lit ses examens et ne saisit rien. Pas de déclaration de l'élève dans cette version : il n'y a donc pas de distinction « déclaré / validé » à porter, seulement « saisi par le personnel ».
- **Date passée** : un examen prévu dont la date est passée se lit « Résultat à renseigner » côté personnel et « Résultat en attente » côté élève. Il n'est jamais une réussite, un échec ni « passé » (`needsResult`).
- **Accompagnement** : facultatif, il occupe réellement l'agenda du moniteur affecté. Un examen sans accompagnement n'occupe personne.
- **Statuts** : Prévu, Reporté, Absent, Réussi, Échoué. Un report garde la tentative d'origine et en ouvre une nouvelle ; « Absent » n'est ni un échec ni une réussite.

## 2. Règles qui en découlent

- **Une tentative par ligne.** `attempt` est le rang de la tentative dans son épreuve (les reports n'en comptent pas). Plusieurs tentatives d'une même formation sont conservées distinctement.
- **Une seule tentative prévue et une seule réussie** par formation et par épreuve (index uniques). Une épreuve réussie ne se replanifie pas : il faut d'abord corriger son résultat.
- **Résultat saisi, jamais déduit.** Il ne s'enregistre qu'une fois la date venue (`EXAM_NOT_STARTED` avant). Le corriger exige un motif (`EXAM_REASON_REQUIRED`). Chaque écriture ajoute une révision signée (`exam_revision` : état complet, auteur, motif), lisible par le personnel seulement.
- **Les autres permis et les bilans sont intacts.** Un examen est rattaché à une formation (donc à un permis) ; réussite ou échec ne modifient ni cette formation, ni les autres, ni les leçons, ni les bilans. Aucune clôture ni archivage automatique après une réussite.
- **Points à travailler.** La note saisie avec un résultat est lue par l'élève.
- **Fuseau et dates.** Fuseau de l'école imposé ; date entre trois ans dans le passé (saisie après coup) et deux ans dans le futur.
- **Pas d'autorité.** Aucune inscription officielle, transmission, attestation, paiement ni taux de réussite.

## 3. API

Migration `20261101b_exams.sql` (additive) : tables `exam` et `exam_revision` (sécurité par ligne forcée), fonctions de portée (`exam_manage`, `exam_manage_exam`, `exam_escort_person`), lecture par la règle de visibilité des formations, écriture réservée à l'administration et au moniteur affecté, reçus et audit des quatre commandes. La table commune `reservation` gagne `exam_id` : l'accompagnement y occupe le moniteur sous la même contrainte d'exclusion que les leçons et les cours, donc les conflits sont refusés dans les deux sens (`EXAM_ESCORT_CONFLICT`). Le moniteur d'accompagnement doit être actif et affecté à la formation.

| Route | Rôle | Effet |
| --- | --- | --- |
| `GET trainings/{id}/exams` | lecteurs de la formation | examens, rang des tentatives, résumé par épreuve, `canManage` |
| `POST trainings/{id}/exams` (201) | `ADMIN`, moniteur affecté | prévoit un examen (épreuve, date, lieu, accompagnement) |
| `POST exams/{id}/update` (If-Match) | idem | modifie la date, le lieu ou l'accompagnement d'un examen prévu |
| `POST exams/{id}/postpone` (If-Match) | idem | reporte : l'ancien devient Reporté, un nouveau est prévu |
| `POST exams/{id}/result` (If-Match) | idem | renseigne ou corrige (motif) le résultat |
| `GET exams/{id}/revisions` | idem | historique signé |

Code : `exams.ts`. Les commandes passent par `schoolCommand` (clé d'idempotence, reçu `GET operations/{id}`, audit).

## 4. Web

Console de gestion, dossier d'un élève : onglet « Examens ». Une ligne par tentative (épreuve, rang, date, lieu, accompagnement, points à travailler) ; « Prévoir » un examen théorique ou pratique tant que l'épreuve n'est ni réussie ni déjà prévue ; modifier la date, reporter, renseigner le résultat (une fois la date venue) ou le corriger avec son motif. Un moniteur d'accompagnement se choisit parmi les moniteurs affectés à la formation. Dans l'annuaire des élèves, un bloc « Examens à renseigner » liste les examens prévus dont la date est passée et ouvre le dossier. Modèle pur testé : `apps/web/client/exam-model.ts`.

## 5. iOS

- `SchoolExamClient` : lecture, liste transversale (`filter=PENDING_RESULT|UPCOMING`) et rejeu des commandes de la file.
- **File chiffrée** : quatre commandes de plus dans `SchoolCommandKind` (`createExam`, `updateExam`, `postponeExam`, `setExamResult`), domaine « pédagogique » comme les leçons. Chaque geste est écrit dans la file avant tout envoi puis rejoué à l'identique (mêmes octets, même clé d'idempotence, même version) tant que l'école n'a pas répondu : une réponse perdue ou un arrêt de l'app ne crée jamais un second effet. Un bandeau « attend la réponse de l'école » propose Réessayer et Abandonner ; un refus définitif retire le geste et relit l'état de l'école. L'écran n'annonce rien avant la réponse.
- Section « Examens » sous la progression d'une formation, dans le dossier du moniteur comme sur la page de l'élève ; l'accompagnement se choisit parmi les moniteurs affectés (`escortCandidates`).
- Élève : une ligne « Prochain examen » au-dessus de ses leçons (Leçons), sans action.
- Personnel : « Examens à renseigner » en tête de la liste d'élèves ; chaque ligne ouvre le dossier.

## 6. Reste, hors périmètre de ce lot

- **Notifications** : aucune alerte à la saisie d'un examen ni de son résultat (#43/#44, le push n'est pas activé).
- **Agenda de l'élève** : l'examen apparaît dans Leçons (« Prochain examen ») et dans sa progression ; il n'est pas une cellule de l'agenda du personnel.
- **Qualification sur appareil** : captures, VoiceOver, texte agrandi et essai du porteur avec une vraie école.
