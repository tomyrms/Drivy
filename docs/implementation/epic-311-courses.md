# #311 / R17 #328 — cours collectifs, de la série à ses séances

Branche `claude/311-planning`, après `b4dee986` (#323). Périmètre : `apps/web/client/portal/courses/*`, le branchement dans `portal/agenda/{agenda-page.tsx,use-agenda.ts}` et la famille d'aperçu `portal/preview/families/planning.ts` (cours, types, politique). Aucune nouvelle destination : les cours vivent dans la section `agenda`. Aucun backend, contrat, migration, ancien rendu, Swift ou CI modifié. Participants, attente, appel, règlements et validation (#329) sont hors de cette vague. Rien ci-dessous ne vaut validation du porteur ni ne ferme #328.

## Sous-vues reconstruites

- **Menu « Ajouter »** (`course-add-menu.tsx`) : Leçon individuelle ou Cours collectif, au clavier comme au doigt. Sans module ou sans droit de gestion (`school.modules.collectiveCoursesEnabled` et `canManage` du catalogue), l'entrée reste le bouton « Planifier une leçon » : aucun menu à un seul choix.
- **Type de cours** (`course-type-dialog.tsx`) : une action courte (nom, description), le brouillon de série reste intact derrière ; le type confirmé est proposé et choisi aussitôt.
- **Brouillon de série** (`course-editor.tsx`, `use-course-draft.ts`) : informations courantes (type, titre, description, lieu, responsable, places, minimum, langue, conditions), puis séances en liste compacte (une ligne : date, heures, moniteur, « Facultative »). Jamais un champ par séance à l'écran.
- **Séance** (`session-parts.tsx`) : une séance à la fois, dans la même page, avec « Retour à la série ». Date, début, fin, moniteur, présence obligatoire, durée calculée ; « Retirer cette séance » seulement s'il en reste une autre. Ajouter une séance reprend heures et moniteur de la précédente, une semaine plus tard (règle existante `emptySession`). Aucune modale empilée.
- **Revue puis publication** : « Relire et publier » ouvre la revue (type, lieu, responsable, langue, places, durée, annulation libre, séances, conditions), puis « Publier le cours » est un acte explicite. Si le brouillon a changé, il est d'abord enregistré (une commande), puis publié (une autre) ; la publication part de la version enregistrée, jamais de l'écran.
- **Fiche du cours publié** (`course-sheet.tsx`) : séances (la séance choisie dans l'agenda est surlignée, `aria-current`, visible), description, conditions ; à droite places, responsable, lieu, langue, durée, minimum, annulation libre. Un seul badge, seulement pour l'inhabituel (Brouillon, Annulé, Clos, Terminé). Séance introuvable : alerte, les séances actuelles restent listées.
- **Gérer** (menu de la fiche) : Modifier la capacité, Modifier les dates, Annuler toute la série. Réservé à un cours publié, à venir, que le serveur déclare gérable (`series.canManage`).
- **Capacité** (`course-changes.tsx`) : dialogue d'un champ ; les places déjà prises (et le minimum) sont donnés, le plancher est vérifié par `capacityProblem`.
- **Dates des séances** (`course-reschedule.tsx`) : mêmes séances, mêmes identifiants, même nombre ; on édite date, heures, moniteur, une séance à la fois ; la relecture montre chaque séance changée avec l'ancienne valeur barrée ; les inscrits concernés sont nommés avant l'envoi.
- **Annulation de toute la série** : dialogue (séances, inscrits concernés, motif obligatoire). Aucune annulation isolée de séance n'existe ni n'est inventée.
- **Règles des cours** (`course-policy-dialog.tsx`) : annulation libre (heures), délai de réponse à une place proposée (minutes, vide = liste d'attente désactivée). Bouton icône « Règles des cours » dans la barre de l'agenda.
- **Point d'entrée des participants** (`course-participants-slot.tsx`) : `CourseParticipantsEntry`, section `#course-participants` de la fiche. Il n'affiche que ce que la série porte (places prises et libres) et n'expose aucun contrôle menant à une vue vide. #329 remplace son corps sans toucher à la fiche.

## Décisions

- **Une seule règle, celle du modèle** : validation, corps des commandes, plancher de capacité, report à nombre constant et messages de refus viennent de `console/course-model.ts` ; ce lot n'en redéfinit aucune. `course-presentation.ts` ne porte que des libellés, des résumés et la comparaison de brouillons.
- **Commandes** (moteur existant, `If-Match`, version lue, `operationId`) : `createCourseType`, `createCourseSeries`, `updateCourseSeries`, `publishCourseSeries`, `changeCourseCapacity`, `rescheduleCourseSeries`, `cancelCourseSeries`, `saveCoursePolicy`. Aucun succès avant le reçu ; refus : la saisie reste, le message du serveur s'affiche près de son objet (refus de séance à côté de la liste des séances) ; conflit de version : « Relire, garder ma saisie » relit sans toucher au brouillon, la version envoyée suit la relecture ; réponse perdue : le panneau d'attente du coordinateur porte la vérification et les boutons se verrouillent.
- **Brouillon protégé** : `useUnsavedChanges` ; quitter un brouillon modifié propose Continuer, Enregistrer et quitter, Abandonner. La comparaison ignore les clés de séance et leur ordre : enregistrer ne laisse pas un brouillon « modifié ».
- **Impacts sans annulation silencieuse** : modifier un cours engagé nomme les inscrits concernés avant l'envoi ; aucune commande n'annule un inscrit.
- **Données d'un cours jamais nulles** : le chargeur renvoie un objet, pas `null`. Un `null` est lu comme « rien à l'écran » et démontait l'éditeur d'un nouveau cours à chaque confirmation (constaté en navigateur, corrigé).
- **Agenda** : la sélection `view=nouveau-cours` ouvre l'éditeur, `course` (+ `occurrence`) la fiche ou le brouillon ; l'ancien contexte en lecture est supprimé. Le retour rend le focus au bouton « Ajouter ». Enregistrer un nouveau brouillon met l'URL à jour sans quitter l'espace de cours.

## Aperçu synthétique

`families/planning.ts` : type prédéfinis et personnalisés, politique, un brouillon de deux séances, une série longue en brouillon (dix séances), un cours publié de quatre séances avec cinq inscrits, un cours annulé. Les écritures suivent les vraies routes ; `If-Match` est respecté ; refus crédibles par action (conflit de moniteur, conflit d'horaire à l'inscrit, accès) ; rendez-vous et séances publiées créent de vrais conflits.

## Vérifications exécutées (dans `apps/web`)

- `node node_modules/typescript/bin/tsc --noEmit` : code 0 ; `tsc -p tsconfig.check.json` : code 0.
- `node node_modules/vitest/vitest.mjs run` (suite complète) : 40 fichiers, 442 tests réussis. `test/portal-boundary.test.ts` n'existe pas dans ce worktree.
- `node node_modules/vite/bin/vite.js build --config vite.preview-311.config.ts` : réussi (garde des imports hérités sans erreur).
- Navigateur headless (Chromium via Playwright), aperçu sur le port 5192 : bureau 1440×900 clair et sombre, mobile 390×844 sombre ; menu Ajouter, création d'un type, brouillon vide (erreurs), séance, brouillon enregistré, revue, publication, fiche avec séance sélectionnée, capacité refusée sous les places prises puis modifiée, report relu et enregistré, annulation sans motif puis confirmée (badge Annulé, plus de menu Gérer), règles invalides puis enregistrées, série longue, cours annulé, parcours au clavier du menu Ajouter. Scénarios : refus, conflit de version (saisie gardée, relecture), réponse perdue à la publication (verrouillée, panneau de vérification), refus d'annulation (motif gardé), refus de report (dates gardées). Aucun débordement horizontal (`scrollWidth - innerWidth = 0`) ni erreur console sur les écrans captés.

## Reste à qualifier

Recette au clavier et au doigt réels, lecteur d'écran (annonce des refus de séance, bandeau de confirmation), changement d'heure dans une séance (le modèle refuse une heure inexistante ; l'heure répétée n'est pas proposée), très longs titres, 64 séances, raccord authentifié réel. Le cas « module des cours désactivé » n'est pas exécutable dans l'aperçu (les réponses de l'école y sont fixes) : la règle est testée en unité (`coursesManageable`), pas en navigateur. Aucune campagne API ou native lancée.

## Demandes au socle

- Sélecteur de date et d'heure : champs natifs (`date`, `time`) utilisés ; rien dans le socle ne couvre l'heure.
- Variante « à puces » de `Badge` pour l'état d'une ligne : contourné localement (badge secondaire).
- Alignement optique d'un bouton ghost « Retour » : marge négative locale (`.course-back`), comme pour les horaires.
