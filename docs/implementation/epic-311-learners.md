# #311 — pilote dossier élève #324

Branche de travail : `codex/311-learners`, socle coordinateur intégré jusqu’à `216468c2`. Travail repris après le retour positif du porteur sur le pilote Accès. Seuls `client/portal/learners/*` et cette note sont modifiés par cet agent.

## Réalisation

- Annuaire neuf : recherche nom/contact, dossiers actifs/archivés, profils à compléter, tri et pagination conservés ; contact secondaire pour les homonymes, aucune photo ou donnée inventée. La couverture partielle est annoncée.
- Fiche reconstruite : identité, contact et planification ; trois domaines Suivi, Formations et Informations. Le suivi présente prochaine leçon, objectif du dernier bilan, compétences nommées et sourcées, historique filtrable. Aucun score pédagogique calculé.
- Lecture dédiée d’un bilan et de ses révisions, avec date de la leçon dans son fuseau historique. Une leçon sélectionnée depuis Agenda est relue directement et contrôlée contre l’école et l’élève ; retour conserve les paramètres d’agenda transmis.
- Administration déplacée dans des vues dédiées : formation courante ou ancienne, affectations et leur historique, permis accepté/refusé/expiré et vérifications précédentes, transitions et leurs motifs, ouverture de formation. Les programmes restent reliés à leur offre versionnée, conformément à #253.
- Informations administratives : coordonnées autorisées, complétion des seuls champs bloquants de la politique active, relecture puis confirmation, conflit de version conservant la saisie. L’API administrative ne fournit pas les valeurs complètes d’identité : aucune édition générale de valeurs inconnues n’est inventée.
- Archivage/restauration réservé aux droits administrateur, consentement GPS lu sans action permettant de l’accorder à la place de l’élève. Les notes privées ne sont jamais ajoutées aux bilans partagés.
- Prérequis suisses par démarche, détail sourcé et faits internes de cours : présence, inscription et accomplissement restent distincts d’une attestation officielle ou d’une dispense. Aucun GPS obligatoire activé.
- Rendu responsive propre, tokens du socle clair/sombre, vrais composants shadcn/Base UI, champs Field/FieldGroup, Checkbox de confirmation et Dialog titrés. Aucun ancien JSX ni ancienne feuille de style importés.

## Garanties conservées

Les contrôleurs ne copient pas de présentation. Ils réutilisent les schémas, commandes, modèles purs, `ConsoleContext`, registre de brouillons et moteur d’écriture existants. Les appels restent scolaires ; les commandes emploient leur operationId et, lorsque requis, If-Match et version. Aucun succès ne précède la confirmation durable. Erreurs, refus, reconnexion et commande en attente restent visibles. Les changements destructifs demandent leur confirmation explicite.

Une liste partielle de références ou de formations bloque les modifications. Un historique incomplet de contrôles ne produit pas de prétendu dernier permis ; les affectations d’une autre formation sont refusées. Les valeurs de formulaire restent en mémoire pendant les erreurs, sous les gardes de navigation de la console.

Sources : `COMMENCER_ICI.md`, règles R01/R02/R11/R12/R17, contrats et scénarios élève/formation/affectation/permis/profil ; `simplification-253-20261028.md`, `regles-suisses-20261028.md`, sources pures `command-core`, `dossier-model`, `profile-completion-model`, `learner-course-facts`, `swiss-prerequisites`. Direction UI affinée avec `ui-skills-root` → `subtractive-design` : lecture quotidienne prioritaire et gestion secondaire.

## Vérification et suites

- TypeScript client (`tsc --noEmit -p apps/web/tsconfig.json`) : PASS.
- TypeScript vérifications web (`tsc -p apps/web/tsconfig.check.json`) : PASS.
- Pas de grande campagne de tests, de migration, de modification API/contrat ou de déploiement par cet agent.
- Raccord, build de l’aperçu et exécution desktop/mobile clair/sombre assurés par le coordinateur sur le SHA intégré. Aucune preuve visuelle ni validation du porteur revendiquée dans cette note avant cette exécution.
- Trajets détaillés et invitation d’un élève sont d’autres familles de #311 ; aucun bouton menant à une vue vide n’est exposé dans ce pilote. Leur raccord reste explicitement à réaliser lors de la généralisation. Les contextes de leçon et bilans lisibles sont disponibles ici.
- Focus exact de retour Agenda, refus/attente via fixtures, textes longs, clavier, mobile et accès révoqués restent à vérifier dans l’aperçu intégré. La seule compilation ne clôture pas #324.

## Appels nécessaires à l’aperçu

GET `learners?status=ALL`, `learners/:id`, `trainings` et filtre `learnerId`, `offerings`, `members`, `curricula`, `trainings/:id/assignments`, `trainings/:id/permit-checks`, `trainings/:id/progress`, `lessons?trainingId`, `lessons/:id`, `lessons/:id/reports`, `learners/:id/action-readiness?action=PLAN_LESSON`, `learners/:id/administrative-profile`, `recording-choices`, `learners/:id/course-facts`.

Commandes : ouverture/transition de formation, création/fin d’affectation, contrôle de permis, archivage/restauration, mise à jour du profil administratif. Réponses synthétiques uniquement dans le runtime d’aperçu commun, jamais dans le composant produit.
