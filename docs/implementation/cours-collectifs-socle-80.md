# Cours collectifs : socle commun (#80) et création/publication (#38)

23 octobre 2026. Branche `vague/cours-collectifs`. Règles : [cadrage #79](cours-collectifs-cadrage-79.md).

## Inventaire avant ce lot

- Aucune table, route ni écran de cours collectif. Le contrat canonique OpenAPI 3.11.0 décrit AP126–AP146 (modèle « produit + profil réglementaire + droits »), sans implémentation. Ce modèle n'est pas repris : les décisions du 23 octobre (types prédéfinis et personnalisés, paiement sur place, file prioritaire) le remplacent. Les routes ci-dessous sont des extensions documentées ici, comme les autres extensions hors canon.
- Déjà présents et réutilisés : droits `MANAGE_COURSES`, `TAKE_ATTENDANCE`, `VALIDATE_REQUIREMENT` dans `membership.grants` ; module `collectiveCoursesEnabled` ; commandes idempotentes `schoolCommand` (operationId, If-Match, audit, reçu) ; occupation commune `drivy.reservation` avec exclusion PostgreSQL (une personne, un créneau).

## Modèle (migration 042)

| Concept | Table | Notes |
| --- | --- | --- |
| Type stable | `course_type` | Sensibilisation (`AWARENESS`) et Premiers secours (`FIRST_AID`) communs, identifiants fixes ; types personnalisés par école, nom unique. Renommer garde l'identifiant. |
| Conditions d'annulation | `course_policy_version` | Sans ligne : version 1, 24 h. Chaque changement crée une version. `offer_response_minutes` NULL = file prioritaire non activée. |
| Série | `course_series` | DRAFT, PUBLISHED, CANCELLED, CLOSED. Délai et version de politique copiés. |
| Séance | `course_occurrence` | Formateur, présence obligatoire, pas de chevauchement dans la série (exclusion). |
| Inscription | `course_enrollment` | Toute la série. Copie `policy_version`, `self_cancel_hours`, `self_cancel_deadline`. Annulation : SELF, STAFF ou SERIES_CANCELLED, auteur et motif. |
| File | `course_waitlist_entry` | Ordre d'entrée (`queued_at`, `seq`), jamais recalculé. |
| Proposition et retenue | `course_seat_offer` | Exclusive, échéance, ACCEPTED lié à l'inscription créée. Ne crée aucune occupation d'agenda. |
| Présence | `course_attendance` | Par inscription et séance. |
| Règlement sur place | `course_payment_record` | `ON_SITE` seulement, annulable. Aucune finance #45. |
| Accomplissement | `course_completion` | Validation explicite, un courant par élève et type. Absence = inconnu. |
| Événements | `course_event_outbox` | Pour #43 : cible unique et `valid_until` pour invalider un push périmé. |

## Primitives communes

- `drivy.can_manage_courses(school)` : administration, ou moniteur avec `MANAGE_COURSES`. Utilisée par la RLS et les commandes ; relue à chaque écriture et à chaque rejeu.
- `drivy.course_seats_taken(series)` : inscriptions actives + propositions actives non échues. Seul compteur. #39 et #40 l'utilisent sous le verrou de la série (`SELECT … FOR UPDATE` sur `course_series`).
- Occupation : à la publication, chaque séance insère une ligne `reservation` (formateur) avec `course_occurrence_id`. L'inscription (#39) insérera la ligne élève avec `course_enrollment_id`. La même exclusion refuse cours/cours et cours/leçon dans les deux sens, y compris en concurrence. `drivy.course_instructor_conflict` donne la prévalidation booléenne anonyme.
- `drivy.course_type_completed(learner,type)` : lecture booléenne de l'accomplissement validé.
- Échéance d'annulation : `première séance - self_cancel_hours`.

### Contrat prévu pour #39 et #40 (non implémenté ici)

- Inscription : verrou série, contrôle `course_type_completed` faux, `seats_taken < capacity`, insertion inscription puis occupation élève (exclusion = conflit agenda).
- Proposition : quand une place se libère et que la file est activée, verrou série, premier `WAITING` admissible, `expires_at = min(now + offer_response_minutes, première séance - 2 h)` (proposition, voir cadrage), statut OFFERED. Une inscription concurrente voit la place comme prise.
- Acceptation : verrou série puis proposition `ACTIVE` non échue, création de l'inscription source OFFER dans la même transaction, proposition ACCEPTED. Expiration idempotente : `UPDATE … WHERE status='ACTIVE' AND expires_at<=now()` puis proposition suivante.

## API (extension `/v1/schools/{schoolId}`)

| Méthode | Chemin | Droit |
| --- | --- | --- |
| GET | `course-catalogue` | membre ; `canManage`, types, politique, formateurs (vides sans droit) |
| POST / PATCH | `course-types`, `course-types/{id}` | gestion des cours ; prédéfinis non modifiables |
| PUT | `course-policy` (If-Match = version) | gestion des cours |
| GET | `course-series?from&to&status`, `course-series/{id}` | membre ; brouillons masqués par la RLS sauf gestion ou responsable |
| POST / PUT | `course-series`, `course-series/{id}` | gestion ; PUT sur brouillon seulement |
| POST | `course-series/{id}/publish` | gestion ; occupation des formateurs, refus du passé |
| POST | `course-series/{id}/capacity` | gestion ; jamais sous `seatsTaken` |

Codes d'erreur : `COURSE_ACCESS_REQUIRED`, `COURSE_TYPE_UNKNOWN`, `COURSE_TYPE_EXISTS`, `COURSE_TYPE_PREDEFINED`, `COURSE_OCCURRENCES_OVERLAP`, `COURSE_INSTRUCTOR_CONFLICT`, `COURSE_IN_PAST`, `COURSE_NOT_DRAFT`, `COURSE_NOT_PUBLISHED`, `COURSE_CAPACITY_BELOW_TAKEN`, `COURSE_CAPACITY_BELOW_MINIMUM`, `INSTRUCTOR_NOT_ACTIVE`, `RESPONSIBLE_NOT_ACTIVE`, `INVALID_INTERVAL`, `INVALID_TIME_ZONE`, `VERSION_CONFLICT`.

## Limites de ce lot

- Pas d'inscription, file, annulation, appel, règlement ni validation en commande : tables et lectures prêtes, écritures dans #39–#42, #81, #82.
- Modifier ou annuler une série publiée passe par #41 (non livré). Seule la capacité change après publication.
- Le module `collectiveCoursesEnabled` n'est pas exigé par les routes : l'activation de l'école reste une décision séparée.
- Aucun test exécuté en CI (stratégie #84). Les 11 tests de `courses.integration.test.ts` ont été lancés une fois localement sur PostgreSQL 17 jetable, sur la migration complète 001–042 ; ce n'est pas la campagne finale.
