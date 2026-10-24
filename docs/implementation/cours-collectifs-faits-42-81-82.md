# Cours collectifs : appel (#42), règlements sur place (#81), validation (#82)

24 octobre 2026. Branche `vague/cours-collectifs`. Migration 044, `apps/api/src/course-facts.ts`.

## Trois faits distincts

| Fait | Qui | Règle |
| --- | --- | --- |
| Présence (#42) | Gestion des cours, droit `TAKE_ATTENDANCE`, ou formateur de la séance | Une valeur par élève et séance (Présent, Absent, Excusé). Rien n'est déduit : ni de l'inscription, ni de l'heure, ni du paiement. Saisie seulement après le début de la séance. Correction avec la version attendue ; chaque saisie dans `course_attendance_history` avec auteur. |
| Règlement (#81) | Gestion des cours ou droit `cash_record` | « Payé sur place », montant informatif. Annulation avec motif, jamais supprimé. Aucun effet sur présence, validation ou compétence. Pas de remboursement. |
| Validation (#82) | Administrateur ou droit `VALIDATE_REQUIREMENT` | Explicite, seulement si toutes les séances obligatoires sont marquées présentes. Une validation courante par élève et type (identifiant stable). Retrait avec motif ; historique gardé. Valider retire l'élève des listes d'attente du même type. |

## API

- `GET course-series/{id}/sheet` : feuille du personnel (élèves × séances, compteur requis/présent/manquant, règlements si droit, validation), droits de l'appelant.
- `PUT course-enrollments/{eid}/attendance/{oid}` `{status, expectedVersion, note}`.
- `POST course-enrollments/{eid}/payments`, `POST course-payments/{id}/void`.
- `POST course-enrollments/{eid}/validate`, `POST course-completions/{id}/revoke`.
- `GET course-progress/me` : validations et progression de l'élève appelant, sans paiement ni autres participants.

## Vérification

- 5 tests ciblés (`course-facts.integration.test.ts`) et 34 au total pour les cours, passés localement sur PostgreSQL 17 jetable (migrations 001 à 044). Pas la campagne #84.

## Limites

- La validation ne regarde pas les séances futures : un cours de plusieurs jours n'est validable qu'après l'appel de toutes ses séances obligatoires.
- Une présence corrigée après validation ne retire pas la validation : le personnel la retire explicitement (aucune invalidation silencieuse).
- Pas d'attestation officielle (choix produit, #79).
