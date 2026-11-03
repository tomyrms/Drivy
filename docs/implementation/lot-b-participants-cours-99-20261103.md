# Lot B participants des cours (#99, lot E) : faits indépendants d’un participant à l’autre

Branche `tomyrms/lotb-participants-99`, base `d7792899` (`claude/lot-a-20261102`). Web uniquement (`apps/web`) ; `apps/api` n’est pas modifié. Aucune donnée réelle : les tests n’emploient que des participants synthétiques (identifiants aléatoires, « Élève A »/« Élève B »).

## 1. Audit : ce que chaque commande renvoie, et ce que le web en faisait

| Commande web | Route (lecture seule, `apps/api/src/course-facts.ts`) | Corps renvoyé |
| --- | --- | --- |
| `recordCourseAttendance` | `PUT /course-enrollments/:id/attendance/:occurrenceId` (l. 154-161) | `{data: sheet}` : **la feuille complète de la série** `{series, rights, rows}` — tous les inscrits, toutes les séances, tous les règlements, droits de l’appelant |
| `recordCoursePayment` | `POST /course-enrollments/:id/payments` (l. 163-170) | la même feuille complète, code 201 |
| `voidCoursePayment` | `POST /course-payments/:id/void` (l. 171-178) | la même feuille complète |
| `validateCourse` | `POST /course-enrollments/:id/validate` (l. 180-187) | la même feuille complète, code 201 |
| `revokeCourseCompletion` | `POST /course-completions/:id/revoke` (l. 188-195) | la même feuille complète |

Le rejeu idempotent (même `Idempotency-Key`) renvoie la même feuille. Aucune de ces routes ne renvoie la seule ligne du participant.

**Fusion côté web, avant ce lot** : `use-course-participants.ts` parsait `{data: sheet}` et faisait `setFresh({scope, sheet})` ; l’écran affichait `fresh.sheet` à la place de la lecture, et un `useEffect` effaçait `fresh` dès qu’une lecture commencée après l’écriture arrivait (`readIsCurrent`). Un seul envoi à la fois (`locked = runner.busy || runner.pending` plus un verrou `inFlight`), donc une réponse ne pouvait jamais en écraser une autre.

**Conséquence pour l’indépendance** : chaque réponse est calculée dans sa propre transaction ; deux réponses en vol peuvent revenir dans n’importe quel ordre, et la plus ancienne porte une copie périmée des **autres** inscrits. Remplacer la feuille entière effacerait donc un fait déjà confirmé chez un autre participant.

La fusion par participant est possible sans risque pour ces cinq commandes : chaque réponse est autoritaire pour **sa** ligne (écrite dans la même transaction), et rien d’autre de la feuille ne change (ni la série, ni les droits, ni une autre ligne). Décision retenue : garder la lecture pour tout, ne remplacer que la ligne que la commande concernait, avec une génération d’écriture par ligne — une lecture commencée avant la réponse ne remplace pas cette ligne, une lecture commencée après la remplace.

## 2. Ce qui existait déjà

- `client/command-lane.ts` et `console/context.ts` (`useCommandLane`, `blocked(subject)`, `refusalOutcome`, reçu AP72) : socle du lot A web, utilisé par les invitations, les horaires, les dossiers, le catalogue.
- `client/command-conflicts.ts` : clés en chemins (`related` par préfixe), la clé unique `course-facts` pour les cinq types.
- `portal/courses/participants-view.tsx` (quatre onglets), `participants-attendance.tsx`, `participants-payments.tsx`, `participants-completion.tsx`, `participants-roster.tsx`, `participants-dialogs.tsx` (`ActionDialog`), `participants-parts.tsx` (`FeedbackText`), `participants-model.ts` (résumé d’appel, éligibilité, total compté, `intentKey`), tests `participants-model.test.ts`.
- Tests web de référence pour une voie : `test/command-lane.test.ts`, `test/pricing-lane.test.ts`.

## 3. Ce qui change

| Fichier | Changement |
| --- | --- |
| `client/command-conflicts.ts` | **Seule la ligne des cinq types** : `course-facts:<série>:<participant>` quand `scope` est fourni, `course-facts` sinon. Deux participants ne s’attendent plus, le même reste ordonné, la relation avec `planning` et `*` est inchangée. |
| `portal/courses/participants-projection.ts` (nouveau, pur) | `participantScope(series, participant)`, `mergeSheet` (fusion par ligne avec génération), `visibleIntentions`, `projectParticipants` (marques, présence demandée, montant voulu, participants suivis), `markLabels`, `resumeOf`/`resumable`. Aucun DOM, aucun réseau, une seule dépendance de type. |
| `portal/courses/use-course-participants.ts` | Passe de `useCommandRunner` à `useCommandLane`. Un geste par participant à la fois (le magasin refuse le second, l’interface le désactive avec la marque pour explication) ; deux participants partent ensemble. Formulaire libéré dès que le magasin garde la demande. Fusion des réponses par ligne. Bandeau de refus pour un montant, une note ou un motif saisis. `pay` refuse un montant qui n’est pas un entier de centimes. |
| `portal/courses/participants-view.tsx` | Bandeau « Reprendre la saisie » (refus) qui rouvre la tâche et le dialogue concernés avec la saisie ; plus de verrou global. |
| `participants-attendance.tsx`, `participants-payments.tsx`, `participants-completion.tsx`, `participants-roster.tsx`, `participants-dialogs.tsx`, `participants-parts.tsx` | Marques « À confirmer » sur la ligne concernée (`MarkText`), contrôles désactivés par participant (et non plus globalement), dialogues qui se ferment à la conservation de la demande, `initialReason`/montant rendus à la reprise. |
| `test/command-conflicts.test.ts` | Ajouts : clés par participant, même participant ordonné, sans agrégat conservateur, relation avec `planning` et les accès inchangée. |
| `portal/courses/participants-projection.test.ts` (nouveau) | Projection : présence, règlement, validation, retrait, annulation, réponse complète tardive, lecture plus récente, refus, reprise. |
| `test/course-participants-lane.test.ts` (nouveau) | Voie réelle contre le vrai magasin : deux participants ensemble, même participant refusé sur place, double appui, réponse perdue puis reçu sans seconde écriture, refus isolé, aucun contenu saisi dans l’état de la voie. |

## 4. Preuve par critère

| Critère de la tâche | Preuve |
| --- | --- |
| Un geste par participant, deux participants indépendants | `command-conflicts.test.ts` : `attendance(A)` et `payment(B)` ne se bloquent pas, `attendance(A)`/`validate(A)`/`revoke(A)`/`void(A)` se bloquent, `course-facts:<série>:<participant>` ; `course-participants-lane.test.ts` : deux envois simultanés partent, un second geste sur le même participant est refusé `LOCAL_COMMAND_CONFLICT` sans second envoi. |
| Clé `course-facts:<série>:<participant>` avec `scope`, `course-facts` sans | `command-conflicts.test.ts` (dont `wouldConflict` avec et sans `scope`). |
| Relation avec `planning` inchangée | `command-conflicts.test.ts` : leçon, réinscription, reprogrammation ne bloquent pas un fait de cours (comme avant), un changement d’accès bloque tout. |
| Présence demandée = marque, valeur confirmée lisible | `participants-projection.test.ts` : `marks = ['attendance']`, `attendanceMarks` porte le statut voulu, `attendanceCell(feuille)` garde `PRESENT`. |
| Règlement demandé = montant voulu, jamais compté | `participants-projection.test.ts` : `paymentMarks` = 12 050 centimes, `settledCents`/`groupSettledCents` restent 2 000. |
| Validation demandée = marque, jamais une attestation | `participants-projection.test.ts` : `activeCompletion` reste `null` pour une validation demandée, reste lue pour un retrait demandé. |
| Réponse complète tardive n’efface pas un autre participant en vol | `participants-projection.test.ts` : B répond en premier (ordre 1), A ensuite (ordre 2) avec une copie périmée de B ; la ligne B garde son règlement et sa marque. `mergeSheet` : une lecture plus ancienne que la réponse ne remplace pas la ligne, une lecture postérieure la remplace ; une ligne absente n’est pas ressuscitée par une réponse antérieure. |
| Refus : seule la ligne concernée, bandeau « Reprendre la saisie » pour un montant/un motif | `participants-projection.test.ts` (refus = intention retirée, autres lignes intactes ; `resumeOf` rend montant, note, motif, motif de retrait, motif d’annulation et élève choisi, `null` pour présence et validation) ; `course-participants-lane.test.ts` : un refus ne touche pas l’autre participant en vol. |
| Double appui, réponse perdue puis reçu sans seconde écriture | `course-participants-lane.test.ts` : un seul appel réseau pour deux appuis ; après 503, l’intention reste suivie, un autre participant avance, le reçu AP72 (`GET` seul) confirme sans nouvelle écriture. |
| Montants en centimes entiers | `use-course-participants.ts` (`pay` refuse tout montant non `Number.isSafeInteger` ou négatif) ; projection testée sur 12 050 centimes. |
| Aucune donnée réelle | Tous les tests utilisent `randomUUID()` et des libellés synthétiques. |

## 5. Non fait, non prouvé

- **Parcours navigateur (Edge/Playwright) et captures : NOT_EXECUTED.** Aucun serveur ni aperçu lancé ; rien n’est mesuré sous latence réelle (la latence simulée des tests n’est pas une perception).
- **Aucun serveur réel, aucun test `apps/api` ni PostgreSQL : NOT_EXECUTED** (`apps/api` non modifié ; base non fournie).
- Aucune vérification VoiceOver, clavier ou grands textes : NOT_EXECUTED (pas de navigateur ici). Les marques sont du texte (jamais la couleur seule) et les contrôles désactivés pointent vers la marque par `aria-describedby`, mais cela n’a pas été éprouvé à l’écran.
- `intentKey` de `participants-model.ts` n’est plus appelé par le hook : il servait à une reprise qui ne pouvait pas se déclencher (le verrou global empêchait tout nouvel envoi pendant un résultat inconnu). Il reste exporté et testé ; le retirer imposerait de modifier un fichier hors de la liste autorisée.
- La marque « À confirmer » disparaît dès la confirmation (réponse ou reçu) ; la valeur confirmée arrive avec la relecture déclenchée par la révision du magasin. Aucun fait n’est inventé entre les deux, mais l’écran peut montrer l’ancienne valeur pendant la relecture.
- Un refus d’inscription (élève choisi dans le sélecteur) ouvre bien la reprise avec l’élève présélectionné, mais la sélection n’est pas rejouée automatiquement : la personne confirme à nouveau.

## 6. Vérifications exécutées (3 novembre 2026)

| Vérification | Résultat |
| --- | --- |
| `npm ci` dans `apps/web` (node_modules absent) | OK ; avertissement `EBADENGINE` (Node v26.8.1, `engines` demande `>=24 <25`), pas une erreur |
| `npm run typecheck` | PASS |
| `npm run test:unit` avant le lot | 67 fichiers, 693 réussis, 1 échec attendu (694) |
| `npm run test:unit` après le lot | 69 fichiers, 711 réussis, 1 échec attendu (712) |
| Tests ajoutés | `participants-projection.test.ts` (10), `course-participants-lane.test.ts` (5), `command-conflicts.test.ts` (+3) |
| Tests `apps/api`, PostgreSQL | NOT_EXECUTED (base non fournie, aucun fichier API modifié) |
| Navigateur, appareil, VoiceOver, déploiement | NOT_EXECUTED |

## Verdict

Le lot E côté web est réalisé : la clé de conflit isole chaque participant, les cinq faits passent par la voie de commandes, la projection pure marque les gestes en attente sans jamais les présenter comme confirmés, et une réponse complète tardive ne peut plus effacer la ligne d’un autre participant. Restent à qualifier sur un vrai navigateur et, côté serveur, les rejeux réels (aucun test d’intégration lancé ici).
