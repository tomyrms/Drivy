# Matrice de couverture écran × rôle × action (#131, étape 1)

État lu : `17b6b667f84135b912927a35ec6c2b6df9ccdaf0` (`master`, 3 novembre 2026 ; branche de travail `tomyrms/lotc-matrice-131`).
Document de constat : aucun code applicatif modifié. Les actions d'écriture sont rattachées à leur issue propriétaire ; une
action sans émetteur réel est notée **absente**, jamais inventée pour remplir le tableau. Une information absente du code est
écrite « non trouvé ».

## 1. Méthode d'inventaire et preuve d'exhaustivité

- Projet Codebase Memory indexé par chemin absolu : `drivy-lotc-matrice-131`
  (`index_repository`, mode `moderate`, `status: indexed`, 38 290 nœuds, 162 566 arêtes, 18 fichiers à analyse partielle,
  1 fichier non analysable : `Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml`, hors périmètre de cette matrice).
- Requêtes Codebase Memory utilisées : `get_architecture(aspects: ["routes"])` sur `apps/api/src`, `search_graph("createCommand")`,
  `search_graph("useCommandLane")`, `search_graph("SchoolCommandOutbox")`, `search_graph("SchoolHomeTab")`,
  `get_file_outline` sur `apps/web/client/portal/pages.tsx`, `apps/web/client/console/sections.ts`,
  `apps/ios/Drivy/SchoolUI/SchoolHomeView.swift`, `apps/ios/Drivy/SchoolUI/SchoolRootView.swift`.
- Exhaustivité **web**, croisement de trois lectures :
  1. routeur réel : `apps/web/client/main.tsx:49-76` (six adresses d'entrée, une adresse console, page inconnue) ;
  2. registre des pages : `apps/web/client/portal/pages.tsx:8-31` (20 sections) et `apps/web/client/console/sections.ts:1`
     (20 clés) ; navigation : `apps/web/client/portal/destinations.ts:9-31` ;
  3. `grep` textuel `useCommandRunner|useCommandLane|commandStore.submit|createCommand` sur `apps/web/client/portal`
     (liste des surfaces d'écriture) et `readSchool|readAll|readPage` (surfaces de lecture).
- Exhaustivité **iOS**, croisement de trois lectures :
  1. onglets par rôle : `apps/ios/Drivy/SchoolUI/SchoolHomeView.swift:188-215` (moniteur/administration) et `:391-408` (élève) ;
  2. feuilles et présentations : `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:176-237` ;
  3. `grep` textuel `Button(` sur chaque écran de `apps/ios/Drivy/*UI` et `kind: .` (commandes de la file) sur
     `apps/ios/Drivy` — chaque ligne d'écriture du tableau cite le site d'émission ou de préparation de la commande.
- Registre des routes d'écriture réutilisé, non refait : `docs/implementation/registre-commandes-106.md` (commit `efddf096`,
  141 routes d'écriture, 134 persistantes, 60 commandes web, 49 types de commande iOS). Chaque ligne ci-dessous qui s'appuie
  sur ce registre pour les droits, la version ou l'idempotence a été revérifiée au SHA courant au fichier:ligne cité.
- Contrôle des citations : script exécuté hors dépôt (voir §8) — chaque `fichier:ligne`
  du document doit exister et désigner une ligne non vide au SHA courant.

## 2. Définitions L/R/O/G (recopiées de #105, section 1)

| Mode | Effet local | Exemples |
|---|---|---|
| **L — local** | Effet définitif sur cet appareil, sans réseau inutile. | Onglets, filtres, texte, thème, caméra/replay déjà chargés. |
| **R — lecture rapide** | Donnée déjà autorisée présentée, fraîcheur visible, revalidation ciblée. | Agenda, dossiers, progression, catalogue, historiques. |
| **O — mutation optimiste réversible** | Projection immédiatement affichée avec état provisoire ; rejet retire/rebase seulement cette intention. | Nom/photo locale, préférence, réaction, souhait, présence saisie provisoirement. |
| **G — action engagée/sensible** | Demande et progression visibles immédiatement, navigation libérée lorsque sûr ; fait métier confirmé seulement par preuve serveur. | Créneau, inscription/dernière place, démarrage autorisé, publication, règlement, droit, consentement, suppression serveur. |

## 3. Légende des colonnes

- **Rôle** : rôle de l'écran au moment de l'action. Côté web, la console n'ouvre que pour `ADMIN`
  (`apps/web/client/console/access-reader.ts:32`) : `INSTRUCTOR` et `LEARNER` sont refusés avant toute page
  (`apps/web/client/portal/portal-console.tsx:52-56`), même quand la route serveur accepte aussi le moniteur.
- **Autorité · version** : contrôle serveur attendu (`ADMIN`, `INSTRUCTOR`, `LEARNER`, droit nommé) et garde de version
  (`If-Match`, version de ressource, version d'école, `operationId`).
- **Source locale** : état qui porte la projection ou l'intention (fichier:ligne).
- **Persistance** : ce qui survit à un rechargement ou à une fermeture d'app. « mémoire » = perdu au rechargement.
- **Confirmation** : `réponse` (le serveur a répondu), `réponse/reçu` (réponse ou reçu AP72), `—` (lecture seule).
- **Refus** : `saisie gardée`, `dialogue rouvert`, `ligne marquée`, `—`.
- **Inconnu** : `panneau` (panneau de demandes en attente en tête de page), `incertain` (état incertain explicite avec
  vérification/renvoi), `—`.
- **Issue** : ticket propriétaire parmi #104, #106–#130, suivi de son état (`fermée` / `ouverte`). `#106` (ouverte) est le
  socle technique quand aucune fonctionnalité ne possède l'action ; il n'est pas compté comme propriétaire métier dans la
  synthèse.
- **Preuve** : fichier de test existant, ou « non prouvé ».

## 4. Web (`apps/web/client`)

### 4.1 Entrée — `/app`, `/app/invitation` (`apps/web/client/main.tsx:71-73`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W01 | visiteur | Vérifier un code d'accès (aperçu) | G | `POST /app/bff/access-code` → `POST /v1/access-codes/preview` | public · limiteur par IP | `apps/web/client/portal/entry/use-account-entry.ts:59` | aucune | aucune | réponse | message, saisie gardée | — | #120 (ouverte) | non prouvé |
| W02 | visiteur | Se connecter (mot de passe) | G | BFF `password-login` | visiteur · CSRF | `apps/web/client/portal/entry/use-account-entry.ts:81` | aucune | session relue après (`apps/web/client/portal/entry/use-entry-session.ts:56`) | réponse puis `/me` | message, champs gardés | — | #120 (ouverte) | `apps/web/test/protocol-session.test.ts` |
| W03 | visiteur | Créer un compte avec le code | G | `POST /v1/accounts` (BFF) | public · limiteur | `apps/web/client/portal/entry/use-account-entry.ts:101` | aucune | compte créé chez le fournisseur | réponse | message, champs gardés | — | #120 (ouverte) | non prouvé |
| W04 | compte | Accepter une invitation reçue | G | `POST /v1/invitations/accept` | invitation + adhésion · `operationId` | `apps/web/client/portal/entry/use-entry-session.ts:206` | mémoire (jeton en fragment, `main.tsx:16`) | aucune | réponse | `incertain` + « Retrouver la demande » | `incertain` (`apps/web/client/portal/entry/entry-page.tsx:37`) | #120 (ouverte) | non prouvé |
| W05 | compte | Fermer une invitation non voulue | G | `POST /v1/invitations/clear` | authentifié | `apps/web/client/portal/entry/use-entry-session.ts:189` | — | aucune | réponse | message | — | #120 (ouverte) | non prouvé |
| W06 | compte | Se déconnecter | G | BFF `endSession` | authentifié | `apps/web/client/portal/entry/use-entry-session.ts:175` | — | aucune | réponse | message | — | #120 (ouverte) | non prouvé |
| W07 | visiteur | Récupérer l'accès | G | `POST /app/bff/account-recovery/start` | public | `apps/web/client/portal/entry/recovery-page.tsx:36` | — | aucune | réponse | message | — | #120 (ouverte) | `apps/web/test/account-recovery.test.ts` |
| W08 | compte | Choisir une école | R | `GET /v1/me` | authentifié | `apps/web/client/portal/entry/use-entry-session.ts:81` | mémoire | `/me` lisible | — | — | — | #120 (ouverte) | `apps/web/client/portal/entry/entry-model.test.ts` |

### 4.2 Ouverture d'école — `/app/ouvrir`, `/app/operateur` (`main.tsx:65-67`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W09 | porteur de lien | Créer l'école depuis le lien | G | `POST /v1/school-openings` | lien consommé · `operationId` + reçu | `apps/web/client/portal/opening/use-school-opening.ts:79` | — | lien valide, non expiré | réponse/reçu | message, saisie gardée | `incertain` exposé (`:84`) | #120 (ouverte) | `apps/web/test/school-opening-model.test.ts`, `apps/web/test/school-opening-bff.test.ts` |
| W10 | porteur de lien | Reprendre le résultat d'une ouverture | G | `GET /v1/school-openings` (`opening/result`) | lien · reçu par opération | `apps/web/client/portal/opening/use-school-opening.ts:92` | — | aucune | réponse | message | — | #120 (ouverte) | `apps/web/test/school-opening-bff.test.ts` |
| W11 | opérateur | Émettre un lien d'ouverture | G | `POST /v1/operator/school-opening-links` | opérateur · `operationId` | `apps/web/client/portal/opening/use-school-opening.ts:107` | — | aucune | réponse | message | — | #120 (ouverte) | `apps/web/test/school-opening-bff.test.ts` |
| W12 | opérateur | Révoquer un lien d'ouverture | G | `POST /v1/operator/school-opening-links/:id/revoke` | opérateur · `operationId` par acteur | `apps/web/client/portal/opening/use-school-opening.ts:113` | — | aucune | réponse | message | — | #120 (ouverte) | `apps/web/test/school-opening-bff.test.ts` |

### 4.3 Console de gestion — `/app/gestion/:schoolId/:section` (accès)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W13 | ADMIN | Ouvrir la console d'une école | R | `GET /v1/me` + `GET /v1/schools/:id` | ADMIN · adhésion + époque | `apps/web/client/console/access-reader.ts:26` | cache de lecture mémoire (`apps/web/client/console/context.ts:113`) | `/me` et école cohérents (`access-reader.ts:35`) | — | — | panneau | #107 (fermée) | `apps/web/test/console-access.test.ts` |

Refus du portail pour un compte non administration : `apps/web/client/console/access-reader.ts:32` → `apps/web/client/portal/portal-console.tsx:52-56`
(« La gestion de l'école demande le rôle Administration »). Aucune page console n'est montée avant ce contrôle.

### 4.4 Pilotage — Tableau de bord et Statistiques (`pages.tsx:10-11`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W14 | ADMIN | Lire le tableau de bord | R | `GET …/metrics`, `…/metrics/definitions`, `…/metrics/series` | ADMIN + `VIEW_SCHOOL_METRICS` / `VIEW_FINANCIAL_METRICS` | `apps/web/client/portal/pilotage/metrics-api.ts:42` | cache mémoire | aucune | — | — | — | #107 (fermée) | `apps/web/test/metrics-bff.test.ts`, `apps/web/client/portal/pilotage/dashboard-models.test.ts` |
| W15 | ADMIN | Changer période, onglet, moniteur | L | — | — | `apps/web/client/portal/pilotage/dashboard-page.tsx:36` (état d'URL, `apps/web/client/console/route.ts:59-63`) | URL | aucune | — | — | — | #107 (fermée) | `apps/web/client/portal/pilotage/dashboard-models.test.ts` |
| W16 | ADMIN | Lire le détail d'une mesure | R | `GET …/metrics/details` | droit du domaine + `metrics_gate` | `apps/web/client/portal/pilotage/details-api.ts:19` | cache mémoire | période lue | — | — | — | #107 (fermée) | `apps/web/client/portal/pilotage/detail-models.test.ts` |
| W17 | ADMIN | Exporter une mesure en CSV | G | `POST …/metrics/exports` | droit export + `metrics_gate` | `apps/web/client/portal/pilotage/details-api.ts:52` | blob en mémoire (`:75`) | mesure affichée | réponse (fichier) | message | — | #106 (ouverte) | `apps/web/test/metrics-bff.test.ts` |

### 4.5 Préparation de l'école — section `apercu` (`pages.tsx:12`, `overview-page.tsx:37`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W18 | ADMIN | Lire les prochaines actions | R | `GET …/setup-draft/next-actions` | ADMIN | `apps/web/client/portal/overview/overview-page.tsx:62` | cache mémoire | brouillon de préparation | — | — | — | #123 (fermée) | `apps/web/client/portal/setup/setup-guide-model.test.ts` |
| W19 | ADMIN | Enregistrer une étape et continuer | O | `PUT …/setup-draft` | ADMIN · `If-Match` brouillon | `apps/web/client/portal/setup/use-setup-guide.ts:55` | file coalescée mémoire (`apps/web/client/portal/setup/setup-save-queue.ts`) | version du brouillon | réponse/reçu | `saisie gardée`, conflit relu (`:67`) | panneau (`:261`) | #123 (fermée) | `apps/web/client/portal/setup/setup-save-queue.test.ts` |
| W20 | ADMIN | Relire le résumé avant adoption | R | `GET …/setup-draft/preview` | ADMIN · version de brouillon exigée | `apps/web/client/portal/setup/use-setup-guide.ts:230` | aucune | brouillon enregistré | — | message, résumé refusé (`:231`) | — | #123 (fermée) | `apps/web/client/portal/setup/setup-review-gate.test.ts` |
| W21 | ADMIN | Adopter / activer l'école | G | `POST …/setup-draft/complete` | ADMIN · brouillon + école + configuration | `apps/web/client/portal/setup/use-setup-guide.ts:271` | aucune | résumé relu, digest | réponse/reçu | message, brouillon gardé (`:258-262`) | panneau | #123 (fermée) | `apps/web/client/portal/setup/setup-review-gate.test.ts` |

### 4.6 Agenda — section `agenda` (`pages.tsx:13`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W22 | ADMIN | Lire l'agenda (leçons, cours, annuaire) | R | `GET …/lessons`, `…/course-series`, `…/members`, `…/learners` | ADMIN | `apps/web/client/portal/agenda/use-agenda.ts:105` | cache de lecture par période (`apps/web/client/console/period-cache.ts`) | aucune | — | — | — | #108 (fermée) | `apps/web/test/agenda-projection.test.ts`, `apps/web/test/period-cache.test.ts` |
| W23 | ADMIN | Créer une leçon | O | `POST …/lessons` | ADMIN/INSTRUCTOR · contexte + créneau, `operationId` | `apps/web/client/portal/agenda/use-lesson.ts:147` (intention `:155-157`) | intention mémoire (`apps/web/client/console/agenda-intentions.ts`) | lectures complètes (formations, affectations, politiques) + créneau vérifié (`:119-139`) | réponse/reçu | `dialogue rouvert` avec la saisie (`:164`) | panneau | #109 (fermée) | `apps/web/test/agenda-lane.test.ts`, `apps/web/test/lesson-planning.test.ts` |
| W24 | ADMIN | Déplacer une leçon | O | `POST …/lessons/:id/move` | ADMIN/INSTRUCTOR · `If-Match` leçon | `apps/web/client/portal/agenda/use-lesson.ts:147` | intention mémoire | version de la leçon + créneau vérifié | réponse/reçu | dialogue rouvert | panneau | #109 (fermée) | `apps/web/test/agenda-lane.test.ts` |
| W25 | ADMIN | Annuler une leçon | O | `POST …/lessons/:id/cancel` | ADMIN/INSTRUCTOR · `If-Match` leçon | `apps/web/client/portal/agenda/use-cancellation.ts:43` | intention mémoire | version leçon, règles d'annulation (`individual-cancellation`) | réponse/reçu | dialogue rouvert | panneau | #109 (fermée) | `apps/web/test/agenda-lane.test.ts`, `apps/web/test/individual-cancellation.test.ts` |
| W26 | ADMIN | Refuser une demande de changement de l'élève | G | `POST …/lesson-change-requests/:id/refuse` | ADMIN/INSTRUCTOR + `lesson_change_staff` | `apps/web/client/portal/agenda/lesson-request-card.tsx:65` | aucune | demande encore en attente | réponse | message | panneau | #109 (fermée) | `apps/web/test/lesson-change-model.test.ts` |
| W27 | ADMIN | Ouvrir une leçon ou un cours | R | `GET …/lessons/:id`, `…/course-series/:id/sheet` | ADMIN | `apps/web/client/portal/agenda/use-lesson.ts:29` | cache mémoire | aucune | — | — | — | #107 (fermée) | `apps/web/test/console-agenda-learners.test.ts` |
| W28 | ADMIN | Filtrer jour/semaine/moniteur/élève | L | — | — | `apps/web/client/portal/agenda/agenda-page.tsx:56-64` | URL | aucune | — | — | — | #108 (fermée) | `apps/web/client/portal/agenda/calendar-layout.test.ts` |
| W29 | ADMIN | Enregistrer les règles des cours | G | `PUT …/course-policy` | ADMIN/INSTRUCTOR + droit cours · version politique | `apps/web/client/portal/courses/course-policy-dialog.tsx:31` | aucune | catalogue lu | réponse | message, saisie gardée | panneau | #127 (fermée) | `apps/web/test/course-model.test.ts` |

### 4.7 Disponibilités et absences — sections `disponibilites`, `absences` (`pages.tsx:17-18`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W30 | ADMIN | Lire horaires et absences | R | `GET …/availability-rules`, `…/closures` | ADMIN | `apps/web/client/portal/availability/use-schedule.ts` (lecture `useLoad`) | cache mémoire | aucune | — | — | — | #110 (fermée) | `apps/web/client/portal/availability/schedule-projection.test.ts` |
| W31 | ADMIN | Ajouter ou modifier un horaire | O | `POST …/availability-rules`, `PUT …/availability-rules/:id` | ADMIN/INSTRUCTOR + droit du moniteur visé · `If-Match` règle | `apps/web/client/portal/availability/use-schedule-commands.ts:76` | intention mémoire | moniteur choisi, aucun rendez-vous déplacé | réponse/reçu | `saisie gardée` (`:69`) | panneau | #110 (fermée) | `apps/web/client/portal/availability/schedule-projection.test.ts` |
| W32 | ADMIN | Retirer un horaire | O | `POST …/availability-rules/:id/remove` | idem | `apps/web/client/portal/availability/use-schedule-commands.ts:96` | intention mémoire | rendez-vous restants vérifiés côté serveur | réponse/reçu | dialogue rouvert (`:109-117`) | panneau | #110 (fermée) | `apps/web/client/portal/availability/schedule-projection.test.ts` |
| W33 | ADMIN | Ajouter une absence | O | `POST …/closures` | idem | `apps/web/client/portal/availability/use-schedule-commands.ts:89` | intention mémoire | dates valides, fuseau de l'école | réponse/reçu | saisie gardée | panneau | #110 (fermée) | `apps/web/client/portal/availability/schedule-projection.test.ts` |
| W34 | ADMIN | Retirer une absence | O | `POST …/closures/:id/remove` | idem | `apps/web/client/portal/availability/use-schedule-commands.ts:96` | intention mémoire | version de la fermeture | réponse/reçu | dialogue rouvert | panneau | #110 (fermée) | `apps/web/client/portal/availability/schedule-projection.test.ts` |

### 4.8 Élèves — section `eleves` (`pages.tsx:14`, rubriques `learner-page.tsx:49-54`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W35 | ADMIN | Lire l'annuaire et un dossier | R | `GET …/learners`, `…/trainings`, `…/assignments`, `…/permit-checks` | ADMIN | `apps/web/client/portal/learners/learner-controller.ts:93-113` | cache mémoire | aucune | — | — | — | #116 (fermée) | `apps/web/client/portal/learners/learner-projection.test.ts` |
| W36 | ADMIN | Ouvrir une formation à un élève | O | `POST …/trainings` | ADMIN/INSTRUCTOR | `apps/web/client/portal/learners/learner-controller.ts:201` | intention mémoire | offres disponibles, dossier lisible | réponse/reçu | `saisie gardée`, réouverture (`:269`) | panneau | #116 (fermée) | `apps/web/client/portal/learners/learner-projection.test.ts` |
| W37 | ADMIN | Affecter un moniteur | O | `POST …/trainings/:id/assignments` | ADMIN | `apps/web/client/portal/learners/learner-controller.ts:212` | intention mémoire | formation active, dossier complet | réponse/reçu | saisie gardée | panneau | #116 (fermée) | `apps/web/client/portal/learners/learner-projection.test.ts` |
| W38 | ADMIN | Changer l'état d'une formation | O | `POST …/trainings/:id/transition` | ADMIN · `If-Match` formation | `apps/web/client/portal/learners/learner-controller.ts:231` | intention mémoire | transitions permises | réponse/reçu | saisie gardée | panneau | #116 (fermée) | `apps/web/client/portal/learners/learner-projection.test.ts` |
| W39 | ADMIN | Terminer une affectation | O | `POST …/trainings/:id/assignments/:id/end` | ADMIN · `If-Match` affectation | `apps/web/client/portal/learners/learner-controller.ts:238` | intention mémoire | affectation ouverte | réponse/reçu | saisie gardée | panneau | #116 (fermée) | `apps/web/client/portal/learners/learner-projection.test.ts` |
| W40 | ADMIN | Consigner un contrôle de permis | O | `POST …/trainings/:id/permit-checks` | ADMIN/INSTRUCTOR + `permit_review_allowed` | `apps/web/client/portal/learners/learner-controller.ts:244` | intention mémoire | formation active | réponse/reçu | saisie gardée | panneau | #117 (fermée) | `apps/web/client/portal/learners/learner-projection.test.ts` |
| W41 | ADMIN | Archiver ou restaurer un dossier | O | `POST …/learners/:id/archive\|restore` | ADMIN · `If-Match` dossier | `apps/web/client/portal/learners/learner-controller.ts:250` | intention mémoire | motif saisi | réponse/reçu | saisie gardée | panneau | #116 (fermée) | `apps/web/client/portal/learners/learner-projection.test.ts` |
| W42 | ADMIN | Compléter le profil administratif | G | `PATCH …/learners/:id/administrative-profile` | ADMIN/INSTRUCTOR/LEARNER selon champs · `If-Match` profil | `apps/web/client/portal/learners/dossier-controller.ts:98` | aucune | profil relu, conflit bloquant (`:82`) | réponse | message, saisie gardée | panneau | #116 (fermée) | `apps/web/test/profile-completion-model.test.ts` |
| W43 | ADMIN | Créer, modifier, reporter un examen | G | `POST …/trainings/:id/exams`, `POST …/exams/:id/update\|postpone` | ADMIN/INSTRUCTOR + `exam_manage` · version examen | `apps/web/client/portal/learners/learner-exams.tsx:103`, `:106` | aucune | formation active, accompagnement libre | réponse | message, saisie gardée | panneau | #117 (fermée) | `apps/web/test/exam-model.test.ts` |
| W44 | ADMIN | Renseigner ou corriger un résultat d'examen | G | `POST …/exams/:id/result` | ADMIN/INSTRUCTOR + `exam_manage` · `If-Match` examen | `apps/web/client/portal/learners/learner-exams.tsx:141` | aucune | examen commencé | réponse | message | panneau | #117 (fermée) | `apps/web/test/exam-model.test.ts` |
| W45 | ADMIN | Planifier une leçon depuis un dossier | O | `POST …/lessons` | ADMIN/INSTRUCTOR | `apps/web/client/portal/learners/learner-page.tsx:41` → `apps/web/client/portal/agenda/use-lesson.ts:147` | intention mémoire | mêmes dépendances que W23 | réponse/reçu | dialogue rouvert | panneau | #109 (fermée) | `apps/web/test/agenda-lane.test.ts` |

### 4.9 Équipe — section `equipe` (`pages.tsx:15`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W46 | ADMIN | Lire les membres et leurs droits | R | `GET …/members` | ADMIN | `apps/web/client/portal/access/members.ts` (`useMembers`) | cache mémoire | aucune | — | — | — | #122 (fermée) | non prouvé |
| W47 | ADMIN | Modifier rôles et droits d'un membre | G | `PATCH …/members/:id` | ADMIN + réauthentification · `If-Match` adhésion | `apps/web/client/portal/access/access-controller.ts:116` | aucune | version de l'adhésion, motif | réponse | message, brouillon gardé (`:124`) | panneau | #122 (fermée) | non prouvé |
| W48 | ADMIN | Retirer un accès | G | `POST …/members/:id/deactivate` | ADMIN + réauthentification | `apps/web/client/portal/team/team-controller.ts:57` | aucune | motif + accusé, dernier administrateur refusé | réponse | message, motif gardé | panneau | #122 (fermée) | non prouvé |

### 4.10 Invitations — section `invitations` (`pages.tsx:16`, audiences `learners` / `team`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W49 | ADMIN | Lire les invitations | R | `GET …/invitations`, `…/invitation-options` | ADMIN/INSTRUCTOR | `apps/web/client/portal/invitations/use-invitations.ts:72` | cache mémoire | aucune | — | — | — | #121 (fermée) | `apps/web/client/portal/invitations/invitations-model.test.ts` |
| W50 | ADMIN | Créer un code d'invitation | G | `POST …/invitations` (`CODE`) | ADMIN/INSTRUCTOR | `apps/web/client/portal/invitations/use-invitations.ts:175` | code en mémoire seulement (`:56`) | offres ouvertes + moniteur affecté | réponse | `saisie gardée` (`:216`) | panneau, code absent signalé (`:70`) | #121 (fermée) | `apps/web/test/invitation-model.test.ts` |
| W51 | ADMIN | Créer une invitation par e-mail | G | `POST …/invitations` (`EMAIL`) | ADMIN/INSTRUCTOR | `apps/web/client/portal/invitations/use-invitations.ts:179` | aucune | e-mail valide, rôles proposables | réponse | saisie gardée | panneau | #121 (fermée) | `apps/web/test/invitation-model.test.ts` |
| W52 | ADMIN | Renvoyer une invitation | G | `POST …/invitations/:id/resend` | ADMIN/INSTRUCTOR · `If-Match` invitation | `apps/web/client/portal/invitations/use-invitations.ts:184` | nouveau code en mémoire | invitation encore actionnable | réponse | saisie gardée | panneau | #121 (fermée) | `apps/web/test/invitation-model.test.ts` |
| W53 | ADMIN | Révoquer une invitation | G | `POST …/invitations/:id/revoke` | ADMIN/INSTRUCTOR · `If-Match` invitation | `apps/web/client/portal/invitations/use-invitations.ts:189` | aucune | motif saisi | réponse | saisie gardée | panneau | #121 (fermée) | `apps/web/client/portal/invitations/invitations-model.test.ts` |

### 4.11 Formations et tarifs — sections `formations`, `offres`, `referentiels`, `procedures`, `prestations`, `conditions`

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W54 | ADMIN | Lire le catalogue et les versions | R | `GET …/offerings`, `…/curricula`, `…/policy-versions`, `…/formations` | ADMIN | `apps/web/client/portal/formations/formation-controllers.ts` (`useFormationSheet`) | cache mémoire | aucune | — | — | — | #124 (fermée) | `apps/web/client/portal/formations/formations.test.ts` |
| W55 | ADMIN | Enregistrer une rubrique de programme | O | `POST …/formations/programmes` | ADMIN + droit catalogue | `apps/web/client/portal/formations/formation-commands.ts:84` | intention mémoire (`apps/web/client/portal/formations/formation-projection.ts:54`) | version publiée relue, rubrique seule | réponse/reçu | refus par rubrique (`formation-projection.ts:121`) | panneau | #124 (fermée) | `apps/web/test/formation-lane.test.ts`, `apps/web/client/portal/formations/formation-projection.test.ts` |
| W56 | ADMIN | Réviser les conditions partagées | O | `POST …/formations/terms/revise` | ADMIN + droit catalogue | `apps/web/client/portal/pricing/pricing-commands.ts:155` | intention mémoire | tarifs concernés lus | réponse/reçu | saisie gardée | panneau | #124 (fermée) | `apps/web/test/pricing-lane.test.ts` |
| W57 | ADMIN | Lire prestations, tarifs et conditions | R | `GET …/service-products`, `…/formations/tariffs`, `…/commercial-terms` | ADMIN | `apps/web/client/portal/pricing/prestations-page.tsx` (`useLoad`), `apps/web/client/portal/pricing/terms-page.tsx:83` | cache mémoire | aucune | — | — | — | #124 (fermée) | `apps/web/client/portal/pricing/pricing-projection.test.ts` |
| W58 | ADMIN | Enregistrer un tarif | O | `POST …/formations/tariffs` | ADMIN + droit catalogue | `apps/web/client/portal/pricing/pricing-commands.ts:103` | intention mémoire | prestation choisie, date d'effet | réponse/reçu | saisie gardée | panneau | #124 (fermée) | `apps/web/client/portal/pricing/pricing-projection.test.ts` |

### 4.12 Réglages — `configuration`, `confidentialite`, `champs-profil`, `signalements`

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W59 | ADMIN | Lire les coordonnées de l'école | R | `GET …/readiness` + école du contexte | ADMIN | `apps/web/client/portal/settings/school-page.tsx:21` | cache mémoire | école lue à l'ouverture | — | — | — | #123 (fermée) | `apps/web/test/school-bff.test.ts` |
| W60 | ADMIN | Enregistrer les coordonnées | G | `PATCH …/schools/:id` | ADMIN · `If-Match` école | `apps/web/client/portal/settings/school-page.tsx:53` | aucune | version d'école, confirmation d'impact | réponse | message, saisie gardée (`:55-60`) | panneau | #123 (fermée) | `apps/web/test/command-core.test.ts` |
| W61 | ADMIN | Activer ou désactiver les trajets GPS | G | `PUT …/modules` | ADMIN + réauthentification · `If-Match` école | `apps/web/client/portal/settings/privacy-page.tsx:80` | aucune | identité confirmée avant l'envoi (`:73-79`) | réponse | message, dialogue rouvert (`:83-84`) | panneau | #125 (fermée) | `apps/web/test/reauth-bff.test.ts` |
| W62 | ADMIN | Adopter les textes de confidentialité | G | `PUT …/data-policy` | ADMIN · `If-Match` politique | `apps/web/client/portal/settings/privacy-page.tsx:137` | aucune | impact GPS relu avant adoption (`:123`) | réponse | message, texte gardé | panneau | #125 (fermée) | `apps/web/test/data-policy-impact.test.ts` |
| W63 | ADMIN | Publier les informations demandées aux élèves | G | `POST …/profile-field-policies` | ADMIN · `If-Match` école | `apps/web/client/portal/settings/privacy-page.tsx:230` | aucune | textes adoptés (notice) | réponse | message, saisie gardée | panneau | #123 (fermée) | `apps/web/test/privacy-model.test.ts` |
| W64 | ADMIN | Lire et réordonner les signalements | R | `GET …/observation-themes` | ADMIN/INSTRUCTOR + droit signalements | `apps/web/client/portal/signals/signals-page.tsx:31` | brouillon de section mémoire (`:47`) | aucune | — | — | — | #112 (fermée) | `apps/web/test/observation-themes-model.test.ts` |
| W65 | ADMIN | Enregistrer l'ordre et la visibilité des signalements | G | `PUT …/observation-themes` | ADMIN/INSTRUCTOR + droit signalements · `If-Match` thèmes | `apps/web/client/portal/signals/signals-page.tsx:158` | brouillon mémoire | version des thèmes | réponse | conflit relu, brouillon abandonné (`:163-165`) | panneau | #112 (fermée) | `apps/web/test/observation-themes-model.test.ts` |

### 4.13 Trajets — section `trajets` (`pages.tsx:26`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W66 | ADMIN | Lire l'inventaire des trajets | R | `GET …/captures` (page ou liste filtrée) | ADMIN, portée RLS de l'école | `apps/web/client/portal/trips/trips-page.tsx:29-35` | cache mémoire | aucune | — | — | — | #115 (fermée) | non prouvé |
| W67 | ADMIN | Chercher, paginer, ouvrir un dossier | L | — | — | `apps/web/client/portal/trips/trips-page.tsx:26-28`, `:36` | mémoire/URL | aucune | — | — | — | #115 (fermée) | non prouvé |

### 4.14 Préférences personnelles — `/app/preferences` (`main.tsx:62-64`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| W68 | compte | Choisir le thème | L | — | — | `apps/web/client/portal/account/preferences-page.tsx:43` (`theme.ts`) | `localStorage` (thème seul) | aucune | — | — | — | #119 (fermée) | `apps/web/test/theme.test.ts` |
| W69 | compte | Basculer une préférence de notification | O | `PUT /v1/me/notification-preferences` (BFF) | personne · verrou + `If-Match` | `apps/web/client/portal/account/preferences-page.tsx:125` → `apps/web/client/notification-preferences-store.ts:104` | intentions mémoire (`apps/web/client/notification-preferences-store.ts:23`) | personne relue avant écriture (`preferences-page.tsx:82`) | réponse | `incertain` + renvoi, `conflict` + choix (`preferences-page.tsx:131-136`) | `incertain` explicite | #119 (fermée) | `apps/web/test/notification-preferences-store.test.ts` |

## 5. iOS (`apps/ios/Drivy`)

### 5.1 Connexion et entrée (`SchoolSignInLanding`, `SchoolRootView:676-687`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I01 | visiteur | Se connecter (e-mail, mot de passe) | G | fournisseur OIDC (`IdentitySession`) | visiteur | `apps/ios/Drivy/SchoolUI/SchoolSignInLanding.swift:92-95` | jeton en Keychain (`apps/ios/Drivy/Identity/IdentityVault.swift`) | aucune | réponse + `/me` | message, champs gardés | — | #120 (ouverte) | `apps/ios/DrivyTests/IdentityTests.swift`, `apps/ios/DrivyUITests/SchoolSignInFeedbackUITests.swift` |
| I02 | visiteur | Saisir un code d'accès avant connexion | G | `POST …/access-codes/preview` (`SchoolAccountClient`) | public · limiteur | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:380-385` | aucune | aucune | réponse | message, code gardé | — | #120 (ouverte) | `apps/ios/DrivyTests/SchoolJoinIdentityTests.swift` |
| I03 | visiteur | Créer le compte avec le code | G | `POST …/accounts` (`SchoolAccountClient`) | public · limiteur | `apps/ios/Drivy/SchoolJoinUI/SchoolAccessCodeView.swift:125-133` | aucune | aperçu du code accepté | réponse | message, champs gardés | — | #120 (ouverte) | `apps/ios/DrivyTests/SchoolJoinIdentityTests.swift` |
| I04 | visiteur | Récupérer l'accès | G | `SchoolAccountRecoveryClient` | public | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:685` | aucune | aucune | réponse | message | — | #120 (ouverte) | `apps/ios/DrivyTests/SchoolAccountRecoveryTests.swift` |
| I05 | compte | Rejoindre une école par lien | G | `POST …/invitations/accept` (`SchoolJoinClient`) | invitation + adhésion · `operationId` | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:340-346` | journal Keychain (`apps/ios/Drivy/SchoolJoinAPI/SchoolJoinJournal.swift:42`) | lien valide | réponse | message, feuille gardée | reprise du journal | #120 (ouverte) | `apps/ios/DrivyTests/SchoolJoinIdentityTests.swift` |
| I06 | compte | Rejoindre une école par code | G | `POST …/invitations/code/accept` (`SchoolCodeJoinWorkspace`) | invitation + adhésion · `operationId` | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:429-445` | journal Keychain (`apps/ios/Drivy/SchoolJoinAPI/SchoolCodeJoinJournal.swift`) | code valide | réponse | message, code gardé | reprise du journal | #120 (ouverte) | `apps/ios/DrivyTests/SchoolInvitationCodeTests.swift` |
| I07 | porteur de code | Ouvrir une école | G | `POST …/school-openings` (`SchoolOpeningClient`) | code · `operationId` + reçu | `apps/ios/Drivy/SchoolJoinUI/SchoolOpeningView.swift:130` | journal Keychain | code valide | réponse/reçu | message, formulaire gardé | `openingWorkspace.receipt` relu (`SchoolRootView.swift:418-422`) | #120 (ouverte) | `apps/ios/DrivyTests/SchoolJoinIdentityTests.swift` |

### 5.2 Feuille Compte (`SchoolRootView.swift:821-863`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I08 | compte | Ouvrir « Mon profil » | L | — | — | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:299-303`, `:615-620` | aucune | personne lue | — | — | — | #118 (fermée) | `apps/ios/DrivyTests/SchoolProfileWorkspaceTests.swift` |
| I09 | ADMIN, INSTRUCTOR | Ouvrir les invitations | L | — | — | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:484-503` | aucune | école `ACTIVE`, rôle | — | — | — | #121 (fermée) | `apps/ios/DrivyTests/SchoolInvitationWorkspaceTests.swift` |
| I10 | compte | Rejoindre une école | G | voir I05/I06 | — | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:287-294` | — | aucune feuille ouverte | — | — | — | #120 (ouverte) | `apps/ios/DrivyTests/SchoolJoinIdentityTests.swift` |
| I11 | compte | Changer d'école | R | `GET /v1/me` puis école | adhésion · époque | `apps/ios/Drivy/SchoolUI/SchoolHomeView.swift:616-618` (`SchoolChooserSheet`) | aucune | aucun trajet en cours | — | — | — | #120 (ouverte) | `apps/ios/DrivyTests/SchoolWorkspaceTests.swift` |
| I12 | ADMIN | Ouvrir la gestion de l'école sur le web | L | — | ADMIN (`SchoolRootView.swift:322-326`) | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:322` | aucune | école non archivée | — | — | — | #123 (fermée) | non prouvé |
| I13 | compte | Se déconnecter | G | `SchoolPushCenter.sessionEnding` + `identity.signOut` | authentifié | `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:730-739` | purge session + jeton d'appareil | trajet en cours signalé | réponse | message | — | #120 (ouverte) | `apps/ios/DrivyTests/IdentityTests.swift` |

### 5.3 Aujourd'hui — onglet moniteur (`SchoolHomeView.swift:303-341`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I14 | INSTRUCTOR, ADMIN | Lire la journée (leçons et cours) | R | `GET …/lessons`, `…/course-series` | moniteur de l'école | `apps/ios/Drivy/SchoolUI/SchoolTodayView.swift:602-628` | mémoire de journée (`SchoolTodayMemory`, `:761-770`) | aucune | — | — | — | #108 (fermée) | `apps/ios/DrivyTests/SchoolTodayAppointmentsTests.swift` |
| I15 | INSTRUCTOR | Démarrer une leçon sans rendez-vous | G | `POST …/lessons/start-now` | INSTRUCTOR + accès formation · `operationId` | `apps/ios/Drivy/SchoolAgendaUI/SchoolStartNowView.swift:210-218` | file chiffrée de l'école (`apps/ios/Drivy/SchoolConfigurationAPI/SchoolCommandOutbox.swift:305`) | élève, formation, module GPS | réponse/reçu | message, saisie gardée | file « à vérifier » | #111 (fermée) | `apps/ios/DrivyTests/SchoolStartNowClientTests.swift`, `SchoolStartNowConsentTests.swift` |
| I16 | INSTRUCTOR | Commencer une leçon planifiée | G | `POST …/lessons/:id/start` | INSTRUCTOR auteur · version leçon | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:929` | file chiffrée | leçon planifiée, heure atteinte | réponse/reçu | message | file « à vérifier » | #111 (fermée) | `apps/ios/DrivyTests/SchoolLessonLifecycleTests.swift` |
| I17 | INSTRUCTOR, ADMIN | Ouvrir une leçon ou un cours | R | `GET …/lessons/:id`, `…/course-series/:id` | moniteur de l'école | `apps/ios/Drivy/SchoolUI/SchoolTodayView.swift:315`, `:171-190` | cache d'écran | aucune | — | — | — | #108 (fermée) | `apps/ios/DrivyTests/SchoolTodayAppointmentsTests.swift` |
| I18 | INSTRUCTOR | Réduire puis revenir au trajet | L | — | — | `apps/ios/Drivy/SchoolUI/SchoolHomeView.swift:253-268` | état de session de capture (`apps/ios/Drivy/SchoolCaptureCore/SchoolCaptureSessionController.swift`) | capture existante | — | — | — | #111 (fermée) | `apps/ios/DrivyTests/SchoolCaptureLifecycleReactivityTests.swift` |
| I19 | INSTRUCTOR, LEARNER | Ouvrir Messages depuis une alerte | L | — | — | `apps/ios/Drivy/SchoolUI/SchoolHomeView.swift:138-150` | aucune | onglet Messages présent | — | refus expliqué (autre école) | — | #104 (fermée) | `apps/ios/DrivyTests/MessagingEntryTests.swift` |

### 5.4 Agenda — onglet moniteur (`SchoolHomeView.swift:196-203`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I20 | INSTRUCTOR, ADMIN | Lire mois, semaine, jour | R | `GET …/lessons`, `…/course-series` | moniteur de l'école | `apps/ios/Drivy/SchoolAgendaUI/SchoolAgendaView.swift:157-176` | mémoire d'agenda (`SchoolAgendaMemory`) | aucune | — | — | — | #108 (fermée) | `apps/ios/DrivyTests/SchoolAgendaMonthTests.swift` |
| I21 | INSTRUCTOR, ADMIN | Chercher le prochain rendez-vous | L | — | — | `apps/ios/Drivy/SchoolAgendaUI/SchoolAgendaView.swift:321` | aucune | agenda lu | — | — | — | #108 (fermée) | `apps/ios/DrivyTests/SchoolAgendaMonthTests.swift` |
| I22 | INSTRUCTOR, ADMIN | Vérifier un créneau | R | `GET …/lessons/availability` | moniteur affecté | `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningWorkspace.swift:526` | aucune | formation, moniteur, durée | — | motif affiché | — | #109 (fermée) | `apps/ios/DrivyTests/SchoolPlanningAvailabilityTests.swift` |
| I23 | INSTRUCTOR, ADMIN | Planifier une leçon | G | `POST …/lessons` | ADMIN/INSTRUCTOR + accès formation · contexte + créneau | `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningWorkspace.swift:662` | file chiffrée de l'école | créneau vérifié, lectures complètes | réponse/reçu | message, formulaire gardé | file « à vérifier » | #109 (fermée) | `apps/ios/DrivyTests/SchoolPlanningBookingTests.swift`, `SchoolPlanningLeaveWhileSendingTests.swift` |
| I24 | INSTRUCTOR, ADMIN | Déplacer une leçon | G | `POST …/lessons/:id/move` | ADMIN/INSTRUCTOR · version leçon | `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningWorkspace.swift:662` (même envoi, entrée depuis `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportView.swift:769`) | file chiffrée | version leçon, créneau | réponse/reçu | message | file « à vérifier » | #109 (fermée) | `apps/ios/DrivyTests/SchoolPlanningBookingTests.swift` |
| I25 | INSTRUCTOR, ADMIN | Annuler une leçon | G | `POST …/lessons/:id/cancel` | ADMIN/INSTRUCTOR · version leçon | `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningWorkspace.swift:685` (`SchoolPlanningView.swift:110-123`) | file chiffrée | règles d'annulation (`SchoolIndividualCancellationTests`) | réponse/reçu | message, confirmation gardée | file « à vérifier » | #109 (fermée) | `apps/ios/DrivyTests/SchoolIndividualCancellationTests.swift` |
| I26 | INSTRUCTOR, ADMIN | Enregistrer les préférences de planification | G | `PUT …/planning-defaults` | ADMIN/INSTRUCTOR · version préférence | `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningSettingsView.swift:170-179` | file chiffrée (domaine `planningPreferences`) | préférence relue | réponse/reçu | message, conflit comparé (`:257`) | file « à vérifier » | #110 (fermée) | `apps/ios/DrivyTests/SchoolPlanningDefaultsTests.swift` |
| I27 | INSTRUCTOR, ADMIN | Ouvrir l'éditeur ou une séance de cours | R | `GET …/course-series` | ADMIN/INSTRUCTOR + droit cours | `apps/ios/Drivy/SchoolAgendaUI/SchoolAgendaView.swift:565` | cache d'écran | aucune | — | — | — | #127 (fermée) | `apps/ios/DrivyTests/SchoolAgendaCoursesTests.swift` |

### 5.5 Élèves — onglet moniteur (`SchoolHomeView.swift:204-209`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I28 | INSTRUCTOR, ADMIN | Lire l'annuaire et ouvrir un dossier | R | `GET …/learners`, `…/trainings`, `…/assignments` | moniteur/administration de l'école | `apps/ios/Drivy/SchoolUI/SchoolBrowserView.swift:48-49` | cache d'écran (`SchoolWorkspace`) | aucune | — | — | — | #116 (fermée) | `apps/ios/DrivyTests/SchoolDossierTests.swift` |
| I29 | INSTRUCTOR, ADMIN | Filtrer, rechercher, afficher les profils à compléter | L | — | — | `apps/ios/Drivy/SchoolUI/SchoolBrowserView.swift:92`, `:137` | aucune | annuaire lu | — | — | — | #116 (fermée) | `apps/ios/DrivyTests/SchoolDossierTests.swift` |
| I30 | INSTRUCTOR, ADMIN | Planifier depuis le dossier | G | `POST …/lessons` | ADMIN/INSTRUCTOR | `apps/ios/Drivy/SchoolUI/SchoolLearnerDossierView.swift:461-462` → `SchoolPlanningWorkspace.swift:662` | file chiffrée | voir I23 | réponse/reçu | message | file « à vérifier » | #109 (fermée) | `apps/ios/DrivyTests/SchoolPlanningBookingTests.swift` |
| I31 | INSTRUCTOR | Démarrer une leçon depuis le dossier | G | `POST …/lessons/start-now` | INSTRUCTOR | `apps/ios/Drivy/SchoolUI/SchoolLearnerDossierView.swift:451` | file chiffrée | voir I15 | réponse/reçu | message | file « à vérifier » | #111 (fermée) | `apps/ios/DrivyTests/SchoolStartNowLaunchTests.swift` |
| I32 | INSTRUCTOR, ADMIN | Modifier le dossier d'un élève | G | `PATCH …/learners/:id` (`updateProfile`) | ADMIN/INSTRUCTOR selon champs · version profil | `apps/ios/Drivy/SchoolProfileUI/SchoolProfileView.swift:85-95` → `apps/ios/Drivy/SchoolProfileUI/SchoolProfileWorkspace.swift:277` | file chiffrée de l'école | version profil, confirmation explicite (`SchoolProfileView.swift:42-44`) | réponse/reçu | message, saisie gardée | file « à vérifier » | #116 (fermée) | `apps/ios/DrivyTests/SchoolProfileWorkspaceTests.swift` |
| I33 | INSTRUCTOR, ADMIN | Consigner un permis vu | G | `POST …/trainings/:id/permit-checks` | ADMIN/INSTRUCTOR + `permit_review_allowed` · version formation | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:973` | file chiffrée | formation active | réponse/reçu | message | file « à vérifier » | #117 (fermée) | `apps/ios/DrivyTests/SchoolLessonHubTests.swift` |

### 5.6 Leçons et progression — onglets élève (`SchoolHomeView.swift:391-408`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I34 | LEARNER | Lire leçons et progression | R | `GET …/trainings/:id/progress`, `…/lessons` | LEARNER de la formation | `apps/ios/Drivy/SchoolTrainingUI/SchoolTrainingView.swift:60` (`SchoolTrainingScreen`) | cache d'écran | dossier ouvert | — | — | — | #117 (fermée) | `apps/ios/DrivyTests/SchoolProgressReadingTests.swift` |
| I35 | LEARNER | S'inscrire à un cours collectif | G | `POST …/course-series/:id/enroll` | LEARNER · `operationId` | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEnrollmentWorkspace.swift:242-255` | coffre `SchoolCourseIntents` (`apps/ios/Drivy/SchoolAgendaAPI/SchoolCourseIntentStore.swift:153`) | place disponible, série publiée | réponse | message, intention gardée (`:332`) | intention « non confirmée » + reprise | #126 (fermée) | `apps/ios/DrivyTests/SchoolAgendaCoursesTests.swift`, `SchoolCourseIntentPersistenceTests.swift` |
| I36 | LEARNER | Rejoindre ou quitter la liste d'attente | G | `POST …/waitlist`, `…/waitlist/leave` | LEARNER | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEnrollmentWorkspace.swift:242-255` | coffre `SchoolCourseIntents` | série complète | réponse | message, intention gardée | reprise | #126 (fermée) | `apps/ios/DrivyTests/SchoolAgendaCoursesTests.swift` |
| I37 | LEARNER | Accepter ou décliner une place proposée | G | `POST …/course-offers/:id/accept\|decline` | LEARNER | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEnrollmentWorkspace.swift:242-255` | coffre `SchoolCourseIntents` | offre non expirée (`:182-183`) | réponse | message | reprise | #126 (fermée) | `apps/ios/DrivyTests/SchoolAgendaCoursesTests.swift` |
| I38 | LEARNER | Annuler une inscription | G | `POST …/course-enrollments/:id/cancel` | LEARNER · version inscription | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEnrollmentViews.swift:58-68` | coffre `SchoolCourseIntents` | délai d'annulation (`:336`) | réponse | message | reprise | #126 (fermée) | `apps/ios/DrivyTests/SchoolAgendaCoursesTests.swift` |
| I39 | LEARNER | Être prévenu des prochaines sessions | O | `PUT\|POST …/course-follows/me/:typeId` | membre élève · clé naturelle | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEnrollmentWorkspace.swift:213` → `apps/ios/Drivy/SchoolAgendaAPI/SchoolCourseClient.swift:484` | appel direct, sans file | type de cours publié | réponse | message, état revient | — | #126 (fermée) | non prouvé |
| I40 | LEARNER | Demander un déplacement ou une annulation | G | `POST …/lessons/:id/change-requests` | LEARNER de la leçon · `operationId` par essai | `apps/ios/Drivy/SchoolAgendaAPI/SchoolLessonChangeClient.swift:101` (`apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonChangeUI.swift:193`) | appel direct (pas de file) | leçon planifiée, une demande en attente | réponse | message | — | #109 (fermée) | `apps/ios/DrivyTests/SchoolLessonChangeTests.swift` |
| I41 | LEARNER | Retirer sa demande | G | `POST …/lesson-change-requests/:id/withdraw` | LEARNER demandeur · `If-Match` | `apps/ios/Drivy/SchoolAgendaAPI/SchoolLessonChangeClient.swift:109` (`SchoolLessonChangeUI.swift:186`) | appel direct | demande en attente | réponse | message | — | #109 (fermée) | `apps/ios/DrivyTests/SchoolLessonChangeTests.swift` |

### 5.7 Profil et réglages

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I42 | compte | Modifier son profil (nom, coordonnées) | O | `PATCH /v1/me/profile` | personne · `If-Match` personne | `apps/ios/Drivy/SchoolProfileUI/SchoolSelfProfileEditor.swift:127` → `apps/ios/Drivy/SchoolAPI/DrivyAPIClient.swift:209` | intention chiffrée (`apps/ios/Drivy/Core/AccountIntentStorage.swift:19`) | personne confirmée lue | réponse | message, saisie gardée | intention reprise | #118 (fermée) | `apps/ios/DrivyTests/SchoolSelfProfileIntentTests.swift` |
| I43 | compte | Changer ou retirer sa photo | O | `PUT\|DELETE /v1/me/profile/photo` | personne · version personne | `apps/ios/Drivy/SchoolProfileUI/SchoolMyProfileView.swift:67`, `:176` → `DrivyAPIClient.swift:216` | intention chiffrée | photo recadrée | réponse | message, « Réessayer » (`:188`) | intention reprise | #118 (fermée) | `apps/ios/DrivyTests/SchoolProfilePhotoCropTests.swift` |
| I44 | compte | Changer une préférence de notification | O | `PUT /v1/me/notification-preferences` | personne · version préférences | `apps/ios/Drivy/SchoolProfileUI/SchoolNotificationSettingsModel.swift:106` (`SchoolNotificationSettingsView.swift:27`) | `EncryptedAccountIntentStore` | préférences relues | réponse | message, « Vérifier la synchronisation » | état incertain explicite | #119 (fermée) | `apps/ios/DrivyTests/SchoolNotificationSettingsTests.swift` |
| I45 | LEARNER | Donner ou refuser l'accord GPS | G | `POST …/learners/:id/recording-choice` | INSTRUCTOR sauf choix `SELF` · `expectedChoiceVersion` | `apps/ios/Drivy/SchoolCaptureUI/SchoolRecordingChoiceWorkspace.swift:140`, `:250` | coffre chiffré (`apps/ios/Drivy/SchoolCaptureCore/SchoolRecordingRefusalIntent.swift`) | leçon ou profil, module GPS actif | réponse | message, intention gardée | intention « à vérifier » | #125 (fermée) | `apps/ios/DrivyTests/SchoolStartNowConsentTests.swift` |
| I46 | ADMIN, INSTRUCTOR | Réordonner et masquer les signalements | O | `PUT …/observation-themes` | ADMIN/INSTRUCTOR + droit signalements · version thèmes | `apps/ios/Drivy/SchoolObservationAPI/SchoolObservationThemeStore.swift:189` → `SchoolObservationThemes.swift:234` | copie locale chiffrée par portée (`SchoolObservationThemeStore.swift:45`) | thèmes relus | réponse | message, « Réessayer » (`:169`) | état d'échec explicite | #112 (fermée) | `apps/ios/DrivyTests/SchoolObservationThemeTests.swift` |
| I47 | INSTRUCTOR | Classer ses signalements | O | `PUT …/observation-ranking` | ADMIN/INSTRUCTOR | `apps/ios/Drivy/SchoolObservationAPI/SchoolObservationRanking.swift:100` | copie locale (`SchoolObservationRankingStore.swift:36`) | thèmes lus | réponse | message | — | #112 (fermée) | `apps/ios/DrivyTests/SchoolObservationRankingTests.swift` |
| I48 | ADMIN, INSTRUCTOR, LEARNER | Remplir ou reprendre l'accueil guidé | G | `PATCH …/my-onboarding`, `POST …/my-onboarding/complete` | membre · version progression | `apps/ios/Drivy/SchoolProfileUI/SchoolProfileWorkspace.swift:291`, `:298` (`SchoolOnboardingView.swift:447`) | file chiffrée de l'école | école `ACTIVE`, dossier élève prêt | réponse/reçu | message, saisie gardée | file « à vérifier » | #120 (ouverte) | `apps/ios/DrivyTests/SchoolOnboardingRecordingSummaryTests.swift` |
| I49 | compte | Ouvrir l'aide | L | — | — | `apps/ios/Drivy/SchoolUI/SchoolStaffSettingsView.swift:91-94`, `apps/ios/Drivy/SchoolUI/SchoolLearnerSettingsView.swift:66-69` | aucune | aucune | — | — | — | #106 (ouverte) | `apps/ios/DrivyTests/SchoolHelpTests.swift` |

### 5.8 Trajet GPS (préparation, direct, historique, replay)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I50 | INSTRUCTOR | Préparer le départ (autorisation, appareil) | G | `POST …/devices/:id/assessments`, `POST …/lessons/:id/captures` | INSTRUCTOR · module GPS, consentement | `apps/ios/Drivy/SchoolCaptureUI/SchoolCapturePreparationWorkspace.swift:305`, `:410` | coffre SQLCipher (`apps/ios/Drivy/SchoolCaptureCore/SQLCipherSchoolCaptureStore.swift`) | consentement élève, autorisation système | réponse/reçu | message, demande gardée (`:414-419`) | « à vérifier » + reprise | #111 (fermée) | `apps/ios/DrivyTests/SchoolCaptureLifecycleTests.swift` |
| I51 | INSTRUCTOR | Arrêter la collecte | G | `POST …/captures/:id/stop` | INSTRUCTOR/LEARNER propriétaire | `apps/ios/Drivy/SchoolCaptureCore/SQLCipherSchoolCaptureStore.swift:593` | coffre SQLCipher | capture en cours | réponse/reçu | message, arrêt local maintenu | « à vérifier » | #111 (fermée) | `apps/ios/DrivyTests/SchoolCaptureLifecycleReactivityTests.swift` |
| I52 | INSTRUCTOR | Envoyer les lots de trace | G | `PUT …/chunks/:index` | INSTRUCTOR/LEARNER | `apps/ios/Drivy/SchoolCaptureCore/SQLCipherSchoolCaptureStore.swift:627` | coffre SQLCipher | capture, réseau | réponse/reçu (lot) | message, reprise sans perte locale | « à vérifier » | #111 (fermée) | `apps/ios/DrivyTests/SchoolCaptureInteropTests.swift` |
| I53 | INSTRUCTOR | Finaliser le trajet | G | `POST …/captures/:id/finalize` | INSTRUCTOR/LEARNER · version capture | `apps/ios/Drivy/SchoolCaptureCore/SQLCipherSchoolCaptureStore.swift:570` (`SchoolCaptureHistoryView.swift:84`) | coffre SQLCipher | lots envoyés | réponse/reçu | message, trajet gardé | « à vérifier » ; choix partiel explicite (`SchoolCaptureHistoryView.swift:78`) | #115 (fermée) | `apps/ios/DrivyTests/SchoolCaptureLifecycleTests.swift` |
| I54 | INSTRUCTOR | Signaler pendant le trajet | O | `POST …/lessons/:id/geo-observations` | INSTRUCTOR auteur | `apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureLiveObservations.swift:218` | file chiffrée de l'école | capture en cours | réponse/reçu | message, saisie gardée | file « à vérifier » | #112 (fermée) | `apps/ios/DrivyTests/SchoolLiveObservationRecorderTests.swift` |
| I55 | INSTRUCTOR | Annuler un signalement (retour arrière) | O | `POST …/geo-observations/:id/remove` | INSTRUCTOR auteur · version observation | `apps/ios/Drivy/SchoolCaptureUI/SchoolObservationUndoBanner.swift:90` | file chiffrée de l'école | observation créée | réponse/reçu | message | file « à vérifier » | #112 (fermée) | `apps/ios/DrivyTests/SchoolLiveObservationUndoTests.swift` |
| I56 | INSTRUCTOR, ADMIN, LEARNER | Lire l'historique des trajets | R | `GET …/captures` | portée de l'école, RLS | `apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureHistoryWorkspace.swift:37` | cache d'écran | aucune | — | — | — | #115 (fermée) | `apps/ios/DrivyTests/SchoolTripsTests.swift` |
| I57 | INSTRUCTOR, ADMIN, LEARNER | Rejouer un trajet | R | `GET …/captures/:id` (segments) | portée de l'école | `apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureReplayWorkspace.swift:124` | cache d'écran | trajet finalisé | — | — | — | #115 (fermée) | `apps/ios/DrivyTests/SchoolCaptureReplayTests.swift`, `SchoolReplayReadingTests.swift` |

### 5.9 Leçon et bilan (`SchoolLessonReportView`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I58 | INSTRUCTOR, LEARNER | Enregistrer objectifs et préparation | O | `PUT …/lessons/:id/preparation` | INSTRUCTOR/LEARNER · version préparation | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:900` | file chiffrée de l'école | leçon ouverte | réponse/reçu | message, saisie gardée | file « à vérifier » | #113 (fermée) | `apps/ios/DrivyTests/SchoolLessonPreparationReactivityTests.swift` |
| I59 | INSTRUCTOR, LEARNER | Enregistrer le souhait de l'élève | O | `PUT …/trainings/:id/wish` | INSTRUCTOR/LEARNER · version souhait | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:907` | file chiffrée | formation active | réponse/reçu | message | file « à vérifier » | #113 (fermée) | `apps/ios/DrivyTests/SchoolLessonWishReactivityTests.swift` |
| I60 | INSTRUCTOR | Enregistrer le brouillon de bilan | O | `PUT …/report-drafts/:id` | INSTRUCTOR/LEARNER · version brouillon | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:983` | file chiffrée + brouillon local chiffré (`SchoolReportLocalDraft.swift`) | constat de fin | réponse/reçu | message, brouillon conservé | file « à vérifier » | #114 (fermée) | `apps/ios/DrivyTests/SchoolReportFlowTests.swift` |
| I61 | INSTRUCTOR | Régler le partage (ce que le moniteur garde privé) | G | `PUT …/lessons/:id/sharing` | INSTRUCTOR auteur · `sharing_version` | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:1001` | file chiffrée, projection `optimisticSharing` (`:473-477`) | bilan ou trajet présent | réponse/reçu | message, état confirmé restauré | file « à vérifier » | #114 (fermée) | `apps/ios/DrivyTests/SchoolLessonClosureReactivityTests.swift` |
| I62 | INSTRUCTOR | Terminer la leçon | G | `POST …/lessons/:id/complete` | INSTRUCTOR/LEARNER · version leçon | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:948` | file chiffrée | constat saisi | réponse/reçu | message, saisie gardée | file « à vérifier » | #114 (fermée) | `apps/ios/DrivyTests/SchoolLessonFinishTests.swift` |
| I63 | INSTRUCTOR, ADMIN | Marquer l'élève absent | G | `POST …/lessons/:id/no-show` | ADMIN/INSTRUCTOR · version leçon | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:956` | file chiffrée | fin prévue atteinte (`:479-482`) | réponse/reçu | message | file « à vérifier » | #114 (fermée) | `apps/ios/DrivyTests/SchoolLessonFinishTests.swift` |

### 5.10 Cours collectifs — moniteur (`SchoolAgendaUI`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I64 | INSTRUCTOR, ADMIN | Créer un type de cours | G | `POST …/course-types` | ADMIN/INSTRUCTOR + droit cours | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEditorWorkspace.swift:230` → `apps/ios/Drivy/SchoolAgendaAPI/SchoolCourseClient.swift:362` | coffre `SchoolCourseIntents` | catalogue lu | réponse | message, saisie gardée | intention reprise (`:373`) | #127 (fermée) | `apps/ios/DrivyTests/SchoolCourseClientTests.swift` |
| I65 | INSTRUCTOR, ADMIN | Enregistrer le brouillon d'une série | G | `POST\|PUT …/course-series` | ADMIN/INSTRUCTOR · version série | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEditorWorkspace.swift:253` → `SchoolCourseClient.swift:368` | coffre `SchoolCourseIntents` | séances valides | réponse | message, brouillon gardé | intention reprise | #127 (fermée) | `apps/ios/DrivyTests/SchoolCourseClientTests.swift` |
| I66 | INSTRUCTOR, ADMIN | Publier une série | G | `POST …/course-series/:id/publish` | ADMIN/INSTRUCTOR · version série | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEditorWorkspace.swift:261` → `SchoolCourseClient.swift:375` (`SchoolCoursePublicationReviewView.swift:43`) | coffre `SchoolCourseIntents` | brouillon enregistré, places réservées | réponse | message, revue rouverte | intention reprise | #127 (fermée) | `apps/ios/DrivyTests/SchoolCourseClientTests.swift` |
| I67 | INSTRUCTOR, ADMIN | Changer la capacité | G | `POST …/course-series/:id/capacity` | ADMIN/INSTRUCTOR · version série | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEditorWorkspace.swift:492` → `SchoolCourseClient.swift:381` | coffre `SchoolCourseIntents` | série publiée | réponse | message | intention reprise | #127 (fermée) | `apps/ios/DrivyTests/SchoolCourseClientTests.swift` |
| I68 | INSTRUCTOR, ADMIN | Inscrire un élève (personnel) | G | `POST …/course-series/:id/enrollments` | ADMIN/INSTRUCTOR | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEnrollmentWorkspace.swift:573` → `SchoolCourseClient.swift:422` | coffre `SchoolCourseIntents` | place disponible | réponse | message | intention reprise | #126 (fermée) | `apps/ios/DrivyTests/SchoolAgendaCoursesTests.swift` |
| I69 | INSTRUCTOR, ADMIN | Annuler une inscription (personnel) | G | `POST …/course-enrollments/:id/staff-cancel` | ADMIN/INSTRUCTOR · version inscription | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseEnrollmentWorkspace.swift:586` → `SchoolCourseClient.swift:428` | coffre `SchoolCourseIntents` | motif saisi | réponse | message | intention reprise | #126 (fermée) | `apps/ios/DrivyTests/SchoolAgendaCoursesTests.swift` |
| I70 | INSTRUCTOR, ADMIN | Marquer une présence | O | `PUT …/attendance/:occurrenceId` | ADMIN/INSTRUCTOR · `expectedVersion` de cellule | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseAttendanceWorkspace.swift:268` (`:20`) → `SchoolCourseClient.swift:442` | file des gestes de cours (`SchoolCourseSheetQueueTests`) | séance commencée | réponse | message, ligne marquée (`:411`) | ligne « à confirmer » | #128 (fermée) | `apps/ios/DrivyTests/SchoolCourseSheetQueueTests.swift` |
| I71 | INSTRUCTOR, ADMIN | Enregistrer un règlement | O | `POST …/course-enrollments/:id/payments` | ADMIN/INSTRUCTOR + `cash_record` | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseAttendanceWorkspace.swift:268` (`:21`) → `SchoolCourseClient.swift:448` | file des gestes de cours | montant entier positif | réponse | message, ligne marquée | ligne « à confirmer » | #129 (fermée) | `apps/ios/DrivyTests/SchoolCourseSheetQueueTests.swift` |
| I72 | INSTRUCTOR, ADMIN | Annuler un règlement | G | `POST …/course-payments/:id/void` | ADMIN/INSTRUCTOR + `cash_record` | `apps/ios/Drivy/SchoolAgendaUI/SchoolCoursePaymentHistory.swift:25` → `SchoolCourseClient.swift:453` | file des gestes de cours | motif saisi | réponse | message | ligne « à confirmer » | #129 (fermée) | `apps/ios/DrivyTests/SchoolCourseSheetQueueTests.swift` |
| I73 | INSTRUCTOR, ADMIN | Valider un cours | O | `POST …/course-enrollments/:id/validate` | ADMIN/INSTRUCTOR + `VALIDATE_REQUIREMENT` | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseAttendanceView.swift:59` → `SchoolCourseClient.swift:458` | file des gestes de cours | critères remplis | réponse | message | ligne « à confirmer » | #130 (fermée) | `apps/ios/DrivyTests/SchoolCourseSheetQueueTests.swift` |
| I74 | INSTRUCTOR, ADMIN | Retirer une validation | G | `POST …/course-completions/:id/revoke` | ADMIN/INSTRUCTOR | `apps/ios/Drivy/SchoolAgendaUI/SchoolCourseAttendanceView.swift:343-358` → `SchoolCourseClient.swift:463` | file des gestes de cours | motif saisi | réponse | message | ligne « à confirmer » | #130 (fermée) | `apps/ios/DrivyTests/SchoolCourseSheetQueueTests.swift` |

### 5.11 Invitations — feuille (`SchoolInvitationsView`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I75 | ADMIN, INSTRUCTOR | Lire les invitations | R | `GET …/invitations` | ADMIN/INSTRUCTOR | `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationsView.swift:498` | cache d'écran | école `ACTIVE` | — | — | — | #121 (fermée) | `apps/ios/DrivyTests/SchoolInvitationListPresentationTests.swift` |
| I76 | ADMIN, INSTRUCTOR | Créer une invitation ou un code | G | `POST …/invitations` | ADMIN/INSTRUCTOR | `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationWorkspace.swift:291`, `:305` | file chiffrée (domaine `invitations`) | offres, moniteur | réponse/reçu | message, formulaire gardé | file « à vérifier », code absent signalé | #121 (fermée) | `apps/ios/DrivyTests/SchoolInvitationWorkspaceTests.swift` |
| I77 | ADMIN, INSTRUCTOR | Renvoyer une invitation | G | `POST …/invitations/:id/resend` | ADMIN/INSTRUCTOR · version invitation | `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationWorkspace.swift:316`, `:324` | file chiffrée | invitation actionnable | réponse/reçu | message | file « à vérifier » | #121 (fermée) | `apps/ios/DrivyTests/SchoolInvitationClientTests.swift` |
| I78 | ADMIN, INSTRUCTOR | Révoquer une invitation | G | `POST …/invitations/:id/revoke` | ADMIN/INSTRUCTOR · version invitation | `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationWorkspace.swift:333` | file chiffrée | confirmation explicite (`SchoolInvitationsView.swift:684`) | réponse/reçu | message | file « à vérifier » | #121 (fermée) | `apps/ios/DrivyTests/SchoolInvitationWorkspaceTests.swift` |

### 5.12 Examens (`SchoolExamsUI`)

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I79 | INSTRUCTOR, ADMIN | Créer, modifier, reporter un examen | G | `POST …/trainings/:id/exams`, `POST …/exams/:id/update\|postpone` | ADMIN/INSTRUCTOR + `exam_manage` · version examen | `apps/ios/Drivy/SchoolTrainingUI/SchoolExamsUI.swift:206`, `:305-306` | file chiffrée de l'école | formation active, accompagnement libre | réponse/reçu | message, saisie gardée | file « à vérifier » (`:72`) | #117 (fermée) | `apps/ios/DrivyTests/SchoolExamTests.swift` |
| I80 | INSTRUCTOR, ADMIN | Renseigner ou corriger un résultat | G | `POST …/exams/:id/result` | ADMIN/INSTRUCTOR + `exam_manage` · version examen | `apps/ios/Drivy/SchoolTrainingUI/SchoolExamsUI.swift:303`, `:308` | file chiffrée | examen commencé | réponse/reçu | message | file « à vérifier » | #117 (fermée) | `apps/ios/DrivyTests/SchoolExamTests.swift`, `SchoolExamNextStepTests.swift` |

### 5.13 Messages — onglet conditionnel

**Surface conditionnelle** : l'onglet Messages n'existe que dans une compilation de qualification
(`DRIVY_MESSAGING_QUALIFICATION`) ou au simulateur `DEBUG` avec `-messaging-development`
(`apps/ios/Drivy/SchoolUI/SchoolMessagingEntry.swift:14-22`) ; sinon `homeMessagingEntry` vaut `nil` (`SchoolRootView.swift:644-668`) et
l'onglet est absent (`SchoolHomeView.swift:572-590`). Aucune surface web de messagerie (registre #106 §2.2).

| # | Rôle | Action | Mode | Endpoint | Autorité · version | Source locale | Persistance | Dépendances | Confirmation | Refus | Inconnu | Issue | Preuve |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| I81 | membre | Envoyer un message | O | `POST …/conversations/:id/messages` | adhésion + époque · `clientMessageId` | `apps/ios/Drivy/MessagingUI/MessagingComposerModel.swift:104` | file chiffrée (`apps/ios/Drivy/MessagingCore/MessagingProtectedStore.swift`) | conversation autorisée | réponse | message, envoi gardé | statut « en cours/lent », renvoi (`MessagingConversationView.swift:282-295`) | #104 (fermée) | `apps/ios/DrivyTests/MessagingOptimisticMutationTests.swift`, `MessagingSendPresentationTests.swift` |
| I82 | membre | Réagir, épingler, voter | O | `PUT\|DELETE …/reactions/:emoji`, `…/pin`, `PUT …/poll/votes` | adhésion + époque · `operationId` optionnel | `apps/ios/Drivy/MessagingUI/MessagingWorkspace.swift:640-655` | file de mutations chiffrée | message lisible | réponse | message, état revient | mutation « à vérifier » | #104 (fermée) | `apps/ios/DrivyTests/MessagingOptimisticMutationTests.swift` |
| I83 | auteur, admin | Supprimer pour moi / pour tous | O | `DELETE …/messages/:id` | auteur ou administration · `operationId` | `apps/ios/Drivy/MessagingUI/MessagingWorkspace.swift:634` | file de mutations | droit relu au moment du geste (`MessagingConversationView.swift:305-306`) | réponse | message | mutation « à vérifier » | #104 (fermée) | `apps/ios/DrivyTests/MessagingCoreTests.swift` |
| I84 | membre | Marquer lu | O | `PUT …/conversations/:id/read-state` | adhésion · `expectedVersion` si sourdine | `apps/ios/Drivy/MessagingUI/MessagingWorkspace.swift:306` | état de lecture local | messages visibles | réponse | — | reprise au prochain affichage | #104 (fermée) | `apps/ios/DrivyTests/MessagingReadNotificationTests.swift` |
| I85 | membre | Mettre en sourdine | O | `PUT …/read-state` (`mutedUntil`) | adhésion · `expectedVersion` | `apps/ios/Drivy/MessagingUI/MessagingWorkspace.swift:368-381` | file de mutations | conversation | réponse | message, « Réessayer » (`:388`) | mutation « à vérifier » | #104 (fermée) | `apps/ios/DrivyTests/MessagingOptimisticMutationTests.swift` |
| I86 | membre | Signaler des messages | G | `POST …/reports` | adhésion · `clientReportId` | `apps/ios/Drivy/MessagingUI/MessagingWorkspace.swift:1058` | file chiffrée | sélection de messages | réponse | message | reprise | #104 (fermée) | `apps/ios/DrivyTests/MessagingReportInboxTests.swift` |
| I87 | admin de conversation | Nommer un administrateur, retirer un membre, clore un sondage | G | `PUT\|DELETE …/general/admins/:personId`, `DELETE …/general/members/:personId`, `POST …/poll/close` | administration de conversation · adhésion | `apps/ios/Drivy/MessagingUI/MessagingWorkspace.swift:662`, `:671`, `:675` → `apps/ios/Drivy/MessagingAPI/MessagingHTTPTransport.swift:373`, `:377` | appel direct | droits relus | réponse | message | — | #104 (fermée) | `apps/ios/DrivyTests/MessagingThreadTests.swift` |
| I88 | membre | Gérer ses appareils et la sauvegarde des clés | G | `POST …/keys/device_signing/upload`, `…/room_keys/version` | adhésion + qualification | `apps/ios/Drivy/MessagingUI/MessagingOwnDevicesModel.swift:56`, `apps/ios/Drivy/MessagingUI/MessagingKeyBackupView.swift:76` | stockage chiffré local | appareil vérifié | réponse | message | — | #104 (fermée) | `apps/ios/DrivyTests/MessagingOwnDevicesTests.swift`, `MessagingKeyBackupTests.swift` |

## 6. Synthèse

Règle de comptage : une **surface** est une page, un onglet, une feuille ou un écran distinct qui porte au moins une action
des tableaux ; les rubriques d'un même écran comptent pour une. Une **action** est une ligne ; les actions `O` et `G` sont
les écritures.

| Mesure | Web | iOS | Total |
|---|---|---|---|
| Surfaces inventoriées | 32 | 49 | 81 |
| Actions inventoriées (lecture, locale, écriture) | 69 | 88 | 157 |
| Actions d'écriture (`O` + `G`) | 48 | 69 | 117 |
| Actions d'écriture sans test trouvé | 7 | 1 | 8 |
| Actions d'écriture sans issue propriétaire métier | 1 | 0 | 1 |

Répartition des modes : `L` 12, `R` 28, `O` 38, `G` 79 (total 157).

Surfaces web (32) : `/app`, `/app/invitation`, `/app/recover`, `/app/preferences`, `/app/ouvrir`, `/app/operateur`, porte
de la console, tableau de bord, statistiques, aperçu/préparation, agenda, fiche leçon, fiche cours, disponibilités,
absences, annuaire élèves, dossier élève, équipe, invitations (élèves), invitations (équipe), formations, offres,
référentiels, procédures, prestations, conditions, configuration, confidentialité, champs de profil, signalements,
trajets, page inconnue.

Surfaces iOS (49) : 7 onglets — Aujourd'hui, Agenda, Élèves, Profil, Leçons, Progression, Messages (conditionnel) ;
9 feuilles de la racine (`apps/ios/Drivy/SchoolUI/SchoolRootView.swift:176-237`) — Compte, Rejoindre par lien, Rejoindre
par code, Code d'accès, Ouverture d'école, Invitations (liste), Invitation (création), Profil, Accueil guidé ; 33 écrans —
connexion, récupération d'accès, choix d'école, compte sans école, dossier élève, fiche leçon/bilan, planification,
préférences de planification, préparation de trajet, trajet direct, historique des trajets, replay, choix d'enregistrement,
examens, éditeur de cours, inscription à un cours, présence, règlements, revue de publication, revue d'inscription,
réglages de notifications, thèmes de signalements, aide, réglages moniteur, réglages élève, trajets de l'élève, édition du
profil, mon profil, profil d'un élève, fil de messages, appareils de messagerie, sauvegarde des clés, signalements reçus.

Actions d'écriture **non prouvées** (aucun test dédié trouvé) : `W01`, `W03`, `W04`, `W05`, `W06`, `W47`, `W48`, `I39`.
Quatre lectures ou actions locales sont aussi sans preuve : `W46` (membres), `W66` (trajets), `W67` (recherche de
trajets), `I12` (ouverture du portail web). Aucune n'est présentée comme qualifiée : elles restent à couvrir par la
campagne #131 §2-3.

Action d'écriture sans issue propriétaire : `W17` (export CSV des mesures) — aucune issue #104/#106–#130 ne la nomme ;
rattachée au socle `#106` (ouverte) pour ne pas l'attribuer à un ticket fermé.

## 7. Écarts constatés (aucune fonction inventée)

1. **Commandes web déclarées sans surface** : `saveSetup`, `activate`, `createOffering`, `createCurriculum`,
   `createCatalogPolicy`, `createCommercialTerms`, `createServiceProduct`, `createFormation`, `publishProfilePolicy`
   existent dans `apps/web/client/command-core.ts` mais aucun composant ne les appelle (`grep` sur
   `apps/web/client/portal` : aucun résultat hors tests et fixture d'aperçu `apps/web/client/portal/preview/families/setup.ts:80`). Ces fonctions sont
   **absentes de l'interface web** : la création de formation passe par `applySetupDraft` (W21) et la publication des
   champs par `createProfilePolicy` avec `publishNow` (W63).
2. **Publication explicite du bilan absente sur iOS** : `publishReportDraft` est déclaré
   (`apps/ios/Drivy/SchoolConfigurationAPI/SchoolCommandOutbox.swift:38`), repris après coupure
   (`apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportWorkspace.swift:495`, `:511`) et routé
   (`apps/ios/Drivy/SchoolLessonReportAPI/SchoolLessonReportClient.swift:115-117`), mais aucun site n'émet cette commande. Le partage
   automatique décidé le 28 septembre 2026 est réglé par `updateLessonSharing` (I61). Aucune action « publier le bilan »
   n'est donc présentée comme livrée.
3. **Messagerie non exposée en production** : l'onglet Messages et la feuille « Envoyer un message » n'existent qu'en
   compilation de qualification ou simulateur `DEBUG` (`apps/ios/Drivy/SchoolUI/SchoolMessagingEntry.swift:14-22`). #104 est fermée, mais
   la surface n'est pas offerte par une IPA ordinaire : la matrice la marque conditionnelle, pas absente.
4. **Barrières de file trop larges côté iOS** (constat, non corrigé ici — propriété #106) :
   `apps/ios/Drivy/SchoolAgendaUI/SchoolStartNowView.swift:69` lit `pending(for: scope)` (toute l'école) et bloque `START_LESSON_NOW` pour une invitation
   ou un tarif en attente ; `apps/ios/Drivy/SchoolObservationUI/SchoolObservationWorkspace.swift:189` fait de même pour les signalements ;
   `apps/ios/Drivy/SchoolProfileUI/SchoolProfileWorkspace.swift:153` pour le dossier et l'accueil ; `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationWorkspace.swift:165` sérialise toutes
   les invitations entre elles. Ces quatre lectures de file ne sont pas reprises dans les tableaux : elles décrivent un
   écart de dépendance, pas une action.
5. **Aucune surface web de terrain** : la console est réservée à `ADMIN` (`apps/web/client/console/access-reader.ts:32`) ; un `INSTRUCTOR`
   ou un `LEARNER` n'a pas d'écran web, y compris pour les routes serveur qui les acceptent (invitations, planning). Le
   web ne comporte ni capture GPS, ni bilan de leçon, ni messagerie (registre #106 §2.2, revérifié).
6. **Écrans de lecture pure, non optimistes** : `trajets` (W66), `statistiques` (W16), `tableau-de-bord` (W14), les listes
   d'invitations (W49) et de membres (W46), l'historique et le replay iOS (I56, I57) ne portent aucune mutation : ils sont
   marqués `R` et ne sont pas décrits comme optimistes.
7. **`GET …/observation-ranking` peut écrire** un rafraîchissement quotidien côté serveur (registre #106 §1.10, note
   `apps/api/src/observation-ranking.ts:78`) : la lecture iOS du classement (I47) est donc une lecture qui peut déclencher une commande
   serveur ; elle reste classée `O` côté écran parce que l'ordre affiché est une projection locale confirmée ensuite.

## 8. Contrôle des citations

Le script ci-dessous a été exécuté depuis `C:\Users\jtoma\AppData\Local\Temp\opencode\verifier-citations.mjs`, **hors du
dépôt** (aucun fichier ajouté : le périmètre de cette tâche ne permet que ce document). Il résout les chemins complets,
puis les noms de fichier seuls par unicité dans le dépôt, et vérifie existence, bornes et ligne non vide.

```js
// node verifier-citations.mjs <racine> <document>
import { readFileSync, existsSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';
const root = process.argv[2], doc = process.argv[3];
const text = readFileSync(join(root, doc), 'utf8');
const byName = new Map();
(function walk(dir) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (['node_modules', '.git', 'build', 'dist', '.build', '.codebase-memory'].includes(e.name)) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p);
    else byName.set(e.name, [...(byName.get(e.name) ?? []), p.slice(root.length + 1).replaceAll('\\', '/')]);
  }
})(root);
const re = /([A-Za-z0-9_@./-]+\.(?:ts|tsx|swift|mjs|js|json|md|py|css)):(\d+)(?:-(\d+))?/g;
const problems = []; let checked = 0;
for (const [index, line] of text.split(/\r?\n/).entries()) {
  let m;
  while ((m = re.exec(line)) !== null) {
    let path = m[1];
    if (!path.includes('/')) {
      const c = byName.get(basename(path)) ?? [];
      if (c.length !== 1) { problems.push(`${index + 1} ${path} ${c.length ? 'ambigu' : 'introuvable'}`); continue; }
      path = c[0];
    }
    checked += 1;
    const target = join(root, path);
    if (!existsSync(target)) { problems.push(`${index + 1} absent ${path}`); continue; }
    const content = readFileSync(target, 'utf8').split(/\r?\n/);
    const from = Number(m[2]), to = Number(m[3] ?? m[2]);
    if (from < 1 || to > content.length) { problems.push(`${index + 1} ${path}:${from}-${to} hors bornes`); continue; }
    if (from === to && content[from - 1].trim() === '') problems.push(`${index + 1} ${path}:${from} vide`);
  }
}
console.log(JSON.stringify({ citations: checked, problems: problems.length, detail: problems }, null, 2));
```

Résultat de l'exécution au SHA `17b6b667` : **251 citations contrôlées, 0 problème**, et 157 lignes de tableau à
14 colonnes (contrôle séparé du nombre de cellules). Le contrôle porte sur les
`fichier:ligne` ; il ne prouve pas que la ligne citée dit bien ce que la colonne affirme — cette lecture a été faite
manuellement pour chaque ligne, et les citations du registre #106 non revérifiées ici ne sont pas reprises.
