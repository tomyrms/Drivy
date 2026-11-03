# Lot B — Planification web (#109) : créer, déplacer et annuler une leçon sans fausse réservation (3 novembre 2026)

Branche `tomyrms/lotb-planif-web-109` (base `34d4c01a`). Web uniquement : `apps/api`, l'iOS et le contrat OpenAPI ne sont pas touchés. Aucun déploiement, aucune PR, aucun envoi réel. Les garanties du lot A restent : aucun succès avant la réponse vérifiée ou le reçu AP72, droits relus au serveur, une projection locale n'accorde ni créneau ni prix.

Deux fichiers hors de la liste initiale ont été modifiés sur autorisation explicite du porteur (réponse du 3 novembre 2026) : `apps/web/client/portal/pilotage/dashboard-appointments.tsx` et `apps/web/client/portal/pilotage/appointments.ts` (affichage des marques seulement, aucun changement de chiffre, de compteur, de lien ni de statistique ; une intention provisoire n'entre dans aucune ligne ni aucun total) et `apps/web/client/portal/runtime/pending-requests.tsx` (règle d'expiration limitée aux créations et déplacements de leçon, comportement inchangé pour tout autre type de commande).

## Étape 1 — audit : ce que le web possède réellement

| Commande | Symbole | Test existant | Écart réel avec #109 |
| --- | --- | --- | --- |
| Créer une leçon | `portal/agenda/use-lesson.ts` (`useLessonEditor.submit`) : `createCommand({ kind: 'createLesson', path: 'lessons' })` via `useCommandRunner`, vérification préalable `GET lessons/availability` (`verify`), assistant Participants → Rendez-vous → Relire | `test/lesson-planning.test.ts` (corps, prix, reçu `CREATE_LESSON`, route BFF), `test/agenda-model.test.ts` | Le formulaire restait verrouillé jusqu'à la confirmation (`runner.busy`, `submitInFlight`, `locked`) ; aucune ligne provisoire ; le dialogue ne se libérait pas ; un refus rouvrait le formulaire mais effaçait la revue. |
| Déplacer (horaire, lieu, durée) | même éditeur, `kind: 'moveLesson'`, `If-Match`, `agreementConfirmed`, `commercialChange`, `changeRequestId` pour la demande de l'élève | `test/lesson-planning.test.ts` (accord obligatoire, changement commercial, `MOVE_LESSON`), `test/lesson-change-model.test.ts` | Même verrou ; aucune marque « Déplacement en cours » ; rien ne distinguait l'ancienne place de la proposition. |
| Annuler | `portal/agenda/use-cancellation.ts` : `kind: 'cancelLesson'`, motif + commentaire, `reread` sur `VERSION_CONFLICT` | `test/individual-cancellation.test.ts`, `test/lesson-planning.test.ts` (`CANCEL_LESSON`) | Dialogue verrouillé jusqu'à la réponse ; la leçon disparaissait de la vue au rechargement sans état intermédiaire ; aucun moyen de voir qu'une annulation était demandée. |
| Répondre à une demande de leçon | `portal/agenda/lesson-request-card.tsx` : accepter = déplacer ou annuler avec `changeRequestId` ; refuser = `refuseLessonChangeRequest` via `useCommandRunner` | `test/lesson-change-model.test.ts` | Refus sur le coureur unique de la fiche ; pas de double appui protégé autrement que par `busy`. |
| Projection agenda | `console/agenda-projection.ts` : `agendaDays`, `agendaCounts`, `agendaCountLabel`, `agendaReadStatus` | `test/agenda-projection.test.ts` (9 cas) | Ne connaissait que les faits de l'école : aucune intention, aucune marque, aucune identité logique pour un déplacement. |
| Clés de conflit | `command-conflicts.ts` : `planning` pour `createLesson`, `moveLesson`, `cancelLesson` (et les cours) | `test/command-conflicts.test.ts`, `test/lesson-planning.test.ts` | Conservateur et voulu : voir « Décisions » ci-dessous. |
| Renvoi d'une demande incertaine | `command-store.ts` (`pendingActions`), panneau `portal/runtime/pending-requests.tsx` | `test/command-store-code.test.ts` | « Renvoyer la même demande » proposé sans condition d'expiration, y compris pour un créneau passé. |

Aucune autre surface web ne possède ces commandes : la recherche `createLesson|moveLesson|cancelLesson` ne trouve que `portal/agenda/**` (et le transport synthétique de l'aperçu, non versionné en production). Le dossier élève et « Aujourd'hui » ne font que lire.

## Étape 2 — ce qui change

### Projection pure

- `client/console/agenda-intentions.ts` (nouveau) : `LessonIntention` (`lesson-create`, `lesson-move`, `lesson-cancel`), `PlannedLessonDraft` (saisie + créneau voulu), `agendaMarkLabels` (`Planification en cours`, `Déplacement en cours`, `Nouveau créneau proposé`, `Annulation en cours`), `visibleIntentions`, `stillFollowed`, `PROVISIONAL_LESSON`, `desiredSlotOf`, `lessonResendAllowed`, `lessonResendReason`.
- `client/console/agenda-projection.ts` : `agendaDays` accepte `intentions` ; chaque événement porte une `logicalKey` et, pour une leçon, une `mark` et un drapeau `provisional`. Une création est une ligne `pending:<opération>` (`schoolId: ''`, `version: 0`, non ouvrable) ; un déplacement garde le fait confirmé à sa place d'origine (`moving`) et marque la proposition à la cible (`move-proposal`), les deux partageant `lesson:<id>` ; une annulation demandée garde la leçon (`cancelling`). `agendaCounts` compte les identités logiques distinctes : une leçon déplacée ne compte jamais deux fois. `agendaFacts` ne rend que les faits confirmés (aucune création provisoire, aucune proposition), pour tout aperçu, compteur ou temps de formation.
- Après confirmation (réponse vérifiée ou reçu), l'intention reste projetée sans marque jusqu'à une lecture plus récente ; un déplacement confirmé n'affiche plus l'ancienne place.

### Voie de commandes

- `portal/agenda/use-lesson.ts` : l'éditeur passe de `useCommandRunner` à `useCommandLane`. Dès que le magasin conserve la demande, `onQueued` est appelé : le dialogue est rendu à la consultation, la saisie part dans `drafts` (mémoire seulement, renouvelée avec le compte, l'école, le rattachement et l'époque). Un refus rend `onRefused` avec la saisie et la raison. Un double appui est refusé sur place (`lane.start` par étiquette) ; un créneau passé n'est plus soumis (`interval` nul → problème explicite).
- `portal/agenda/use-cancellation.ts` : même voie, étiquette `lesson:<id>:cancel`. La confirmation se ferme dès l'admission, la leçon reste marquée « Annulation en cours » ; un refus rouvre la confirmation avec le motif et le commentaire saisis.
- `portal/agenda/lesson-request-card.tsx` : le refus d'une demande de l'élève passe par la voie (étiquette `request:<id>:refuse`). Son dialogue reste ouvert jusqu'à la réponse : sa raison n'a pas d'autre endroit où s'afficher ; ce n'est pas une des trois commandes de planification.
- `portal/agenda/use-lesson-intentions.ts` : intentions lues dans `drafts`, confirmées repérées dans `useCommandSnapshot().confirmations`, filtrées par les demandes que le magasin suit encore et par la date de la dernière lecture.

### Écrans

- `portal/agenda/use-agenda.ts`, `agenda-page.tsx`, `agenda.css` : l'agenda projette les intentions ; chaque marque est un texte visible **et** un libellé accessible (concaténé à `aria-label`) ; une ligne provisoire est un `div` non cliquable (`role="group"`), jamais un bouton qui ouvrirait une leçon inexistante. Bandeau « Reprendre la saisie » sur l'agenda pour une création ou un déplacement refusé, avec la raison ; « Reprendre la saisie » rouvre le formulaire sur la leçon concernée avec la saisie refusée. Un refus `VERSION_CONFLICT`, `LESSON_CLOSED` ou `LESSON_STARTED` déclenche une relecture silencieuse (les données affichées restent, la sélection ne bouge pas).
- `portal/agenda/lesson-workspace.tsx` : la fiche affiche « Déplacement en cours » ou « Annulation en cours » ; « Modifier la leçon » est désactivé pendant une annulation ou un déplacement demandé.
- `portal/pilotage/dashboard-appointments.tsx` + `appointments.ts` : marques sur les seuls rendez-vous déjà listés (`agendaFacts` retire toute ligne provisoire et toute proposition), en badge texte. Aucun compteur, lien ou statistique du pilotage n'est modifié.
- `portal/runtime/pending-requests.tsx` : « Renvoyer la même demande » disparaît pour une création ou un déplacement dont l'horaire voulu est passé, avec la raison courte « L'horaire demandé est passé : vérifiez le résultat ou arrêtez le suivi. » ; « Vérifier le résultat » et « Arrêter le suivi » restent. Tout autre type de commande garde son comportement.

### Décisions

- **`command-conflicts.ts` n'est pas modifié.** Ajouter `planning:lesson:<id>` aurait détaché les leçons des clés `planning:availability:<moniteur>:…` : une leçon pourrait alors partir pendant qu'un horaire est suivi, ce que `test/command-conflicts.test.ts` (« la planification reste commune ») et `test/lesson-planning.test.ts` (`commandConflictKeys === ['planning']`) exigent encore. La règle « la planification attend tous les horaires » est donc conservée, et deux planifications de la même école restent ordonnées : la voie libère le dialogue et la consultation, pas une seconde écriture simultanée.
- **Un nouvel horaire est une nouvelle intention** : chaque soumission construit une nouvelle commande (nouvelle `operationId`) ; aucune clé n'est réutilisée avec un autre corps.
- **Pas de route API nouvelle** : les routes `lessons`, `lessons/availability`, `lessons/:id/move`, `lessons/:id/cancel`, `lesson-change-requests/:id/refuse` existaient déjà (`server/school-routes.ts`, inchangé).

## Preuve par critère

| Critère #109 | Preuve |
| --- | --- |
| Sous latence 15 s : retour visuel immédiat, consultation possible, demande retrouvable ; double appui sans doublon | `test/agenda-lane.test.ts` : « un double appui n'envoie qu'une requête » (une seule requête, même `Idempotency-Key`, deux étiquettes refusées) ; la demande conservée laisse l'intention suivie par le magasin (`phase: uncertain`) et l'agenda la projette (`test/agenda-intentions.test.ts`, création provisoire). Latence réelle de 15 s non rejouée dans un navigateur : NOT_EXECUTED. |
| Deux utilisateurs sur le même créneau : jamais deux réservations définitives côté client | La projection n'ajoute aucune réservation : une création est `provisional`, `schoolId: ''`, `version: 0`, non ouvrable ; le serveur arbitre (`SLOT_CONFLICT`, testé comme refus sans confirmation dans `agenda-lane.test.ts`). Recette à deux comptes : NOT_EXECUTED. |
| Réponse perdue après commit, déplacement deux fois, annulation concurrente, GET échoué après confirmation | `agenda-lane.test.ts` : réponse perdue puis reçu confirmé sans seconde écriture (`calls` = un seul POST puis un GET) ; un refus ne laisse rien à suivre ; `test/command-lane.test.ts` (socle, inchangé) pour la reprise même clé/corps/version. Déplacement deux fois : la seconde demande est refusée localement (`LOCAL_COMMAND_CONFLICT`, clé `planning`). Annulation concurrente et GET échoué : comportement du magasin inchangé, non rejoués ici. |
| Reprise après relance, changement d'école, expiration : aucun rejeu silencieux d'une ancienne réservation | `test/agenda-intentions.test.ts` (« renvoi d'une planification dont l'horaire est passé ») : créneau futur renvoyable, créneau passé non renvoyable, commande restaurée sans corps non renvoyée, autres types inchangés. Changement de compte/école : la voie est détruite avec la portée (`useCommandLane`, testé dans `test/command-lane.test.ts`), les intentions vivent dans `drafts` renouvelés avec la portée. |
| Agenda, Aujourd'hui et dossier cohérents ; aucun démarrage GPS ni état financier fabriqué | Une seule projection (`agendaDays`) alimente l'agenda et les « Prochains rendez-vous » ; le tableau de bord ne montre que les marques des faits listés (`agendaFacts`). Aucun prix, aucun droit, aucun démarrage n'est créé par une intention : la fiche d'une ligne provisoire n'existe pas (non ouvrable) et les totaux passent par `agendaFacts`. Dossier élève : lit l'école, inchangé. |
| Création : identité locale stable raccordée au vrai ID, aucun démarrage dépendant | L'identité provisoire est `pending:<operationId>` ; elle n'est jamais présentée comme un identifiant de l'école et aucune action ne s'y attache. Le raccordement au vrai ID se fait par la relecture après confirmation (révision du magasin), pas par une écriture locale. |
| Déplacement : ancien fait conservé et proposition distinguée, jamais compté deux fois | `test/agenda-intentions.test.ts` : « garde le fait confirmé à sa place d'origine et marque la proposition à la cible », « ne compte jamais deux fois dans les totaux de la semaine » (2 lignes, 1 leçon comptée), « après confirmation, la position confirmée est la cible ». |
| Annulation : ne pas libérer un créneau partagé ni déclencher remboursement/notification depuis le client | `test/agenda-intentions.test.ts` : la leçon reste, marquée, la journée n'est pas vide, elle compte toujours. Le web n'appelle aucun remboursement ni notification (aucune route de ce type dans `school-routes.ts`). |
| Conflit : garder les choix et présenter la proposition refusée avec solution de modification, sans restaurer un ancien agenda | Bandeau « Reprendre la saisie » (création, déplacement) et réouverture de la confirmation (annulation) avec la saisie ; les autres rendez-vous restent (`visibleIntentions` : une demande non suivie n'est plus projetée, les faits restent) ; relecture silencieuse sur version/leçon fermée. |
| Marques lisibles sans la couleur seule | `agendaMarkLabels` rendus en texte dans l'agenda (`span.agenda-event-mark`) et dans l'aperçu (`Badge`), et ajoutés à `aria-label` des boutons d'événement. Vérification visuelle et VoiceOver : NOT_EXECUTED. |
| Aucune intention provisoire dans les statistiques ni le temps de formation | `agendaFacts` exclut création provisoire et proposition ; les statistiques du pilotage viennent des mesures serveur (`pilotage/metrics-api.ts`), jamais de la projection ; aucun total client n'est calculé à partir d'un événement provisoire (test « aucune intention provisoire dans un total »). |

## Non fait, non prouvé

- Aucun serveur réel, aucune base PostgreSQL : `apps/api` non lancé, les tests d'intégration API ne sont pas relancés. Toutes les preuves de voie utilisent un transport simulé et le vrai magasin de commandes.
- Aucun parcours dans Edge/Playwright sur l'aperçu synthétique pour cette tâche, aucune capture, aucun chronométrage : NOT_EXECUTED. Les 15 s de latence ne sont donc pas mesurés à l'écran.
- VoiceOver, appareil, IPA, déploiement, homelab : NOT_EXECUTED.
- La clé de conflit reste `planning` (décision ci-dessus) : deux planifications simultanées de la même école restent ordonnées.
- Le dialogue de refus d'une demande de l'élève reste ouvert jusqu'à la réponse (sa raison n'a pas d'autre emplacement) ; ce n'est pas l'un des trois dialogues de planification.
- Le renvoi d'une demande incertaine reste proposé par le panneau générique pour tous les autres types de commande, et par le magasin lui-même (`pendingActions` non modifié) ; seule la surface du panneau applique l'expiration des leçons.
- L'aperçu (« Prochains rendez-vous ») ne montre jamais de ligne provisoire : décision d'affichage des marques seulement, sur autorisation.
- Aucune mesure de performance, aucun test de charge ; aucun test de composant React (le projet n'a ni `@testing-library` ni environnement DOM) : les preuves d'écran reposent sur le typage, la lecture du code et les fonctions pures testées.

## Vérifications exécutées (3 novembre 2026)

| Vérification | Résultat |
| --- | --- |
| `npm ci` dans `apps/web` | PASS (153 paquets ; avertissement `EBADENGINE` : Node 26.8.1 installé, `engines` demande `>=24 <25` ; ce n'est pas une erreur) |
| `npm run typecheck` dans `apps/web` | PASS |
| `npm run test:unit` dans `apps/web` | PASS : 66 fichiers, 686 tests réussis, 1 échec attendu (`test.fails`) |
| Tests ajoutés | `test/agenda-intentions.test.ts` (14), `test/agenda-lane.test.ts` (7) |
| Référence annoncée avant travail | 64 fichiers, 663 réussis, 1 échec attendu. Les deux fichiers ajoutés portent 21 cas : le reste de la suite en compte donc 665, soit 2 de plus que la référence — écart venu de la base `34d4c01a` (fusions du lot A postérieures au document), non mesuré séparément. |
| Tests `apps/api` et PostgreSQL | NOT_EXECUTED (base non fournie, `apps/api` non modifié) |
| Parcours navigateur, latence réelle, VoiceOver, appareil | NOT_EXECUTED |

`command-conflicts.ts`, `command-store.ts`, `command-lane.ts`, `command-core.ts`, `school-routes.ts`, `apps/api` et `apps/ios` ne sont pas modifiés.
