# Reprise — revue UI/UX native du 4 octobre 2026

Document de passation. Il permet à une autre session (Codex, Claude) de reprendre ce chantier sans l'historique de la conversation. **Il est tenu à jour à chaque étape : la section « État des lots » fait foi.**

Dernière mise à jour : 4 octobre 2026, après essai de build100. Les huit lots sont intégrés, le logo et les icônes livrés ; les longues campagnes Apple restantes ont été arrêtées à la demande du porteur. Les feuilles natives stables de build100 sont validées par son retour. IPA build101 compilée et livrée : [prochaines leçons, palette Signaler et confirmation de fin](today-signal-finish-20261004.md). Voir [STATUS](STATUS.md) pour la dernière IPA et les limites, [résultats de la revue initiale](native-ui-review-20261004.md) et [icônes](native-icon-signal-review-20261004.md).

Dernier retour : après build102, le dossier commence par la fiche de l’élève puis ouvre Leçons/Progression sur des pages séparées ; tarif affiché sans fenêtre, Signaler légèrement agrandi. [Décision courante](dossier-pages-tarif-signaler-20261004.md). IPA build103 compilée et vérifiée sur `9603eb3` (run37219639586) ; STATUS indique la livraison. Aucun nouveau test Apple ni capture. Le suivi samaritains/sensibilisation reste une tranche métier à implémenter.

## Pour reprendre (à lire en premier)

1. Lire `AGENTS.md`, puis ce document en entier.
2. `git status --short -- apps docs` et `git log --oneline -15` : ce qui est committé est relu ; ce qui est seulement modifié dans l'arbre de travail vient d'un lot peut-être interrompu.
3. Pour chaque lot non terminé (tableau ci-dessous) : relire `git diff -- <ses fichiers>`, vérifier que chaque fichier est entier (accolades, pas de fonction coupée), comparer au cahier du lot, terminer ou refaire.
4. Suivre « Ce qu'il reste à faire » dans l'ordre.

Phrase à donner à Codex : « Lis docs/implementation/reprise-revue-ui-20261004.md et continue le chantier là où il s'est arrêté, en respectant AGENTS.md et les skills indiqués. »

## Demande du porteur (4 octobre 2026)

Continuer à analyser et améliorer l'app native avec tous les skills pertinents, **surtout Impeccable**, à chaque étape et pas seulement au début : les consulter, appliquer leurs recommandations et s'en servir pour vérifier.

1. **Page « Aujourd'hui » du moniteur** : « encore un peu bof visuellement » ; améliorer présentation, hiérarchie des informations, utilisation de l'espace.
2. **Démarrer une leçon** : le permis B est présélectionné après le choix de l'élève ; vérifier que c'est cohérent.
3. **Chargements** : il manque des squelettes (skeletons) ; en ajouter là où c'est pertinent.
4. **Leçon en cours** : le bouton « Annuler la leçon » prend trop de place et est trop visible ; le rendre discret. Évaluer « la croix annule + on quitte par la barre d'onglets » contre « masquer la barre d'onglets pendant la leçon », en distinguant quitter l'écran et annuler la leçon.
5. **Carte** : les mentions légales Apple Plans se retrouvent au milieu de l'écran ; les replacer en les gardant visibles.
6. **Tracé GPS** : « vraiment incohérent » ; trouver la cause et le rendre fiable (pas seulement esthétique).
7. **Revue générale** : passer les fonctionnalités existantes une par une (fonctionnement, cohérence, complétude, UI/UX), corriger, compléter, améliorer.

Le porteur a aussi demandé que le travail soit fait par des agents en parallèle, et que Codex puisse le reprendre.

## Où en est le dépôt

- Branche `codex/revue-integration-20260929`, à jour avec `origin` au commit `fef94bf` au début du chantier.
- Modifications **étrangères au chantier, à ne pas committer ni annuler** : `.claude/skills/**` (modifiés et non suivis), `docs/implementation/native-account-dossier-review-20260930.md`, `Drivy-correctif-captures-ios.patch`, `Drivy-fix-permit-dialog-test-v2.patch`.
- Préparation déjà faite : la carte du trajet en cours a été extraite telle quelle de `SchoolCaptureLiveView.swift` vers `apps/ios/Drivy/SchoolCaptureUI/SchoolCaptureLiveMap.swift` (struct `SchoolCaptureLiveMap`, initialiseur inchangé) pour séparer l'écran et le tracé.

## Constats établis par lecture du code

- **Permis B présélectionné : cohérent.** `SchoolStartNowWorkspace.select()` appelle `SchoolPlanningDefaults.trainingID(in:)` (`SchoolAgendaAPI/SchoolPlanningClient.swift`) : l'unique formation active est prise ; avec plusieurs, la catégorie préférée si elle est unique, sinon aucun choix d'office. La vue affiche une ligne fixe avec une formation, un sélecteur avec plusieurs. Cas limites à confirmer par le lot 2.
- **Mentions Apple Plans** : en disposition compacte, les deux commandes de carte sont dans le `safeAreaInset` du bas, au-dessus du panneau ; MapKit pose sa mention au-dessus de l'ensemble. Correctif retenu : commandes en `.overlay(alignment: .bottomTrailing)` sur la carte **avant** le `.safeAreaInset(edge: .bottom)`, panneau plus court. Rendu réel à contrôler sur capture Apple.
- **Tracé GPS, hypothèse principale non prouvée** (aucune trace réelle disponible) : `SchoolCaptureLocationSource.didUpdateLocations` admet toute position valide sans seuil de précision horizontale ; rien n'écarte un saut invraisemblable ; la dérive à l'arrêt est tracée ; marqueur et caméra suivent le dernier point brut. À vérifier aussi : `observationAnchor` prend l'index du tableau affiché comme `pointSequence` ; ordre des points, lots et pages dans `SchoolReplayTimeline`.
- Cadre non négociable du correctif GPS : aucune position inventée (ni lissage, ni interpolation, ni recalage routier) ; on choisit parmi les mesures réelles celles qui sont tracées et on laisse une lacune visible ; une seule règle pure et testée, partagée par la carte en direct et le replay ; stockage, transfert et contrat OpenAPI inchangés sauf nécessité prouvée.

## Décisions prises (le porteur en est informé)

- **La barre d'onglets reste visible pendant une leçon.** Quitter l'écran = changer d'onglet, la leçon continue ; l'onglet « Aujourd'hui » signale la leçon en cours (symbole `location.fill`, valeur accessible « Leçon en cours »).
- **La croix ne devient pas l'annulation** (sur iOS elle signifie fermer). « Annuler la leçon » passe dans un menu « Plus d'actions » (ellipsis, disque 48 pt) à droite de la barre du haut, avec « Voir la leçon ». Le formulaire d'annulation avec motif reste la confirmation. Identifiants : `capture-more`, `capture-cancel-lesson`.
- En racine d'onglet, plus de bouton à gauche de la barre ; dans la fiche de leçon (écran poussé), un retour `chevron.left`. Paramètre prévu : `isTabRoot: Bool = false` sur `SchoolCaptureLiveView`.
- La rangée « Annuler la leçon » disparaît du panneau du bas.
- **Réserve** : le porteur peut encore préférer la croix ; il a été invité à le dire.

## Composant de squelettes (contrat commun à tous les lots)

Fichier `apps/ios/Drivy/UI/DrivySkeleton.swift`, écrit par le lot 1 :

```swift
struct DrivySkeletonBlock: View { init(width: CGFloat? = nil, height: CGFloat = 14, radius: CGFloat = 6) }
struct DrivySkeletonRow: View { enum Leading { case none, avatar, time }; init(leading: Leading = .none, lines: Int = 2) }
struct DrivySkeletonRows: View { init(count: Int = 4, leading: DrivySkeletonRow.Leading = .none) }
extension View { func drivySkeleton(_ label: String) -> some View }
```

Règle d'emploi : squelette pour le premier chargement d'un contenu de forme connue (listes, fiches) ; `DrivyLoadingState` (spinner et texte) pour une opération en cours et pour « charger la suite » ; jamais de squelette à la place d'un contenu déjà affiché pendant une relecture. Balayage immobile avec Réduire les animations ; un seul élément VoiceOver portant le libellé.

## État des lots

Chaque lot possède ses fichiers ; personne d'autre ne les modifie. Les signatures existantes restent compatibles (nouveaux paramètres avec valeur par défaut), car les tests et les bancs visuels `apps/ios/Drivy/UI/*VisualReview.swift` les utilisent.

| Lot | Sujet | Fichiers possédés | État |
|---|---|---|---|
| 1 | Composant de squelettes ; compte, onglet Profil, liste des trajets | `UI/DrivySkeleton.swift`, `UI/DrivyDesignSystemGallery.swift`, `UI/DrivyComponents+Accueil.swift`, `SchoolUI/SchoolRootView.swift`, `SchoolUI/SchoolAccountComponents.swift`, `SchoolTripsUI/*`, tests `SchoolTripsTests`, `SchoolPresentationIdleTests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |
| 2 | Page « Aujourd'hui », « Démarrer une leçon » | `SchoolUI/SchoolTodayView.swift`, `SchoolAgendaUI/SchoolStartNowView.swift`, tests `SchoolStartNowClientTests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |
| 3 | Leçon en cours : actions, navigation, mentions légales ; onglets | `SchoolCaptureUI/SchoolCaptureLiveView.swift`, `SchoolLiveObservationSheet.swift`, `SchoolCaptureLiveObservations.swift`, `SchoolObservationEmblem.swift`, `UI/DrivyComponents+Seance.swift`, `SchoolUI/SchoolHomeView.swift`, tests `FieldFlowTests`, `SchoolLiveObservationRecorderTests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |
| 4 | Fiabilité du tracé GPS ; écran de replay | `SchoolCaptureUI/SchoolCaptureLiveMap.swift`, `SchoolMapCourse.swift`, `SchoolCaptureReplayView.swift`, `SchoolCaptureReplayWorkspace.swift`, `SchoolCaptureCore/*`, `SchoolCaptureAPI/*`, tests `SchoolMapCourseTests`, `SchoolCaptureLifecycleTests`, `SchoolCaptureInteropTests`, `SchoolReplayFormattingTests`, `DrivyTimelineMarkGroupTests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |
| 5 | Agenda et planification | `SchoolAgendaUI/SchoolAgendaView.swift`, `SchoolPlanningView.swift`, `SchoolPlanningWorkspace.swift`, `SchoolPlanningSettingsView.swift`, `UI/DrivyComponents+Agenda.swift`, tests `SchoolPlanningDefaultsTests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |
| 6 | Élèves, dossier, formation, progression (moniteur et élève) | `SchoolUI/SchoolBrowserView.swift`, `SchoolUI/SchoolWorkspace.swift`, `SchoolTrainingUI/*`, tests `SchoolDossierTests`, `SchoolTrainingRefreshTests`, `SchoolWorkspaceTests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |
| 7 | Fiche de leçon, bilan, observations, préparation du trajet | `SchoolLessonReportUI/*`, `SchoolObservationUI/*`, `SchoolCaptureUI/SchoolCapturePreparation*.swift`, `SchoolRecordingChoice*.swift`, tests `SchoolLessonFinishTests`, `SchoolLessonHubTests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |
| 8 | Invitations, entrée dans une école, profil, accueil guidé | `SchoolInvitationsUI/*`, `SchoolJoinUI/*`, `SchoolProfileUI/*`, `UI/DrivyComponents+Ecole.swift`, tests `SchoolInvitation*Tests`, `SchoolProfile*Tests` | intégré ; première campagne exécutée, attente finale arrêtée par le porteur |

Chemins relatifs à `apps/ios/Drivy/` (tests : `apps/ios/DrivyTests/`, `apps/ios/DrivyUITests/`). Fichiers partagés sans propriétaire, à ne modifier qu'à l'intégration : `UI/DrivyComponents.swift`, `UI/DrivyTheme.swift`, `UI/*VisualReview.swift`, `DrivyTests/SchoolPresentationTests.swift`.

### Cahier de chaque lot

Méthode commune des lots de revue (1, 5, 6, 7, 8) : inventorier chaque état de chaque écran (chargement, vide, erreur, succès, désactivé, hors ligne, demande incertaine, contenu long, grand texte, iPad) ; critique Impeccable classée P0 (parcours cassé ou trompeur) à P3 (finition) ; corriger P0 à P2, P3 si peu coûteux ; compléter un manque fonctionnel seulement s'il est petit et sans changement d'API serveur ; poser les squelettes ; mettre à jour les tests si une logique change.

- **Lot 2, Aujourd'hui** — pistes relevées : aucune lecture du moment (« dans 12 min », « en cours », « en retard ») ; titre de barre sans date ; « Leçons du jour N » compte la leçon mise en avant que la liste exclut ; leçons passées au même poids que les suivantes ; leçon suivante invisible quand une leçon est « À terminer » ; état vide pauvre ; chargement en spinner ; localisation jamais demandée ou refusée sans action proposée (« Autoriser la localisation », « Ouvrir Réglages ») ; mention Apple Plans. Règles métier et identifiants `today-*` inchangés.
- **Lot 3, leçon en cours** — appliquer les décisions ci-dessus ; critique de tous les états (préparation, attente de position, pause, arrêt, sauvegardé, échec), de la feuille de signalement ; squelette pour le chargement du dossier de l'élève dans `SchoolHomeView.learnerStatus`.
- **Lot 4, tracé GPS** — débogage systématique de toute la chaîne (collecte, stockage, affichage en direct, replay, serveur en lecture seule) ; règle d'affichage pure et testée (précision maximale tracée, vraisemblance de vitesse, verrou à l'arrêt, coupure des lacunes) ; marqueur, cap, caméra, vue d'ensemble et ancres de signalement sur les points retenus ; tests de cas réels (départ imprécis, saut isolé, arrêt avec dérive, giratoire lent, tunnel, lots en désordre, deux segments, ancre sur point écarté). Si le serveur est fautif : correctif et test dans `apps/api`, **sans déploiement**.

## Skills à utiliser

Les skills sont des dossiers `.claude/skills/<nom>/` : lire `SKILL.md` puis ses fichiers de référence (une session sans outil Skill les lit directement).

- **impeccable** : `SKILL.md`, puis `reference/ios.md`, `operate.md`, `critique.md`, `polish.md`, et `craft-floor.md` juste avant toute édition d'interface ; selon le cas `layout.md`, `harden.md`, `clarify.md`, `distill.md`, `quieter.md`, `onboard.md`, `audit.native.md`, `adapt.native.md`, `animate.md`. `impeccable context` a été exécuté : pas de `PRODUCT.md`, `DESIGN.md` fait autorité, mode Operate, plateforme iOS. C'est un raffinement : l'identité native (tokens, police système, composants Drivy) est conservée.
- Compléments : `swiftui-ui-patterns`, `write-swift`, `apple-hig`, `apple-design-hig`, `mobile-native`, `interaction-design`, `accessible-animation`, `better-accessibility`, `interactive-hit-areas`, `balise-ux-writing`, `better-writing`, `swiftui-liquid-glass` (seulement pour les commandes flottant sur la carte).
- Chaque changement se rattache à une recommandation précise d'un skill dans le compte rendu.

## Contraintes

- Aucune toolchain Swift sur ce PC Windows : rien ne se compile localement. N'employer que des API déjà présentes dans le dépôt ou certaines pour le SDK iOS 26 ; découper les `body` longs ; relire chaque fichier modifié en entier.
- XcodeGen : un fichier ajouté dans un dossier source est pris automatiquement.
- Compilation : le workflow « IPA d'essai · iLoader » se lance à chaque push sur `codex/**` qui touche `apps/ios/Drivy/**`. Tests et captures Apple : `gh workflow run "Refonte · iOS" --ref codex/revue-integration-20260929`, puis `gh run watch`.
- Ne jamais forcer la signature GPG ; pas de `git reset --soft` suivi de `git add -A` ; jamais de force-push.
- GitGuardian rescanne tous les commits : dans les tests, utiliser `testCredential` de `helpers.ts`, jamais `password:` ni `TEST_PASSWORD`.
- Aucun secret, jeton, donnée de personne ni position dans les logs ou artefacts.
- Documents écrits par script (Python en UTF-8), pas par un outil qui les ouvre à l'écran du porteur.
- Aucun déploiement du homelab n'est nécessaire tant que seul `apps/ios` change. Un changement d'API demande une sauvegarde de la base avant déploiement et l'accord du porteur.

## Livraison et qualification restante

L’IPA **0.7.0/build98** (`e36b0d4`) a compilé avec succès dans `37210789141`, puis a été téléchargée et vérifiée. Le porteur demande de la recevoir sans attendre tous les tests ; les campagnes encore actives/en attente sont arrêtées. La [PR5](https://github.com/tomyrms/Drivy/pull/5) est ouverte, attachée au chat et sortie du brouillon. Aucun déploiement.

- Les résultats exécutés et les captures inspectées sont dans [la revue](native-ui-review-20261004.md) et sa preuve JSON.
- Les tests ajoutés après la campagne initiale, la revalidation du sélecteur iPad et les nouvelles captures de la fixture Aujourd’hui/logo ne sont pas supposés réussis. Reprendre ces qualifications uniquement lorsqu’elles sont demandées.
- Qualification physique : route GPS, batterie, VoiceOver, gestes et mentions Apple Plans sur iPhone. Signature de l’IPA avec iLoader par le porteur.

## Journal

- 4 octobre 2026 : diagnostic par lecture, extraction de `SchoolCaptureLiveMap.swift`, huit lots lancés en parallèle. Rien n'est compilé ni testé.

- Reprise active : trois agents travaillent sur 2/5 puis 8, 4, 6/7. Intégration 1/3 par l’agent principal. Squelettes communs repris ; erreur école visible dans Trajets ; annulation déplacée dans le menu ; onglets conservés et contrôles carte séparés du dock. Aucune compilation Swift locale. Nouveau harnais `skeletons` et fixture live dans les vrais onglets pour les captures Apple. Les tests Python de capture ne sont pas exécutables ici via le bash WSL absent ; la CI Linux les exécutera.

- Intégration : lots 1–8 implémentés et committés séparément. Relecture A : disponibilités après relecture, conflit de préférences, explications ciblées de validation corrigés ; purge du démarrage après refus d’accès en finition. Relecture B indépendante en cours. Syntaxe Bash vérifiée avec Git Bash ; aucune compilation Swift locale.

- Extension demandée par le porteur : 65 propositions d’icônes conservées (5 application, 5 × 12 thèmes/actions), sélection et polissage, Signaler simplifié. Documents dédiés et planches dans `assets/native-icons-20261004`.

- Suite : skill logo-design installé et appliqué ; logo d continu intégré dans `e36b0d4`. Les 24 captures AX de `10f1d12` sont inspectées. Correction de la note initiale sur Python : les 11 tests de capture passent localement avec Git Bash et PYTHONUTF8=1 ; ils ne sont pas câblés dans la CI générale.

- Livraison : à la demande du porteur, arrêt des campagnes restantes et retrait du brouillon PR5 ; IPA 0.7.0/build98 fournie immédiatement, sans attendre les tests.


- Suite retours terrain : tarif et profil accessibles directement, alertes natives centrales, bandeau après Signaler avec annulation durable y compris hors ligne et sans GPS, trois modes carte. Planification : prévalidation anonyme du créneau avant tarif ; serveur `52c355f` déployé après sauvegarde, migration022 et services vérifiés. 234 tests API/104 web passent dans run37217180774. Tests Swift ajoutés mais non exécutés conformément au choix d’IPA rapide. Décision courante : `live-feedback-planning-20261004.md` ; IPA0.7.0/build102 compilée sur9dcad86, run37217708082 ; téléchargée et empreintes vérifiées. Preuve `proofs/live-feedback-planning-20261004.json`.
