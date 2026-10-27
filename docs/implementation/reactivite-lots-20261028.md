# Réactivité : lots A à D et ménage des issues (28 octobre 2026)

Demande du porteur : lister les issues ouvertes non commencées, réaliser les lots validés (« fais-les toutes »), livrer une IPA sans lancer les tests, puis, après son essai, quelques tests ciblés, fusion dans master et déploiement si nécessaire.

Branche : `claude/reactivite-20261028` (base `b090f2d`). IPA d'essai : branche d'intégration `claude/integration-20261028` = `claude/integration-lots-1-8-20261028` (lots 1 à 8 de l'audit UX et fil Exyte #184, autre session) + cette branche. Ne jamais fusionner la branche d'intégration.

## Réalisé

| Lot | Ticket | Changement |
| --- | --- | --- |
| A | #112 | « Signaler » : les signalements d'une leçon forment une file. Chaque geste est écrit dans la file chiffrée avant de rendre la main, puis les gestes partent dans l'ordre, un à la fois, même opération et même instant au renvoi. Sans réseau, « Signaler » reste ouvert (avant : un seul signalement possible tant que le premier n'était pas confirmé). Règle de conflit de la file scolaire : deux créations d'observation de la même leçon, même portée, ne se bloquent plus ; elles restent une barrière pour le reste du domaine pédagogique (fin de leçon, autre leçon, autre époque). Double appui du même geste refusé (même instant d'ouverture) ; deux gestes identiques distincts sont gardés. Un geste encore en file derrière un autre, jamais parti, s'annule localement ; sinon l'annulation garde son retrait durable. Plafond : 30 signalements en file. La palette (ordre, affichage) était déjà immédiate et coalescée. |
| A | #113 | Préparation : objectifs, note et souhait restent modifiables pendant leur envoi ; la fiche n'est plus retenue. À la relecture, la révision confirmée sert de point de départ : une saisie poursuivie pendant l'envoi est gardée, ni remplacée ni prise pour un conflit, et s'enregistre ensuite sur la nouvelle version. Pas de persistance locale ajoutée pour la préparation (le coffre chiffré ne concerne que le bilan). |
| B | #111 | Reprise après une pause : le segment GPS rouvre sans attendre l'école, sur le bail local encore valable (comme après une perte de signal). L'école est relue ensuite : trajet clos pendant la pause ou accès refusé, la collecte s'arrête et se scelle, positions conservées ; école injoignable, rien ne change. Pause et arrêt étaient déjà locaux. Démarrage inchangé : il exige toujours les autorisations du serveur. |
| C | #115 | Replay : un trajet synchronisé déjà ouvert pendant la session se rouvre aussitôt depuis un cache en mémoire (3 trajets au plus), jamais sur disque, lié au compte, à l'école, à l'adhésion et à l'époque d'accès, vidé à la déconnexion et à tout refus. Une seule lecture du trajet confirme sa version et sa synchronisation ; sinon les pages se relisent comme avant. L'historique des trajets gardait déjà sa liste au retour. |
| C | #117 | Progression : la lecture de la progression part en même temps que celle des leçons ; seul le dernier bilan évalué attend la liste. Le cache des formations (`SchoolTrainingModelCache`) existait déjà. |
| D | #121, #122 | Web : la ligne d'une invitation affiche « Renvoi en cours » ou « Révocation en cours », celle d'un membre « Modification en cours » ou « Retrait en cours », tant que la demande est suivie ; une création annonce « Création d'une invitation en cours » sans inventer de ligne ni de code. Ces états ne débloquent aucun droit. |
| D | #123 | Web : les coordonnées de l'école restent modifiables pendant leur enregistrement ; `useDraft.markSaved(value, sent)` garde une saisie poursuivie depuis l'envoi, qui reste à enregistrer, et ne relâche la protection de sortie que sans saisie restante. |
| E | — | Issues livrées fermées avec leurs commits (toutes dans la release `54b6ea9`) : #38 à #42, #79 à #82, #51, #88, #98, #100 à #104, #141, #143, #162, #163, #169, #170 ; #75 renvoyée à #97. #174 était déjà fermée. |

Déjà en place à l'ouverture et seulement constaté : file web par opération avec clés de conflit, cache de lecture et relecture en arrière-plan (#106/#107 web, `dbd868b`) ; brouillons des formations et tarifs (#124).

## Vérifications

| Vérification | Résultat |
| --- | --- |
| `npm run typecheck` dans `apps/web` | PASS |
| `npx vitest run` dans `apps/web` | PASS, 34 fichiers, 401 tests |
| Compilation de l'app (IPA, runner Apple) | voir STATUS.md ; l'IPA ne compile pas la cible de tests |
| Tests Swift ajoutés ou adaptés | NOT_EXECUTED : `SchoolLiveObservationRecorderTests` (file, ordre, hors réseau, annulation locale), `SchoolLiveObservationUndoTests`, `SchoolObservationRefusalTests`, `SchoolCommandSchedulingTests` (règle de conflit), `SchoolLessonPreparationReactivityTests` (nouveau), `SchoolCaptureLifecycleTests` (reprise sans attendre l'école), `SchoolCaptureReplayTests` (cache) |
| Recette physique GPS, réseau dégradé réel, VoiceOver | NOT_EXECUTED |

## Reste à qualifier ou à faire

- #112 : correction et retrait après la leçon restent une demande à la fois (écran des observations) ; « Signaler » depuis l'écran sans GPS ne rouvre pas tant qu'une file y attend sans réseau (prudence conservée, le trajet en direct est le cas visé).
- #113 : aucune persistance locale de la préparation après fermeture de la fiche.
- #111 : démarrage (préparation, autorisation) non modifié.
- #115 : pas de mesure de rendu ni de mémoire ; le cache ne couvre que les trajets synchronisés.
- #121 à #124 : un seul envoi à la fois par section (le coureur de commandes de chaque section reste séquentiel) ; catalogue (#124) inchangé.
- Tickets à garder ouverts : #37 (reste #83), #43/#44 (APNs non activé avec iLoader), #50 (pas de SMTP), #65 à #74, #76 à #78 (non vérifiés un à un), #97, #52, #54 (règles à fixer par le porteur).

## Pour Codex

« Lis docs/implementation/reactivite-lots-20261028.md, puis reprends à l'étape : essai du porteur, tests ciblés listés ci-dessus sur runner Apple (`unit_only`), PR de `claude/reactivite-20261028` vers master, déploiement web sur le homelab (seul `apps/web` a changé côté serveur). »
