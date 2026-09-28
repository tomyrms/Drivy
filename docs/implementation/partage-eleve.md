# Partage automatique avec l’élève

Décision du porteur du 28 septembre 2026 ([décisions](decisions-2026-09-28.md)) : l’élève voit son trajet, les erreurs et points positifs notés pendant la leçon, son bilan et les objectifs de la leçon, sans geste de publication. Le moniteur garde pour lui ce qu’il choisit.

## Serveur (migration 012, API)

| Élément | Règle |
|---|---|
| Bilan | À la fin de la leçon (AP49) et à chaque enregistrement du brouillon (AP52), le brouillon de l’auteur devient la révision courante lue par l’élève. Un contenu identique ne crée pas de révision. Un bilan vidé est retiré. Les révisions suivantes portent le motif automatique « Bilan mis à jour par le moniteur. ». |
| Bilan privé | `lesson.report_private` : la révision courante est retirée (table `report_publication_withdrawal`, comme AP57) et les enregistrements suivants ne la republient pas. Repasser en partagé republie la version courante du brouillon. AP57 met aussi le bilan en privé ; une publication explicite (AP53) le repartage. |
| Observations | Visibles par l’élève si la leçon est réalisée, l’observation non retirée et non marquée `private` (RLS `observation_learner_read`). Une observation qui arrive après la fin de la leçon rejoint le brouillon au lieu d’être refusée. |
| Trajet | Visible par l’élève si la leçon est réalisée, la capture finalisée (SYNCED ou PARTIAL) et `lesson.capture_hidden` faux (RLS `capture_learner_read`). Les lots suivent la session par la politique existante ; le replay déchiffre côté serveur comme pour le moniteur. |
| Objectifs | L’élève lit la préparation de ses leçons ; l’API masque `administrativeCheckNote`. |
| Contrat | Les projections canoniques OpenAPI 3.11.0 restent inchangées : l’état de partage passe par des extensions. |

Extensions ajoutées :

- `GET /v1/schools/{schoolId}/lessons/{lessonId}/sharing` : auteur seulement ; `{lessonId, schoolId, version, reportPrivate, captureHidden, privateObservationIds}` et `ETag`.
- `PUT /v1/schools/{schoolId}/lessons/{lessonId}/sharing` : auteur seulement, `If-Match` sur `version`, `Idempotency-Key = operationId`, commande `UPDATE_LESSON_SHARING` prouvable par AP72. Erreur `OBSERVATION_NOT_IN_LESSON` si une observation ne fait pas partie de la leçon.
- `GET /v1/schools/{schoolId}/lessons/{lessonId}/captures` : trajets de la leçon lisibles par le compte (moniteur affecté, ou élève si partagés).

Profil GPS d’essai : un profil de `CAPTURE_QUALIFICATION_PROFILES_JSON` accepte `*` (toute valeur) et `26.*` (préfixe de version) pour le modèle, le système et le build. Il ne qualifie rien : il autorise la collecte sur un appareil déclaré par le porteur.

## Preuves

CI « Refonte · vérifications », PostgreSQL 17 réel, à chaque push depuis le 28 septembre 2026 :

- `lesson-reports.integration.test.ts` : partage à la fin de la leçon, révision par enregistrement, pas de doublon, droits de lecture, bilan privé, repartage, progression et note administrative masquée ;
- `lesson-outcomes.integration.test.ts` : AP57 laisse le bilan privé, republication motivée ;
- `capture-observations.integration.test.ts` : observation tardive, lecture élève, « Pour moi » ;
- `capture.integration.test.ts` : trajet visible après la leçon, masqué à la demande, profil d’essai à jokers.

Run [36451503346](https://github.com/tomyrms/Drivy/actions/runs/36451503346) : 11 fichiers sur 12 réussis ; le dernier était l’ancien échec G1B (admin autorisé à modifier une appartenance depuis AP08), corrigé dans le test.

## État

- Déployé le 28 septembre 2026 (release `6c03c02`, migrations 010 à 013).
- App : l’écran de leçon unique sert au moniteur (interrupteur « Visible par l’élève » sur le trajet et sur le bilan, cadenas « Gardée pour moi » par observation) et à l’élève (onglets Leçons et Progression).
- À qualifier sur appareil : lecture d’un vrai trajet par l’élève après une leçon.
