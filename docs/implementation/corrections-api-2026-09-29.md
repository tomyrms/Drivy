# Parcours API repris le 29 septembre 2026

Les travaux déjà présents dans le checkout d’agent `api-corrections` ont été intégrés, puis vérifiés sur PostgreSQL réel. Le contrat OpenAPI 3.11.0 conservé n’est pas réécrit ; les ajouts ci-dessous sont des extensions.

| Problème | Comportement implémenté |
|---|---|
| Leçon immédiate nécessitant la saisie des réglages connus | `POST /lessons/start-now`, moniteur affecté : `{operationId,trainingId,meetingPoint?}`. Début courant, durée/offre/tarif/conditions choisis au serveur. Conflits d’occupation et droits conservés. Les disponibilités ne bloquent pas le moniteur qui démarre lui-même. |
| Permis soumis à une habilitation à configurer | ADMIN et moniteur affecté contrôlent directement le permis. |
| Leçon future terminée par erreur | Refus `LESSON_NOT_STARTED` plus de 15 minutes avant le début prévu. |
| Ancien tarif toujours réservable | Seule la version courante du produit est utilisable. Les dates civiles suivent le fuseau de l’école. |
| Tampon prolongeant l’ouverture requise | La leçon peut finir à l’heure de fermeture ; l’occupation conserve le tampon entre les leçons. |
| Formation créée par un moniteur devenant invisible | Affectation automatique du créateur, atomique ; `assignCreator` permet le choix explicite. |
| Configuration annoncée incomplète malgré ses données | `CAN_PLAN_LESSON` relit offres, moniteurs, ouvertures, prestations et politique des champs. |
| Réponses de leçon sans noms ni état réel du trajet | `learnerDisplayName`, `instructorDisplayName` et `captureSummary` relus avec les droits courants. |
| JSON invalide traité comme panne rejouable | 400, 413 et 415 conservés comme erreurs client, sans détails internes. |

Toutes les routes suivantes sont sous `/v1/schools/{schoolId}`, réservées à ADMIN, avec `Idempotency-Key = operationId`, `If-Match`, audit et preuve AP72. Un refus ne modifie rien.

| Route | Corps en plus de `operationId` | Résultat |
|---|---|---|
| `POST /members/{id}/deactivate` | `reason` | Retire l’accès, termine les affectations et rend `plannedLessonCount`. Authentification récente ; ni dernier ADMIN ni soi-même. |
| `POST /trainings/{id}/assignments/{assignmentId}/end` | `reason?` | Termine l’affectation, invalide les curseurs du moniteur et rend `plannedLessonCount`. Une affectation future reçoit un intervalle vide, donc aucun accès ultérieur. |
| `POST /trainings/{id}/transition` | `targetStatus`, `reason` | Pause, reprise, fin ou annulation. Les états finaux rouvrent vers ACTIVE ; une formation courante identique bloque la réouverture. Les leçons à venir bloquent la clôture. |
| `POST /learners/{id}/archive` | `reason` | Archive après clôture des formations ; conserve l’historique. |
| `POST /learners/{id}/restore` | `reason` | Restaure le dossier, sans rouvrir ses formations ni réactiver une appartenance révoquée. Commande `RESTORE_LEARNER`. |
| `PUT /modules` | `gpsEnabled` | Modifie le seul module GPS ; authentification récente. |

Migrations 016 : cycle de vie, droits SQL, restauration et intervalles d’affectation vides. Migration 017 : contrôle du permis, version courante des prestations, noms des leçons, démarrage immédiat. Migration 018 : invitations multi-permis, détaillées dans [trajets et codes](api-trajets-codes.md).

Le code existant couvre les charges du compte de leçon, mais pas la saisie des règlements ; aucune API de documents, de cours collectifs ou de notifications in-app/push n’est présente. Ces modules ne sont pas déclarés livrés.
