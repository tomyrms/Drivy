# Captures iOS : diagnostic de l’échec 65 — 30 septembre 2026

## Périmètre et diagnostic

Le journal fourni se termine sur l’échec de `VisualOrientationTests.testRequestedScreensAtRealOrientations`, puis le code 65. Ce résumé ne suffit pas à lui seul à connaître l’assertion en cause.

Le journal complet consulté dans la conversation situe l’échec pendant l’attente de « Mon dossier », après cinq captures. Cela identifie l’étape échouée, pas la cause ultime : écran non ouvert, chargement non terminé ou élément d’accessibilité non trouvé restent à distinguer.

**L’archive jointe contient une autre version du test.** Vérification effectuée sur les fichiers à la racine `Drivy2/Drivy/`, pas dans les anciens worktrees `.claude/`. Dans cette version, `student-file`, `today`, `training` et `training-list` ne sont pas des noms de capture reconnus. Les destinations courantes incluent `dossier`, `learner`, `profile`, `account`, `home-tabs`, `progression` et `planning-details`. Ces destinations ne sont pas déclarées équivalentes aux anciens écrans. Il ne faut pas remplacer automatiquement un ancien nom par un autre.

Ce correctif porte sur la campagne présente dans l’archive. Il n’est pas une preuve de résolution de l’ancien écran « Mon dossier ». Aucun changement produit, navigation métier, compte, API, signature ou rendu n’est effectué.

## Modifications

1. Le test refuse les noms d’écran inconnus avant le lancement de l’application. Un contrôle de régression compare sa liste à celle du script pour éviter leur divergence.
2. Toutes les assertions visuelles explicites de la campagne passent par une aide qui joint une capture d’échec et la hiérarchie d’accessibilité avant d’appeler `XCTFail`. Le nom comprend appareil, écran, apparence et orientation. Les images d’échec sont préfixées `FAILED-`, donc exclues des captures réussies. Les exceptions internes à XCTest et les arrêts forcés du runner restent gérés par XCTest.
3. L’écran `account` est attendu avec son identifiant existant `account-heading`, plutôt qu’avec seulement un délai fixe. Les contrôles existants des autres écrans et de la rotation sont conservés.
4. Le script exporte les pièces jointes même si `xcodebuild` échoue. Il conserve le code de sortie du test si l’export échoue aussi et ne valide aucune matrice incomplète. Les diagnostics sont sous `artifacts/ios/test-reports/Visual-<appareil>-<apparence>/capture-attachments/`, répertoire déjà couvert par l’upload `if: always()` du workflow. Ce sous-dossier ne chevauche pas l’export `attachments/` effectué par le workflow.

Les diagnostics ajoutés sont limités à la campagne opt-in de fixtures fictives. Aucun dump des variables d’environnement ou des jetons n’est ajouté.

## Vérifications exécutées

- PASS — `bash -n scripts/ios/capture-screens.sh`.
- PASS — analyse syntaxique avec `swiftc -frontend -parse apps/ios/DrivyUITests/VisualOrientationTests.swift` (Swift 6.2.1 Linux). Ce n’est pas une compilation ni un contrôle des API du SDK Apple.
- PASS — les 11 contrôles de `scripts/ios/test_visual_capture.py`, exécutés par lots/individuellement. `xcrun` et `xcodebuild` sont des doubles de test : aucun simulateur n’est lancé.
- PASS — contrôle puis application du patch sur les fichiers originaux extraits de l’archive, et comparaison des fichiers résultants.
- NON EXÉCUTÉ — compilation iOS, exécution XCUITest, validation iPhone/iPad, inspection des nouvelles captures Apple.

### Scénarios du script

Succès et conservation des octets PNG ; export après code 65 ; erreur d’export sans masquage du code 65 ; résultat absent sans masquage du code 65 ; erreur d’export après succès du test ; captures manquantes ; capture d’échec non comptée comme succès ; mauvaise orientation ; ancien nom inconnu refusé avant toute commande simulateur ; correspondance des listes d’écrans ; diagnostics avant l’assertion et contrôles d’orientation préservés.

## Reprise sur GitHub Actions

Appliquer le patch à la version de l’archive, puis lancer une **nouvelle exécution** de « Refonte · iOS » sur la branche qui contient ces fichiers. Commencer par cette matrice ciblée du code actuel :

```text
visual_only: true
visual_screens: dossier account planning-details
visual_devices: iPhone
visual_appearances: dark
visual_orientations: portrait landscape
```

Ce lot contrôle les destinations actuelles, sans prétendre reproduire l’ancien parcours « Mon dossier ». Ensuite seulement, élargir aux écrans souhaités, à iPad et au thème clair. Les captures originales et les rapports permettront de vérifier la présentation et les éléments réellement affichés.

Ne pas relancer simplement un ancien job en pensant qu’il intégrera ces fichiers : vérifier le commit de l’exécution choisie. Aucun push, lancement GitHub Actions, déploiement ni IPA n’a été effectué par ce correctif.
