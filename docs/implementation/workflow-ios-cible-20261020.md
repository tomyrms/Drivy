# Campagne iOS ciblée par parcours

20 octobre 2026. Demande du porteur : ne plus exécuter des tests hors sujet à chaque correction d'une fonctionnalité.

## Décision

Le mode `unit_only=true` du workflow `refonte-ios.yml` propose deux périmètres :

- `unit_test_scope=gps`, par défaut : capture GPS, recalage en direct, prédiction, traces et replay.
- `unit_test_scope=all` : toute la suite native, disponible explicitement pour les régressions transversales.

Aucun test métier n'est supprimé. Les campagnes UI, visuelles et complètes existantes gardent leur fonctionnement. La campagne ciblée ne lance ni parcours UI, ni iPad, ni capture d'écran, ni construction d'IPA. L'IPA d'essai reste construite par son workflow distinct lorsque le code de l'app change.

Une seule sélection est partagée par la compilation pour tests et l'exécution, pour ne pas construire une sélection puis en exécuter une autre. Les entrées sont validées avant la compilation. Les noms affichés dans GitHub doivent distinguer GPS, suite native complète et parcours UI.

## Périmètre GPS

Huit fichiers de tests couvrent le parcours :

- `SchoolLiveMatchTests.swift`, avec ses trois suites de fenêtre, transport et cycle de vie.
- `SchoolCaptureLifecycleTests.swift`.
- `SchoolCaptureInteropTests.swift`.
- `SchoolTrackDisplayTests.swift`.
- `SchoolMapCourseTests.swift`.
- `SchoolMapRouteGapTests.swift`.
- `SchoolLiveHeadingTests.swift`.
- `SchoolReplayFormattingTests.swift`.

Les contrôles de droits, de refus de consentement, de persistance chiffrée, d'annulation, de réponse tardive et d'ancres réelles ne sont pas retirés au nom de la vitesse. Les invitations, profils, formations et autres domaines restent dans la campagne complète, pas dans le périmètre GPS.

## Commandes

```cmd
gh workflow run refonte-ios.yml --ref claude/recalage-suisse-osrm-20261020 -f unit_only=true -f unit_test_scope=gps
gh workflow run refonte-ios.yml --ref claude/recalage-suisse-osrm-20261020 -f unit_only=true -f unit_test_scope=all
```

## Mesure et limites

La sélection `only-testing` réduit les tests exécutés mais ne garantit pas que Xcode omette toutes les cibles UI lors du `build-for-testing` du scheme partagé. Aucun scheme dédié n'a été ajouté. La campagne `39499618964` a exécuté les 705 tests Swift Testing en 17,833 secondes, après compilation et démarrage du simulateur. Le temps d'attente de plusieurs minutes n'est donc pas proportionnel au nombre de tests. Cibler réduit le bruit et le risque d'échec hors sujet, mais ne supprime pas le coût de compilation de l'app ou du démarrage iOS. Aucun facteur d'accélération n'est promis sans mesure.

## Qualification

| Exigence | Vérification | Résultat |
|---|---|---|
| Sélection GPS sans perte de transport ou droits | Dix noms de suites dans huit fichiers, validation des noms | 14 tests locaux réussis sur le commit `4770294`, noms des dix suites comparés aux sources Swift |
| Même sélection à la compilation et à l'exécution | Helper unique, tests des arguments | Arguments identiques contrôlés par doubles locaux pour `gps` et `all` |
| Pas de parcours UI/iPad/IPA dans le mode GPS | Conditions du workflow et script, exécution Apple | À vérifier |
| Suite complète encore accessible | Cas `all` dans les tests locaux | Sélecteur `-only-testing:DrivyTests` conservé et testé |
| Parcours GPS réellement exécuté | Workflow Apple ciblé, nombre de tests et conclusion observés | Campagne `39503905801` en cours |
