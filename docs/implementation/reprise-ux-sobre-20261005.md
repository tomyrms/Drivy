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
| A | Dossier de l'élève, pages Leçons et Progression | opus | `SchoolUI/SchoolLearnerDossierView.swift`, `SchoolUI/SchoolLearnerProfileSummary.swift`, `SchoolUI/SchoolLearnerActions.swift`, `SchoolTrainingUI/*`, test `SchoolDossierTests` | **committé `392c360`** |
| B | Fiche de leçon, bilan, saisie d'observations | opus | `SchoolLessonReportUI/*`, `SchoolObservationUI/*`, `UI/DrivyComponents+Agenda.swift`, test `SchoolLessonHubTests` | **committé `7209608`** |
| C | Tarif dans la planification, libellés de l'agenda | sonnet | `SchoolAgendaUI/*`, tests `SchoolPlanningBookingTests` | **committé `7fc911a`**, non compilé |
| D | GPS actif : Signaler, pause et reprise | opus | `SchoolCaptureCore/SchoolCaptureSessionController.swift`, `SchoolCaptureUI/SchoolCaptureLiveView.swift`, `SchoolCaptureLiveObservations.swift`, `SchoolLiveObservationSheet.swift`, tests de cycle de vie et d'enregistreur | **committé `fa72b75`** |
| E | Modification des informations de l'élève | opus | `SchoolProfileUI/*`, `SchoolProfileAPI/*`, tests `SchoolProfile*Tests` ; `apps/api/src/profiles.ts` et `apps/api/test/g1d.integration.test.ts` | **committé `876bef9` (app) et `4daae5f` (API, non déployée)** |
| F1 | Seconde vague : relectures et états occupés sans clignotement (fiche de leçon, observations, profil), nom du moniteur pour l'élève, libellé du permis vu | opus | `SchoolLessonReportUI/*`, `SchoolObservationUI/*`, `SchoolProfileUI/SchoolProfileWorkspace.swift`, `SchoolProfileView.swift`, `UI/DrivyComponents+Agenda.swift` | **committé** |
| F2 | Seconde vague : huit corrections ciblées (onglet après reprise, planification, démarrage, préparation du trajet, symboles restants, liste Élèves, test UI du prix) | sonnet | `SchoolUI/SchoolHomeView.swift`, `SchoolTodayView.swift`, `SchoolWorkspace.swift`, `SchoolLearnerDossierView.swift`, `SchoolAgendaUI/SchoolPlanning*.swift`, `SchoolStartNowView.swift`, `SchoolCaptureUI/SchoolCapturePreparation*.swift`, `DrivyUITests/VisualOrientationTests.swift`, `DrivyTests/SchoolWorkspaceTests.swift` | **committé** |

## Skills

`impeccable` (SKILL.md, `reference/ios.md`, `operate.md`, `distill.md`, `quieter.md`, `clarify.md`, `layout.md`, `polish.md`, et `craft-floor.md` avant toute édition), `swiftui-ui-patterns`, `write-swift`, `apple-hig`, `balise-ux-writing`, `superpowers:systematic-debugging` pour le lot D. Contexte Impeccable déjà chargé : pas de `PRODUCT.md`, `DESIGN.md` fait autorité, mode Operate, plateforme iOS, raffinement.

## Contraintes

Celles de `reprise-revue-ui-20261004.md` valent ici : aucune compilation Swift locale (iOS 26, Swift 6), IPA compilée par le workflow « IPA d'essai · iLoader » à chaque push sur `codex/**` touchant `apps/ios/Drivy/**`, jamais de force-push ni de signature GPG forcée, documents écrits par script, aucun déploiement implicite.

## Ce qu'il reste à faire

Tous les lots sont intégrés et poussés. Il reste :

1. Confirmer la campagne native après correction des deux fixtures de test : `gh workflow run "Refonte · iOS" --ref codex/revue-integration-20260929`.
2. Décision du porteur sur l'API (`4daae5f`, nom affiché recomposé, écart avec R77) : déployer après sauvegarde, ou revenir à un champ « Nom affiché » distinct.
3. Essai sur appareil par le porteur : transitions, GPS réel, VoiceOver, grandes tailles de texte.
4. Points laissés en l'état, listés dans `ux-sobre-20261005.md`.

## Journal

- 5 octobre 2026 : constats par lecture, composant `DrivyLearnerIdentity` écrit, lots A à E lancés en parallèle. Rien n'est compilé.
- 5 octobre, nuit : lot C terminé, relu et committé (`7fc911a`). Les lots A, B, D et E ont été coupés par la limite d'usage. Au moment de la coupure : A avait modifié le dossier et la page de formation, B la fiche de leçon et ses règles, E `profiles.ts`, son test et `SchoolProfileWorkspace.swift`, D aucun fichier. Chaque fichier modifié est à relire en entier avant de continuer.
- 5 octobre, 12 h 20 : les quatre agents sont repris avec leur contexte.
- 5 octobre, 12 h 36 : lots A, B, D, E relus et committés ; branche poussée (`fa72b75`), compilation de l'IPA et vérifications lancées. Seconde vague F1 (opus) et F2 (sonnet) lancée sur les défauts similaires relevés par D, B et A.
- 5 octobre, après-midi : F2 committé (`30f4ff4`). F1, coupé une fois par la limite d'usage, repris et committé (`4cb4cee`). Cible de tests réparée (`37dc641`, `57ffbcf`). IPA compilée sur `4cb4cee`. Captures de 15 écrans regardées. Campagne native : 322 tests sur 324 et 12 parcours d'interface réussis ; deux fixtures de test corrigées. Préparation du trajet : en-tête compact à la place du nom en grand titre. Décision et STATUS écrits.
