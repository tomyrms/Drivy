# Reprise — revue UI/UX native du 4 octobre 2026

Document de passation. Il permet à une autre session (Codex, Claude) de reprendre ce chantier sans l'historique de la conversation. **Il est tenu à jour à chaque étape : la section « État des lots » fait foi.**

Dernière mise à jour : 4 octobre 2026, lots lancés, aucun terminé.

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
| 1 | Composant de squelettes ; compte, onglet Profil, liste des trajets | `UI/DrivySkeleton.swift`, `UI/DrivyDesignSystemGallery.swift`, `UI/DrivyComponents+Accueil.swift`, `SchoolUI/SchoolRootView.swift`, `SchoolUI/SchoolAccountComponents.swift`, `SchoolTripsUI/*`, tests `SchoolTripsTests`, `SchoolPresentationIdleTests` | en cours |
| 2 | Page « Aujourd'hui », « Démarrer une leçon » | `SchoolUI/SchoolTodayView.swift`, `SchoolAgendaUI/SchoolStartNowView.swift`, tests `SchoolStartNowClientTests` | en cours |
| 3 | Leçon en cours : actions, navigation, mentions légales ; onglets | `SchoolCaptureUI/SchoolCaptureLiveView.swift`, `SchoolLiveObservationSheet.swift`, `SchoolCaptureLiveObservations.swift`, `SchoolObservationEmblem.swift`, `UI/DrivyComponents+Seance.swift`, `SchoolUI/SchoolHomeView.swift`, tests `FieldFlowTests`, `SchoolLiveObservationRecorderTests` | en cours |
| 4 | Fiabilité du tracé GPS ; écran de replay | `SchoolCaptureUI/SchoolCaptureLiveMap.swift`, `SchoolMapCourse.swift`, `SchoolCaptureReplayView.swift`, `SchoolCaptureReplayWorkspace.swift`, `SchoolCaptureCore/*`, `SchoolCaptureAPI/*`, tests `SchoolMapCourseTests`, `SchoolCaptureLifecycleTests`, `SchoolCaptureInteropTests`, `SchoolReplayFormattingTests`, `DrivyTimelineMarkGroupTests` | en cours |
| 5 | Agenda et planification | `SchoolAgendaUI/SchoolAgendaView.swift`, `SchoolPlanningView.swift`, `SchoolPlanningWorkspace.swift`, `SchoolPlanningSettingsView.swift`, `UI/DrivyComponents+Agenda.swift`, tests `SchoolPlanningDefaultsTests` | en cours |
| 6 | Élèves, dossier, formation, progression (moniteur et élève) | `SchoolUI/SchoolBrowserView.swift`, `SchoolUI/SchoolWorkspace.swift`, `SchoolTrainingUI/*`, tests `SchoolDossierTests`, `SchoolTrainingRefreshTests`, `SchoolWorkspaceTests` | en cours |
| 7 | Fiche de leçon, bilan, observations, préparation du trajet | `SchoolLessonReportUI/*`, `SchoolObservationUI/*`, `SchoolCaptureUI/SchoolCapturePreparation*.swift`, `SchoolRecordingChoice*.swift`, tests `SchoolLessonFinishTests`, `SchoolLessonHubTests` | en cours |
| 8 | Invitations, entrée dans une école, profil, accueil guidé | `SchoolInvitationsUI/*`, `SchoolJoinUI/*`, `SchoolProfileUI/*`, `UI/DrivyComponents+Ecole.swift`, tests `SchoolInvitation*Tests`, `SchoolProfile*Tests` | en cours |

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

## Ce qu'il reste à faire

1. Attendre ou terminer chaque lot ; relire son diff ; passer son état à « terminé » dans le tableau ; committer ses fichiers seuls (`git add <chemins>`, jamais `-A`).
2. Intégration : vérifier par recherche tous les appels des signatures modifiées (`SchoolCaptureLiveView`, `DrivyLiveTopBar`, `DrivyMapHeaderAction`, `DrivyLessonRow`, `SchoolCaptureLiveMap`), les identifiants d'accessibilité utilisés par `DrivyUITests`, les bancs visuels et `SchoolPresentationTests`. Vérifier que `DrivySkeleton.swift` respecte le contrat et que chaque lot l'emploie correctement.
3. Relecture croisée de l'ensemble (cohérence du vocabulaire et des états de chargement entre écrans).
4. Pousser la branche ; attendre la compilation de l'IPA ; corriger jusqu'à réussite.
5. Lancer « Refonte · iOS » ; corriger les échecs ; relire les captures (Aujourd'hui, leçon en cours avec la mention Apple Plans, squelettes), en clair, sombre, grand texte, iPhone et iPad.
6. Écrire `docs/implementation/native-ui-review-20261004.md` (constats, décisions, changements, skills appliqués, limites) et mettre à jour `docs/implementation/STATUS.md` avec ce qui est exécuté et ce qui reste à qualifier.
7. Ouvrir la PR vers `master` (le porteur l'attend en fin de tâche ; annoncer l'intention avant de pousser).
8. Reste hors de portée du simulateur, à dire tel quel : tracé GPS sur route (intersections, giratoire, tunnel, arrêt prolongé, départ, pause et reprise), batterie, VoiceOver sur appareil, position réelle de la mention Apple Plans sur iPhone.

## Journal

- 4 octobre 2026 : diagnostic par lecture, extraction de `SchoolCaptureLiveMap.swift`, huit lots lancés en parallèle. Rien n'est compilé ni testé.
