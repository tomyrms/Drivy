# Classement intelligent des signalements — iOS (13 octobre 2026)

**Rien de ce qui suit n’a été compilé ni exécuté.** Le code a été écrit sur une machine Windows sans toolchain
Swift : ni compilation, ni test, ni rendu. Tout ce qui est décrit ici est une intention relue à la main, à
qualifier sur un runner Apple puis à l’œil.

## Principe

- L’ordre **manuel** reste celui de l’école (`observation-themes`, inchangé). Le classement intelligent est une
  préférence **par adhésion**, calculée **par le serveur** : l’app ne calcule aucun score, elle lit un ordre de
  clés (`GET /v1/schools/{schoolId}/observation-ranking`) et l’applique à l’affichage.
- Le classement n’écrit jamais dans l’ordre manuel : le désactiver rend l’ordre de l’école tel quel.
- L’ordre porte sur tous les thèmes affichés. La fenêtre de neuf tuiles n’est qu’un affichage : aucune logique
  « neuf premiers » n’existe dans le code ajouté.

## Fichiers créés

- `apps/ios/Drivy/SchoolObservationAPI/SchoolObservationRanking.swift` — `SchoolObservationRankingMode`,
  `SchoolObservationRanking` (projection + `isValid(for:)`), `SchoolObservationRankingBody`,
  `SchoolObservationRankingOrder.arranged(_:order:)` (règle pure), `SchoolObservationRankingClient`.
- `apps/ios/Drivy/SchoolObservationAPI/SchoolObservationRankingStore.swift` — cache (`SchoolObservationRankingCache`,
  fichier `SchoolObservationRanking/<école>-<adhésion>.json`), `SchoolObservationRankingStore`, registre
  `SchoolObservationRankingStores`, `SchoolAgendaClient.observationRankingStore(person:membership:)`, et le
  stockage de l’ordre figé d’une leçon (`SchoolLessonSignalOrderStore`, implémentations fichier et mémoire,
  fabrique `SchoolLessonSignalOrderStores.make`).
- `apps/ios/DrivyTests/SchoolObservationRankingTests.swift` — règle d’ordre, projection, store, stockage, gel.

## Fichiers modifiés

- `SchoolCaptureUI/SchoolCaptureLiveObservations.swift` — l’enregistreur reçoit `rankingStore` et `signalOrders`
  (paramètres avec valeur par défaut, placés après `themeStore`) ; `signalOrder`, `themes`, `openPalette()`.
- `SchoolCaptureCore/SchoolCaptureSessionController.swift`, `SchoolObservationUI/SchoolObservationWorkspace.swift` —
  les deux créations de l’enregistreur passent le store de classement et le stockage des ordres figés.
- `SchoolObservationAPI/SchoolObservationClient.swift`, `SchoolAgendaAPI/SchoolAgendaClient.swift` — accès au
  nouveau client (`rankingClient`, `observationRankingClient`).
- `SchoolUI/SchoolHomeView.swift` — le classement est relu à l’ouverture de l’espace, après les thèmes.
- `SchoolUI/SchoolStaffSettingsView.swift` — l’entrée « Signalements » existe pour tout moniteur ou administrateur.
- `SchoolObservationUI/SchoolObservationThemeSettingsView.swift` — interrupteur, ordre automatique, lecture seule.
- `UI/SchoolVisualReview.swift` — réponse fictive au `GET observation-ranking` (mode manuel, version 1), cache et
  stockage en mémoire pour les rendus de contrôle. `SchoolFieldVisualReview.swift` et la galerie n’ont pas eu
  besoin de changer : les nouveaux paramètres ont une valeur par défaut.

## Décisions

1. **Client dupliqué, pas factorisé.** `SchoolObservationRankingClient` reprend la forme de
   `SchoolObservationThemeClient` (contrôle du compte avant écriture, `If-Match`, `Idempotency-Key`, enveloppe)
   sans toucher au client existant, faute de pouvoir compiler. Il réutilise `SchoolObservationThemeFailure` et
   `SchoolObservationThemeClient.failure(_:code:)` ; les phrases montrées sont celles du store de classement.
2. **Validation stricte de la projection.** En mode `SMART`, `order` doit porter 1 à 64 clés ; un `SMART` à ordre
   vide est refusé (réponse invalide), comme le contrat l’énonce. `rankedOn` doit avoir la forme `AAAA-MM-JJ`.
3. **404 = fonction absente, et oubli de la copie.** Un 404 rend `isAvailable` faux, sans message, et efface la
   copie locale : sinon un ordre automatique resterait appliqué sans qu’aucun écran ne permette de le désactiver.
4. **`isAvailable` ne vient que de l’école**, pas de la copie locale : hors ligne, l’interrupteur n’apparaît pas,
   mais la liste et « Signaler » gardent l’ordre automatique de la copie.
5. **Gel par leçon.** À la première ouverture de « Signaler » en mode automatique, l’ordre confirmé est écrit dans
   `Application Support/SchoolLessonSignalOrders.json` (un seul fichier ; chaque entrée porte API, école, adhésion
   et leçon ; au plus 20 entrées, 3 jours). Tout enregistreur créé ensuite pour la même leçon le relit, dès son
   initialisation. En mode manuel rien n’est figé ; un ordre figé plus tôt est ignoré sans être effacé, et
   resservirait si le moniteur réactivait l’option pendant la même leçon.
6. **Sans stockage fourni**, l’enregistreur garde l’ordre en mémoire : il tient au moins pour cette instance.
7. **La relecture lancée par `openPalette()`** ne sert qu’à une leçon suivante. Conséquence assumée : si l’app
   est restée ouverte plusieurs jours sans repasser par l’accueil, la première leçon du jour fige l’ordre de la
   dernière lecture.
8. **Écran de réglage, moniteur sans droit de gestion** : rangées simples des seuls thèmes affichés. Ce cas
   couvre aussi un gestionnaire dont le droit n’a pas encore été confirmé par l’école dans la session (hors
   ligne) : il voyait auparavant des interrupteurs grisés.
9. **En ordre automatique**, « Réinitialiser l’ordre » est masqué ; « Rétablir la configuration d’origine » reste,
   puisqu’il porte aussi sur l’affichage. Les interrupteurs d’affichage passent par `store.setVisible`, qui part
   de `store.displayed` : le `PUT observation-themes` envoie l’ordre de l’école.
10. **Pendant l’envoi de l’activation**, la liste n’a pas encore d’ordre automatique : elle perd ses poignées
    aussitôt et ne se réordonne qu’à la confirmation.
11. **En-tête de la liste** : « Ordre automatique » à côté du compteur quand la ligne tient, dessous sinon
    (`ViewThatFits`), pour laisser sa place à « Enregistrement… ».
12. **Annonce VoiceOver** : « Classement intelligent activé / désactivé » à la confirmation d’un changement
    demandé depuis cet appareil (`confirmedChanges`), pas à une simple relecture.

## Ni compilé ni vu

Tout. En particulier :

- la compilation Swift 6 (concurrence stricte) des deux nouveaux fichiers et des tests ;
- le rendu de l’écran « Signalements » dans ses quatre états (manuel/automatique × gestion/lecture seule) ;
- l’animation des rangées au changement de mode ;
- VoiceOver sur l’interrupteur, sur les rangées en lecture seule et l’absence de « Monter »/« Descendre » ;
- le gel réel sur appareil (arrière-plan, app tuée, reprise de leçon).

## À regarder à la première compilation

- `SchoolObservationThemeSettingsView` : `.accessibilityActions { if reorders { Button… } }` (première utilisation
  de cette forme dans le dépôt), `.onMove(perform:)` avec une fermeture optionnelle, `ViewThatFits` dans l’en-tête
  de section, `.environment(\.editMode, .constant(reorders ? .active : .inactive))`.
- `SchoolLiveObservationRecorder.init` : `signalOrder` est affecté après les autres propriétés, comme `pending`.
- `SchoolObservationRankingStore` : type privé `Attempt` dans une classe `@Observable`.
- Tests : acteur `RankingSchool` (propriétés statiques lues depuis le MainActor), fermeture `now:` du stockage,
  tuple renvoyé par `smartSchool()`.

## À regarder à l’œil

- Hauteur et alignement de la rangée « Classement intelligent » avec sa description, en clair et en sombre,
  et aux grandes tailles de texte.
- Les rangées ne doivent être ni grisées ni estompées en ordre automatique.
- L’en-tête « 12 affichés sur 18 » suivi de « Ordre automatique » pendant « Enregistrement… » sur un iPhone étroit.
- Passage du mode d’édition actif à inactif : disparition des poignées et glissement des rangées.
- La liste en lecture seule d’un moniteur sans droit de gestion.

## Hors périmètre de ce lot

- `docs/implementation/STATUS.md` n’a pas été mis à jour (consigne : ne rien toucher hors de `apps/ios/` et de
  ce document).
- Rien n’a été commité, poussé ni déployé. L’API doit connaître `observation-ranking` avant que l’interrupteur
  n’apparaisse ; une API plus ancienne répond 404 et l’app se comporte comme avant.

## Mise à jour : compilation et tests (13 octobre)

L’IPA compile et la cible de tests aussi. Sur la CI (`Refonte · iOS`, `unit_only`), les cinq suites de ce lot passent : `SchoolObservationRankingOrderTests`, `SchoolObservationRankingProjectionTests`, `SchoolObservationRankingStoreTests`, `SchoolLessonSignalOrderStoreTests`, `SchoolLiveObservationRankingFreezeTests`. Les points « à regarder à la première compilation » sont donc levés ; ceux « à regarder à l’œil » restent entiers : aucun écran n’a été vu.

Limite connue : la leçon fige l’ordre que l’app a en mémoire à la première ouverture de « Signaler ». Si l’app n’est pas repassée par l’accueil depuis le dernier reclassement, c’est l’ordre de la veille.