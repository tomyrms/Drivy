# #311 / R11 #322 — pilote Agenda

Reprise après validation de la première page Accès le 28 octobre 2026. Base intégrée : `216468c2` (aperçu Accès `e28c0e2d` et socle partagé Select/Combobox). Périmètre de cet agent : `apps/web/client/portal/agenda/*` et cette note. Aucun backend, contrat, migration, ancien rendu, point d’entrée, déploiement ou source native modifié.

## Implémenté

- `AgendaPilot` sans props obligatoires, sur le même `ConsoleContext` : période/date, filtre moniteur et recherche élève dans la semaine, leçons/cours fusionnés chronologiquement par la projection métier existante.
- Desktop : semaine horaire à sept colonnes, chevauchements disposés sur des voies distinctes, jours vides non présentés comme disponibilité. Mobile : semaine compacte de sélection et liste de la journée. Fuseau scolaire, sélection et filtres conservés ; retour avec focus et défilement de la fenêtre et de la grille.
- Fiche de leçon entièrement reconstruite : élève, rendez-vous, moniteur, lieu, durée, prix historique, faits réels et état dérivé sans déduire une réalisation de l’heure prévue. Accès à la fiche élève avec identifiant exact de la leçon et contexte de retour.
- Nouvelle création en trois étapes : participants, rendez-vous, relecture. Déplacement : identité stable, différences avant/après, accord et prix historique conservé ; nouveau tarif et motif explicites pour un changement commercial. Heure locale répétée choisie explicitement.
- Annulation en dialogue shadcn avec motif, commentaire, protection de saisie, confirmation et relecture de version sans perdre le motif. Une réponse incertaine laisse le moteur de commandes existant propriétaire de la reprise.
- Contexte de cours collectif en lecture : toutes les occurrences, séance sélectionnée, lieu, places, conditions et échéance. La gestion complète du cours relève de R17 et n’est pas remplacée par un ancien formulaire.
- Contrôleurs `.ts` séparés du JSX ; réutilisation des schémas et moteurs existants. `If-Match`, `operationId`, contrôle des attributions/disponibilités, refus serveur, conflit de version, prix/conditions historiques et verrou synchrone contre un double appui conservés.
- Erreurs de lecture avec reprise, listes partielles annoncées, absence de données distinguée d’un vide confirmé, aucune réservation optimiste.

## Contrats de l’aperçu et raccord réel

Toutes les routes sont relatives à `/app/bff/schools/:schoolId/`. Le BFF et `readSchool`/`readAll` restent canoniques. Les réponses utilisent l’enveloppe existante `{ data, requestId, serverTime }` ; les collections paginées répondent `{ items, nextCursor }`.

| Lecture | Schéma / paramètres |
| --- | --- |
| `members` | `memberSchema`, collections paginées |
| `learners` | `learnerSchema`, `status=ALL` pour l’annuaire Agenda, actifs pour la planification |
| `lessons` | `lessonSchema`, `from`, `to`, facultatif `instructorMembershipId` |
| `course-series` | `courseSeriesListSchema`, `from`, `to`, max. 200 séries ; au plafond la lecture est déclarée partielle |
| `course-series/:courseId` | `courseSeriesSchema`, contrôle de l’identité école/série |
| `lessons/:lessonId` | `planningLessonSchema`, détails requis : `actualStart`, `actualEnd`, `learnerDisplayName`, `instructorDisplayName`, `priceCentsSnapshot`, `bufferMinutesSnapshot`, `commercialSelection`, `commercialRevisionVersion` |
| `offerings` | `offeringSchema` |
| `policy-versions` | `catalogPolicySchema` |
| `service-products` | `planningProductSchema`, inclut `current` et `siteId` |
| `commercial-terms` | `termsSchema` |
| `trainings` | `trainingSchema`, `learnerId` |
| `trainings/:trainingId/assignments` | `assignmentSchema` |
| `lessons/availability` | `slotAvailabilitySchema`, `trainingId`, `instructorMembershipId`, `plannedStart`, `plannedEnd`, `timeZone`, `bufferMinutes`, et `excludeLessonId` au déplacement |

Écritures uniquement via `createCommand` et `useCommandRunner` existants : `createLesson` sur `lessons`, `moveLesson` sur `lessons/:id/move`, `cancelLesson` sur `lessons/:id/cancel`. Le corps de création/déplacement provient de `lessonWriteBody`; l’annulation transmet `{ reasonCode, comment }`. Les modifications portent la version et l’identifiant de la ressource. Aucune autre file d’attente, aucun faux résultat dans le pilote.

Jeux d’états nécessaires à la démonstration :

- Semaine future relative à la date d’exécution, plusieurs élèves et moniteurs, rendez-vous voisins et chevauchants, cours à plusieurs séances, leçon planifiée et réalisée, permis à vérifier.
- Catalogue approuvé, produit individuel valide, conditions actuelles et version historique distincte, formation active et attribution couvrant le créneau.
- Vide confirmé, lecture lente, échec annuaire/leçons/cours, collection tronquée, recherche élève, état annulé/absent/en cours.
- Disponibilité refusée, conflit de version lors du déplacement et de l’annulation, réponse perdue nécessitant vérification de reçu, refus de droit/session expirée, double appui.
- Desktop/mobile, clair/sombre, clavier, retour exact depuis fiche élève ; heure locale inexistante/répétée dans Europe/Zurich.

## Vérification

`npm run typecheck` **PASS** (client et configuration de contrôle), sur le rendu complet et le socle `216468c2`. Build Vite ciblant directement `agenda-page.tsx` **PASS**, via la configuration d’aperçu et son garde des imports : **aucun ancien rendu importé**. Sortie temporaire sous `node_modules/.cache/agenda-311-build`, hors Git. Vitest ciblé `calendar-layout.test.ts` : **4 tests PASS**, vérifiant les chevauchements, les rendez-vous courts, le fuseau scolaire et l’heure locale répétée. Aucune campagne étendue API, navigateur ou native lancée. L’intégration runtime, l’aperçu exécutable et les preuves visuelles sont coordonnés par le responsable de #311. Cette note ne vaut pas validation visuelle, ne ferme pas #322 et n’affirme pas de déploiement.
