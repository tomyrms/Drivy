# Cours collectifs et protection des formulaires — 26 octobre 2026

Travail de #99 (A30, A31, A32, A33, A34, A37, A38, A39) et volet planification/cours de #143, dans `codex/bilans-reactivite-parcours-20261026`. Base intégrée `ee2192c` (agenda #178 et travail conservé de la branche). Références lues : `COMMENCER_ICI.md`, `DESIGN.md`, F18/R55–R69, contrats AP126 et suivants, recette T097 et suivants, décisions effectives `cours-collectifs-cadrage-79.md`, corps/commentaires #99 et #143. Les contrats effectifs sont les extensions `courses.ts`, `course-enrollments.ts`, `course-facts.ts` ; aucun contrat canonique ni serveur de cours modifié ici.

## Changements

| Point | Réalisation |
| --- | --- |
| A30 | Le sélecteur natif réutilise `SchoolLearnerPicker` et son index complet, sans `prefix(20)`. Recherche insensible aux accents ; homonymes distingués par les références déjà utilisées dans l’app. L’admissibilité affichée exclut inscrits actifs, liste d’attente et archives ; les permissions restent relues au serveur. Même distinction des homonymes dans le sélecteur web. |
| A31 | Toutes les inscriptions actives et validations possédant une série ouvrent `SchoolCourseLearnerView`. Les séries suivies absentes du catalogue à venir sont relues par identifiant ; une panne de la progression n’empêche plus cette relecture. Le prochain horaire tient compte d’une séance en cours. Les engagements ne sont pas répétés dans Disponibles. |
| A32/A33 | Titre réel, état, prochaine date, lieu, volume et action avant les détails. Description réelle distincte des conditions. Dates et conditions accessibles par dévoilement progressif ; récapitulatif complet obligatoire avant inscription ou acceptation de place, avec toutes les dates, obligations, conditions et échéance. Une proposition expirée ne peut plus être confirmée localement. |
| A34 | Séances compactes dépliables dans l’éditeur natif et web. Suppression de l’aperçu permanent doublant toutes les dates ; vérification complète au moment de publier. Le brouillon web repris garde des clés de séance stables : une lecture seule ne déclenche plus une fausse alerte de modifications. La langue d’un brouillon web est conservée lors d’une réécriture native. |
| A37 | Modes locaux Appel, Règlements, Validation selon les droits de la feuille. L’accès aux règlements ne dépend plus d’une séance commencée. Appel : compteur renseignés/inscrits, filtre À renseigner, aucun paiement ni validation mêlé aux boutons de présence. Les états métier restent indépendants. |
| A38 | Confirmation « Ton inscription aux 4 séances sera annulée » (singulier adapté). Annulations nominatives dans une action contextuelle, confirmation explicite de toute la série. Le motif reste après erreur. |
| A39 | Entrée Messages existante, limitée à son contexte autorisé, avec e-mail de l’école en alternative. Aucun envoi ou retrait implicite. Le contrat cours expose une adhésion responsable et aucun `personId` : aucune correspondance par nom ni permission nouvelle ; l’utilisateur choisit son interlocuteur dans les contacts autorisés. |

L’entrée « Cours collectifs » de Leçons est nommée. Une prochaine séance inscrite apparaît dans l’entrée existante, avant l’accès au catalogue. Aucun nouvel onglet global, deuxième agenda, prix supposé ou règle commerciale ajouté.

Pour #143, planification et déplacement enregistrent un instantané au premier geste réel de l’utilisateur ; chargement et suggestion automatique ne marquent pas le formulaire modifié. Fermer demande de choisir si la saisie a changé, le glissement est protégé, une demande déjà dans l’outbox conserve sa propre récupération. Les lectures de l’outbox de planification sélectionnent désormais le domaine `teaching` du socle #106.

Le volet profil est réalisé par le lot commun dans `SchoolMyProfileView` : protection préexistante des changements et de l’envoi conservée, action « Continuer » explicite pour rester dans le formulaire. `SchoolFormProtectionUITests` couvre profil propre, saisie et conservation après Continuer ; exécution Apple à joindre, sans prétendre l’avoir réalisée sous Windows.

Un cours neuf inchangé peut se fermer directement, y compris après chargement de ses valeurs par défaut. Après modification, l’éditeur propose de continuer, abandonner explicitement ou enregistrer le brouillon. Une réponse incertaine à l’éditeur bloque la modification des champs et la fermeture ; « Réessayer la demande » reprend l’intention et l’identifiant en mémoire. Les formulaires de règlement, annulation d’inscription et retrait de règlement/validation conservent leur saisie après erreur et demandent confirmation avant abandon. Aucune persistance en clair ajoutée.

## Vérifications exécutées

| Vérification | Résultat / preuve |
| --- | --- |
| `npm run typecheck` dans `apps/web` | PASS, TypeScript client et vérification des tests. |
| `npm run build` dans `apps/web` | PASS. Avertissement préexistant du script classique `theme-init.js`, compilation terminée. |
| `npm run test -- test/course-model.test.ts test/person-reference.test.ts` | PASS, 32 tests. Régression de stabilité des identifiants de séance ajoutée. |
| Revue navigateur local sur fixture synthétique `test/visual.html?page=course&agenda=course-review` | PASS : modes séparés, règlements accessibles avant première date, recherche « Zoe » retrouvant les deux homonymes après les 30 autres candidats. |
| Même fixture avec `draft=1` | PASS : fermeture inchangée directe ; après modification, choix explicite ; Retour conserve le titre ; publication ouvre les quatre dates, les exigences et les conditions avant son bouton final. Le test réel a révélé puis permis de corriger les clés aléatoires causant une fausse alerte. |
| Captures web sombres, données fictives | `proofs/cours-20261026/web-publication-review-dark.png`, `web-payments-dark.png`, `web-participant-homonyms-dark.png`. Captures après modifications ; aucune mesure avant/après inventée. |
| `git diff --check` | PASS. |
| Swift / XCTest / IPA | NOT_EXECUTED localement (Windows) ; compilation et exécution sur runner Apple à rattacher à la livraison commune. |

Tests Apple ajoutés dans `SchoolCourseClientTests` : brouillon neuf propre/modifié/revenu à sa valeur ; langue conservée ; séance courante/suivante/terminée ; droits indépendants ; texte d’annulation ; 32 candidats et homonymes ; inscription hors catalogue avec progression indisponible ; état de la confirmation.

`SchoolCourseJourneyUITests` contient six parcours sur les vraies vues : recherche des homonymes au-delà du vingtième, ouverture d’un cours commencé, récapitulatif d’inscription, sens de l’annulation, règlement avant séance avec maintien du montant, protection du titre modifié. Fixtures `course-learner`, `course-enrolled`, `course-list`, `course-editor`, `course-roster`, `course-attendance`, `course-payments-before-start` intégrées au harnais DEBUG simulateur et à la liste des captures. Transport exclusivement synthétique ; toute mutation échoue sans serveur.

## Qualification restant à joindre

Les lots A/F de #99 ne sont pas déclarés entièrement qualifiés : captures natives avant/après identiques, iPhone étroit/courant, iPad, clair/sombre, clavier et grands textes ; VoiceOver physique ; offre proche de l’expiration, retrait de droits, conflit et réseau lent en situation intégrée. La revue Windows ne remplace pas ces essais. Le rapprochement du responsable du cours vers une conversation directe n’est pas inventé à partir de son nom : l’entrée de contacts autorisés est la solution disponible sans extension d’API.

Les commandes natives de cours conservent encore leur intention en mémoire ; leur reprise durable après arrêt forcé reste dans les lots dédiés #126–#130. Ce changement ne prétend pas livrer leur refonte de réactivité. Aucun déploiement effectué.
