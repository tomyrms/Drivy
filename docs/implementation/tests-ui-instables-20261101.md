# Tests UI instables : notes par test (1er novembre 2026)

Branche `claude/tests-ui-stables-20261101`. Source : les journaux de 173 runs « Refonte · iOS » (13 au 31 octobre), les artefacts de deux runs rouges (41229249440, 40669055795) et l'historique git. « Version actuelle » = test tel qu'il est dans master depuis son dernier changement de fonction ; elle ne suit pas les changements d'aides (`launch`, `restore`), cités à part quand ils comptent.

## Corrigés dans cette branche

**`SchoolAgendaUITests/testRefreshFailureRetainsCoursesAndSelectionUntilRetry`** (8 échecs sur 18 exécutions). Quatre échecs le 26/10 : agenda en chantier, corrigé le jour même. Quatre échecs iPhone seul du 30 au 31/10 (iPad vert sur le même commit) : le geste de tirer-pour-actualiser ne partait pas (la barre de navigation avec champ de recherche couvre y 62 à 228), puis, sur `80efe4d1`, le compte final des séances donnait 1 au lieu de 2. Les deux correctifs du 31/10 (`80efe4d1`, `b24f2def`) sont dans master ; aucun run n'avait tourné sur `b24f2def`. Défaut restant du test : le compte final suppose que la seconde séance (14:00) est à l'écran, alors qu'elle dépasse à demi sous la barre d'onglets sur iPhone. Correctif (`702865be`) : amener 14:00 à l'écran (`reveal`, comme dans `testMixedDay…`) avant de compter. Aucune assertion retirée. Preuve : run 41254020521, réussi.

**`MessagingLatencyUITests/testFiveSecondResponseCannotReintroduceAQuicklyRemovedReaction`** (7 échecs sur 24). Cinq échecs « Retrait local immédiat », deux échecs d'ouverture du fil (aucun depuis le 28/10). Cause des cinq, établie en deux temps. Première hypothèse (abandonnée) : le retrait tombait sur la réponse retardée de 5 s ; un délai de 15 s a pourtant échoué de la même façon (run 41256319407, retrait 5,0 s après l'ajout, 10 s avant la réponse). Cause retenue : cinq secondes après l'ajout, la bulle passe à « en cours de synchronisation » (indicateur `messaging.mutation.slow`) et change de hauteur ; un appui de retrait qui tombe à cet instant est perdu et le cœur reste affiché (hiérarchie finale du run 41256319407 et vidéo, aussi vidéo du run 41229249440). Écart mesuré entre les deux appuis dans 22 exécutions : 4,3 à 13,2 s, médiane 5,6 s ; les échecs mesurés tombent tous à 5,0 à 5,8 s, soit ce seuil de 5 s plus la latence de XCTest. Correctif (`1dc697f5`, sur la base de `12c4bd2a`) : réponse à l'ajout retardée de 15 s (valeur déjà admise par la fixture), l'appui attend l'indicateur de lenteur puis une bulle au cadre stable, fenêtre d'observation ancrée sur l'ajout (2 × 15 s + 8 s), écart réel joint au test. Mêmes assertions ; le retrait part dans un état stable et avant la réponse. Preuve du code final : runs 41257979928 et 41257987154, réussis tous deux (test passé, 0 échec). Des essais antérieurs à 8 s (run 41254020521, réussi) et à 15 s sans attente (41254915339 réussi, 41256319407 rouge, 41257019945 rouge sur le même appui perdu) ont conduit à ce correctif.

## Déjà corrigés avant cette branche (aucun changement, aucun run)

| Test | Échecs | Cause et correctif existant | Depuis |
|---|---|---|---|
| `testLoadOlderMessages` | 18 sur 46 | 15 échecs les 25-26/10 sur l'ancien fil et un test réécrit cinq fois, souvent sur les deux appareils. 3 échecs iPhone seul (`a4acced6`, `a9e02058`, `6a46d787`) : le test appuyait sur « Charger les messages précédents » et attendait sa disparition. Sur `6a46d787` le bouton est à y 48 à 66, derrière la barre de navigation (y 78 à 132) : l'appui ne touche rien. Réécrit en `e8b5f3c3` pour remonter jusqu'à la page 2 par la pagination automatique. | 0 échec sur 19 exécutions de la version actuelle |
| `testAdminRemoveConfirmationFromContextMenuByLabel` | 7 sur 47 | 4 : fin de test refusée (apparence « non spécifiée », corrigé `c84d489d`). 3 : lancement de l'app expiré (« background assertion », « timed out while launching »), faute de simulateur, non corrigeable côté test. | 0 sur 14 depuis le 28/10 |
| `testAdminRemoveConfirmationFromSwipeAction` | 7 sur 47 | Mêmes 4 (apparence), 1 « ligne du général » d'une ancienne attente, 2 lancements expirés. | 0 sur 14 depuis le 28/10 |
| `testConversationOpensAtNewestMessageNearComposer` | 6 sur 49 | 4 apparence ; 1 « ligne du général » ; 1 iPad (15 s), délai iPad et attente de page corrigés en `696d01d7`. | 0 sur 26 exécutions |
| `testQuotedReplyShowsAndJumps` | 5 sur 47 | 4 apparence ; 1 « ligne du général ». Réécrit pour Exyte en `e8b5f3c3`. | 0 sur 18 |
| `testDarkModeCapture` | 5 sur 47 | 3 apparence ; 1 « ligne du général » ; 1 ancien fil. | 0 sur 41 depuis le 26/10 |
| `SchoolCourseJourneyUITests/testParticipantSearch…` | 5 sur 23 | 2 champ introuvable (ancienne interface), 2 « aucun élément n'a le focus clavier », 1 « plusieurs `PopoverDismissRegion` » : corrigés en `acfe52dd`. | 0 sur 8 + 8 |
| `testFifteenSecondResponseKeepsReactionAndComposerUsable` | 4 sur 23 | 3 chronométrage faussé par la lecture de l'écran (27,3 et 12,9 s), corrigé en `0e7ed903` ; 1 palette introuvable avant le menu natif (`a1a3529a`). | 2 + 2 réussites seulement sur le code actuel : à surveiller |
| `MessagingKeyBackupUITests/testRestoreErrorsAreDistinctWithLargeText` | 4 sur 17 | Glissements vers le bas qui fermaient la feuille Messages sur iPad ; supprimés en `a4acced6`, sélecteurs en `6c755aac`. | 0 sur 4 + 4 |
| `NativeNavigationTests/testProfileOpensObservationThemes…` | 4 sur 19 | 2 exécutions rouges le 25/10 avant `85d63a45`. | 0 sur 8 |

Le « ligne du général » est l'attente de `openInbox` avant sa réécriture ; « apparence » est `XCUIDevice.appearance = .unspecified`, refusé par le simulateur de CI.

## Vrais défauts de l'app (décrits, non corrigés)

1. Bouton « Charger les messages précédents » inaccessible au toucher sur iPhone (observé sur `6a46d787`, `MessagingOlderMessagesButton`, `mainHeaderBuilder`) : son cadre est y 48 à 66, derrière la barre de navigation, et la capture `05a-haut-du-fil` ne le montre pas. Non revérifié sur master : la pagination automatique charge la page 2 avant que le bouton ne serve. Il reste le recours accessible annoncé dans le code. Zone de l'ancrage du fil, donc non touchée.
2. Un appui sur la bande de réactions qui tombe pendant la bascule « en cours de synchronisation » (5 s après l'ajout) est perdu. Vu sur deux runs (vidéos et hiérarchies), non reproduit à la main : à qualifier côté app, le correctif de test attend simplement l'état stable.

## Reste à faire

- Les lancements lents ou expirés du simulateur (run 41256319407 : lancement de 37 s, appui sur « Messages » sans effet ; `Failed to launch … Timed out`) ne se corrigent pas dans le test : environnement du runner.
- Dans le run 41254915339, le retrait est parti 13,1 s après l'ajout (runner chargé) : au-delà du seuil de 10 s, l'état redevient stable, mais une marge sous 2 s avant la réponse à 15 s reste possible sur un runner très lent.
