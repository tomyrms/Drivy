# Reprise — passe UX « sobre, compacte, cohérente, fluide » (5 octobre 2026)

Document de passation. Il permet à une autre session (Codex, Claude) de reprendre ce chantier sans l'historique de la conversation. La section « État des lots » fait foi.

Phrase à donner à Codex : « Lis docs/implementation/reprise-ux-sobre-20261005.md et continue le chantier là où il s'est arrêté, en respectant AGENTS.md et les skills indiqués. »

## Demande du porteur (5 octobre 2026)

Nouvelle passe sur l'app native, avec les skills pertinents à chaque étape, plusieurs agents en parallèle et des modèles adaptés à la difficulté. Ses propositions sont des pistes : analyser le comportement réel avant de choisir.

1. **Fiche de leçon et planification** : trop d'« emojis » (le code n'en contient aucun : il s'agit des symboles SF décoratifs). Présentation sobre, icônes seulement quand elles servent. Affichage du tarif à réévaluer dans la fiche et dans la planification : est-il nécessaire à cet endroit, à ce moment ? S'il reste, le rendre discret ; ne pas le retirer s'il répond à un besoin.
2. **Carte de l'élève et dossier** : beaucoup plus sobre et compacte, l'essentiel visible, le secondaire accessible autrement. Dans Leçons et Progression, ne plus réafficher une grosse carte d'identité. Composant partagé avec variantes.
3. **Modifier les informations** : pourquoi date de naissance, adresse, téléphone et e-mail ne sont-ils pas modifiables ? Les rendre modifiables selon les droits ; vérifier l'enregistrement et la répercussion dans l'app.
4. **GPS actif** : « Signaler » devient gris un instant après un signalement (clignotement) ; pause puis reprise donnent l'impression d'un rechargement. Trouver la cause, corriger, chercher les mêmes défauts ailleurs.
5. **Bilan** : carte de l'élève, montant à payer mal présenté, bouton « Enregistrer » trop vague (quoi, avec quelles conséquences ?).
6. **Ensemble** : informations répétées, composants trop volumineux, intitulés ambigus, transitions instables.

## Constats établis par lecture du code

- **Formulaire de l'élève** : `SchoolProfileWorkspace.editableFields` ne retient que les champs cités par la politique de champs publiée de l'école. Celle de « Luc auto école » ne cite que prénom et nom : rien d'autre n'est modifiable, et un moniteur affecté (non administrateur) n'a aucun champ. Le serveur (`apps/api/src/profiles.ts`) accepte pourtant les six champs en accès FULL (administration, élève lui-même) et e-mail/téléphone en accès CONTACT (moniteur affecté).
- **Tarif** : la fiche de leçon affiche « Tarif » (prix convenu à la réservation) et « À payer » (somme des charges du compte) dans l'en-tête, pour tous. Aucun paiement n'est enregistré nulle part (`payments=[]`, `netReceivedCents=0`) : « À payer » vaut toujours la charge et ne peut pas diminuer.
- **Enregistrer le bilan** : `saveDraft` enregistre le brouillon ; le serveur en fait aussitôt la version lue par l'élève (`syncSharedReport`), sauf bilan gardé privé. La leçon est déjà terminée à ce moment.
- **Dossier** : la carte répète prénom et nom sous le nom complet, puis e-mail, téléphone, date de naissance, adresse, bouton, formations. Les pages Leçons et Progression réaffichent avatar 48 pt, nom en titre et permis.

## Décisions

- Composant partagé `UI/DrivyLearnerIdentity.swift` (écrit par l'intégrateur) : variantes `page` (dossier), `compact` (fiche de leçon, bilan), `inline` (rappel sur une page secondaire, une ligne sans avatar).
- Les champs modifiables suivent les droits du serveur, plus la politique ; celle-ci continue d'indiquer ce qui est requis et pourquoi. Écart à consigner si le dossier de conception l'interdit.
- Pas de commit par les agents ; l'intégrateur committe lot par lot.

## État des lots

Chemins relatifs à `apps/ios/Drivy/`. Chaque lot possède ses fichiers ; personne d'autre ne les modifie. Fichiers partagés réservés à l'intégration : `UI/DrivyComponents.swift`, `UI/DrivyTheme.swift`, `UI/DrivyLearnerIdentity.swift`, `UI/*VisualReview.swift`, `UI/DrivyDesignSystemGallery.swift`, `DrivyTests/SchoolPresentationTests.swift`.

| Lot | Sujet | Modèle | Fichiers possédés | État |
|---|---|---|---|---|
| A | Dossier de l'élève, pages Leçons et Progression | opus | `SchoolUI/SchoolLearnerDossierView.swift`, `SchoolUI/SchoolLearnerProfileSummary.swift`, `SchoolUI/SchoolLearnerActions.swift`, `SchoolTrainingUI/*`, tests `SchoolDossierTests`, `SchoolTrainingRefreshTests` | lancé |
| B | Fiche de leçon, bilan, saisie d'observations | opus | `SchoolLessonReportUI/*`, `SchoolObservationUI/*`, `UI/DrivyComponents+Agenda.swift`, tests `SchoolLessonFinishTests`, `SchoolLessonHubTests` | lancé |
| C | Tarif dans la planification, libellés de l'agenda | sonnet | `SchoolAgendaUI/*`, tests `SchoolPlanningDefaultsTests`, `SchoolStartNowClientTests` | lancé |
| D | GPS actif : Signaler, pause et reprise | opus | `SchoolCaptureUI/SchoolCaptureLive*.swift`, `SchoolLiveObservationSheet.swift`, `SchoolObservationUndoBanner.swift`, `SchoolObservationEmblem.swift`, `SchoolLiveHeadingSource.swift`, `SchoolMapCourse.swift`, `SchoolCaptureCore/SchoolCaptureSessionController.swift`, `UI/DrivyComponents+Seance.swift`, tests `FieldFlowTests`, `SchoolLiveObservationRecorderTests`, `SchoolCaptureLifecycleTests` | lancé |
| E | Modification des informations de l'élève | opus | `SchoolProfileUI/*`, `SchoolProfileAPI/*`, tests `SchoolProfile*Tests` ; au besoin `apps/api/src/profiles.ts` et son test | lancé |
| F | Seconde vague : mêmes défauts ailleurs, relecture de compilation | opus | à définir après intégration de A à E | à faire |

## Skills

`impeccable` (SKILL.md, `reference/ios.md`, `operate.md`, `distill.md`, `quieter.md`, `clarify.md`, `layout.md`, `polish.md`, et `craft-floor.md` avant toute édition), `swiftui-ui-patterns`, `write-swift`, `apple-hig`, `balise-ux-writing`, `superpowers:systematic-debugging` pour le lot D. Contexte Impeccable déjà chargé : pas de `PRODUCT.md`, `DESIGN.md` fait autorité, mode Operate, plateforme iOS, raffinement.

## Contraintes

Celles de `reprise-revue-ui-20261004.md` valent ici : aucune compilation Swift locale (iOS 26, Swift 6), IPA compilée par le workflow « IPA d'essai · iLoader » à chaque push sur `codex/**` touchant `apps/ios/Drivy/**`, jamais de force-push ni de signature GPG forcée, documents écrits par script, aucun déploiement implicite.

## Ce qu'il reste à faire

1. Recevoir les comptes rendus des lots A à E, relire chaque diff, committer lot par lot.
2. Lancer le lot F, intégrer.
3. Pousser la branche, attendre la compilation de l'IPA, corriger les erreurs éventuelles.
4. Écrire la décision (`docs/implementation/ux-sobre-20261005.md`), mettre à jour `STATUS.md`.

## Journal

- 5 octobre 2026 : constats par lecture, composant `DrivyLearnerIdentity` écrit, lots A à E lancés en parallèle. Rien n'est compilé.
