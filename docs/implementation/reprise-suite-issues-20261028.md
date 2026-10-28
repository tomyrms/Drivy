# Reprise : suite des issues non commencées (28 octobre 2026)

## Demande du porteur

Lister les issues ouvertes non commencées, réaliser ce qui est faisable (« fais tout »), livrer une IPA sans lancer les tests ; après son essai, quelques tests ciblés, fusion dans master, déploiement si nécessaire.

Branche : `claude/suite-issues-20261028`, partie de `claude/audit-ux-lots-5-8` (PR #188, elle-même empilée sur #186 et #187, autre session). Worktree : `Drivy-claude-suite-issues-20261028`. L'IPA d'essai se compile directement sur cette branche avec `-f messaging_qualification=true` : elle contient master, les lots 1 à 8 de l'audit UX et ce travail.

## Réalisé

| Lot | Tickets | Changement |
| --- | --- | --- |
| 1 Messages | #168, #177, #142 | Sourdine : le menu propose « Mettre en sourdine » (1 h, 8 h, 1 jour) ou « Réactiver » avec l'échéance ; un état jamais lu laisse les deux choix ; liste, bandeau et menu lisent la même valeur, relue à l'échéance. Refus d'une modification : l'appui ouvre la raison, « Actualiser » (conflit) et « Masquer » distincts ; l'erreur du bandeau a son bouton « Masquer ». Zones tactiles : pastilles de réaction côte à côte sans chevauchement, 44 pt de haut sans grossir la bulle (`MessagingHitArea`) ; reprises, sondage et icône d'erreur de la bulle citée à 44 pt. |
| 2 Cours (personnel) | #128, #129, #130 | `SchoolCourseAttendanceWorkspace` : une file par élève au lieu du verrou global `busyEnrollment`. Choix affiché aussitôt, jamais compté comme enregistré ; deux présences non parties = une demande ; version attendue figée au premier envoi ; « Réessayer » (même operationId) ou « Abandonner » (feuille relue) ; refus affiché sur la ligne ; une réponse ne remplace que la ligne de son élève. Règlement, annulation et retrait : la feuille se ferme aussitôt. |
| 3 Cours (élève) | #126 | `SchoolCourseLearnerWorkspace.submit` : la confirmation se ferme aussitôt, la fiche dit « Inscription en cours » à part de l'état de l'école ; non confirmée : Réessayer/Abandonner ; la demande survit à la fermeture de la fiche (`SchoolLearnerCoursesWorkspace.detail(for:)`). |
| 4 Profil | #118 | Photo affichée dès le cadrage (« en cours »), seul le dernier choix part ; compte et photo envoyés l'un après l'autre (même version de personne) ; échec : retour à la photo enregistrée et « Réessayer ». |
| 5 Bilan | #114 | La rédaction continue pendant l'envoi du bilan ; une saisie N+1 survit à la réponse de N, la fiche reste ouverte et la saisie est rebasée sur la version confirmée (pas de conflit). Sans saisie pendant l'envoi : fermeture inchangée. |

#119 : déjà réalisé côté natif le 26 octobre (`d85bd004`, `reactivite-native-106-107-119-20261026.md`) ; rien ajouté.

## Non fait, et pourquoi

- Lot 6 planification (#108, #109, #110) : une réservation « immédiate » suppose une file de commandes reprise hors de l'écran (aujourd'hui chaque écran reprend sa propre demande) et une projection des demandes en cours dans Aujourd'hui/Agenda. C'est le socle #106/#107 à étendre, pas un correctif local : chantier à part, à valider avec le porteur.
- Web des cours (#128-#130) : `CourseFactsSheet` garde un envoi à la fois par feuille (`useCommandRunner`), comme les autres sections web. L'appel se fait sur le terrain (app).

## Vérifications

| Vérification | Résultat |
| --- | --- |
| Essai du porteur sur l'IPA `226dee20` (build 427, avec Messages) | Validé (« tout est bon »), lots 1 à 5 |
| Tests métier, suite complète (runner Apple) | PASS sur `c1ce2dca` : 859 tests Swift Testing en 78 suites et suites XCTest, dont `MessagingMuteMenuTests`, `SchoolCourseSheetQueueTests`, les tests photo de `SchoolWorkspaceTests` et bilan N+1 de `SchoolLessonFinishTests` (run 40686053375) |
| Tests UI iPhone et iPad | PASS : `MessagingLatencyUITests`, `MessagingThreadUITests`, `MessagingFeatureCheckUITests`, `SchoolFormProtectionUITests`, `SchoolReportFlowUITests` (run 40686057743) ; `SchoolCourseJourneyUITests` 7/7 après correction sur `67f20dbc` (run 40694974479) |
| Défauts trouvés par la campagne | `try` imbriqué dans un `#expect` composé (compilation des tests) ; identifiant d'accessibilité propagé d'un `Label` ou d'un bloc à ses enfants (règlement en cours lu « Horloge », « Réessayer » de l'inscription introuvable). Corrigés. |
| Recette physique, VoiceOver, réseau dégradé réel | NOT_EXECUTED |

Fusion : PR vers master (iOS seul, aucun déploiement homelab).

## Pour Codex

« Lis docs/implementation/reprise-suite-issues-20261028.md, puis reprends au lot 6 (planification) s'il a été cadré avec le porteur. »
