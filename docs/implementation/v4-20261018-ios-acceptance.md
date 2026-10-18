# V4 · campagne Apple et checklist appareil

Branche `design/ui-ux-v4-20261018`, publiée le 18 octobre 2026. Aucune fusion.

## Workflows lancés

| Run | Portée | Ce que la réussite prouve | Ce qu'elle ne prouve pas |
|---|---|---|---|
| 39165440743 `unit_only=true` | Compilation + DrivyTests iPhone | le code V4 compile, tests modèles verts | rendu réel, VoiceOver, iPad |
| 39165443005 `ui_test_suite` (8 suites) | XCUITest iPhone et iPad | parcours bilan, navigation, continuité de saisie | appareil physique, GPS, batterie |
| 39165445238 `refonte-checks` | API PostgreSQL, web, docs | serveur et web identiques à la recette locale | iOS |

Suites UI : `LayoutContinuityTests FieldFlowTests SchoolReportFlowUITests NativeNavigationTests SchoolEntryTests SchoolRootEntryTests DossierRefreshTests AppearanceSettingsTests`.

## Tests Swift ajoutés par V4

Unitaires :
- `DrivyMotionTests` : `testProgressIsImmediateWhenReduceMotionIsEnabled`, `testProgressUsesCallerDurationWhenMotionIsEnabled`, `testExistingFeedbackContractRemainsAvailable`.
- `SchoolLearnersTripsV4Tests` : `tripFilterStateResetsToAllWhenScopeChanges`, `pickerDistinguishesBaseEmptyFilteredEmptyAndResultPresent`.
- `SchoolAgendaMonthTests` : `emptyAgendaAlwaysOffersTheNextDayWithoutDuplicatingPlan`, `freshnessAppearsOnlyForRetainedContentAfterAnErrorInTheSameScope`, `confirmedLessonIsConsumedOnlyWhenThePlanningSheetReturns`.
- `SchoolPlanningBookingTests` : `confirmedCreateExposesTheServerLessonOnlyAfterItsReceiptAndRead`, `confirmedMoveExposesTheRereadServerVersionAndNeverAutoStarts`, `unknownOrRejectedBookingNeverExposesALesson`, `invalidatingWhileTheConfirmedLessonIsReadDropsTheOldScopeResult`, `invalidatingVerificationDuringConfirmedReadPublishesNeitherSuccessNorNotification`, `rereadAcceptsANewerCurrentVersionButRejectsAnOlderOne`, `forbiddenConfirmedLessonReadRevokesTheWorkspaceInsteadOfOfferingGenericRetry`.
- `SchoolReportFlowTests` : 8 tests d'ordre, récapitulatif sans trajet, visibilité en attente, colonne large sans doublon.

UI : `SchoolReportFlowUITests.testCompactReportEditsTextBeforeCompetenciesAndSavesOnlyFromReview`, `LayoutContinuityTests` adapté au récapitulatif.

## Voie visuelle, après succès des tests

```text
gh workflow run refonte-ios.yml --ref design/ui-ux-v4-20261018 -f visual_only=true -f visual_screens="agenda learners learner" -f visual_large_text=true
```

## Checklist manuelle sur appareil

1. **Bilan** : terminer une leçon, saisir le texte, passer les compétences, vérifier que seul le récapitulatif propose « Enregistrer ». Quitter en cours de route puis revenir : texte conservé.
2. **Bilan iPad paysage** : trajet et observations visibles une seule fois, toujours modifiables.
3. **Agenda** : planifier une leçon, la fiche s'ouvre après confirmation, la leçon n'est pas démarrée. Couper le réseau puis rafraîchir : la date de dernière lecture apparaît sous l'erreur.
4. **Trajets** : filtre par moniteur sur un élève avec plusieurs pages, « Charger d'autres trajets » quand aucun résultat chargé ne correspond.
5. **Réduire les animations** activé : écran de lancement de trajet sans zoom ni barre animée.
6. **VoiceOver** sur les étapes du bilan et sur le filtre trajets (valeur annoncée).
7. **Dynamic Type** accessibility3 et accessibility5 : bilan et agenda vide sans texte tronqué.

Hors portée : GPS terrain, batterie, précision de positionnement.
