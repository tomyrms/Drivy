# Qualification Apple 62875344 — réparation d'un diagnostic de compilation tests

Date : 5 novembre 2026. Base locale propre : `3dbbe101730aefbe7fc10ef24937b7efffd63ff8`.
Modèle : `opencode-go/deepseek-v4.1-flash`, sans override ni effort exposé.

## Diagnostic repris

Le coordinateur a relu le journal primaire du job Apple `127014762437` : `TEST BUILD FAILED`,
code 65, Xcode 26.6 / Swift 6.3.3. Linux est vert. Le diagnostic autorisé porte sur l'appel
`ErrorBox(error)` de
`apps/ios/DrivyTests/MessagingMediaCoordinatorTests.swift:110` : l'initialiseur membre de
`private struct ErrorBox { let error: Error }` (ligne 1672) exige l'étiquette `error:`.

## Correction

Une seule ligne modifiée :

```swift
case .failure(let error): box.finish(.error(ErrorBox(error: error)))
```

Aucun changement du helper, des échéances, des assertions, de la gestion des erreurs
produit, des autres tests ou d'un autre fichier.

## Vérifications réellement exécutées

- `git status --porcelain` avant édition : arbre propre, HEAD `3dbbe101`.
- `git diff --stat` : un seul fichier de code, une insertion, une suppression.
- `git diff --check` : aucune erreur.
- `Select-String` : l'appel corrigé est unique ; la déclaration `ErrorBox` et son membre
  `error` restent inchangés.
- Codebase Memory : projet `drivy-medias-parcours-97`, racine exacte du worktree,
  `status: ready` ; lecture directe de la déclaration et de l'appel, sans réindexation
  générale.
- Aucune compilation Swift ni exécution XCTest sous Windows : Apple absent.
  **Correctif préparé, Apple à réexécuter.**

## Limites

- Aucun GREEN n'est revendiqué ici. Le RED est le compilateur Apple cité, pas une
  simulation de syntaxe.
- Le job mentionne deux erreurs de compilation de tests ; la présente autorisation ne
  couvre que l'appel `ErrorBox(error:)`. Tout autre diagnostic distinct n'est pas modifié
  et doit être confirmé ou rouvert par le rerun Apple.
- Commit local final : son SHA exact est transmis avec le `worker_done`. Aucun push, CI,
  fusion ou déploiement.

## Q3 — second diagnostic du helper DeadlineBox

Les deux journaux `simulator-build.log` complets du SHA `3ad58197e88f24fb4b915db12172905749341123`
(runs `41960681911` / `41960681798`) ne portent qu'une erreur de compilation à
`MessagingMediaCoordinatorTests.swift:1701:23` : `sending 'value' risks causing data races`.
Les 21 anciens diagnostics ont disparu et aucun test n'a tourné.

Cause relue : `@MainActor private final class DeadlineBox<Value>` stocke `Value` puis le
remet au paramètre `sending` de `CheckedContinuation.resume(returning:)`. Les deux usages
(`80`, `106`) instancient `DeadlineBox<DeadlineOutcome<T>>`, où `T: Sendable` et
`DeadlineOutcome<Value: Sendable>: Sendable`.

Correction : seule la déclaration devient `DeadlineBox<Value: Sendable>`. `@MainActor`,
`CheckedContinuation`, `finish`/`wait`, gardes et assertions restent inchangés ; aucun
`@unchecked Sendable`, `nonisolated(unsafe)` ni désactivation de strict-concurrency.

Vérifications : les deux usages et leurs génériques ont été relus ; le diff est limité à
cette déclaration (plus ce rapport), `git diff --check` est vide et l'arbre est propre.
Aucune compilation Apple locale : le RED est le compilateur cité, pas un port Python.
**Correctif préparé, Apple à réexécuter.** Il ne garantit pas l'absence d'un autre
diagnostic après compilation.

## Q4 — attente de recomposition après réponse perdue

Le run `41962003316` au SHA `62560a2e` exécute réellement
`testSendKeepsTheIntentWhenTheServerAnswerIsLost` et n'échoue qu'à la ligne 320 : après
une réponse POST perdue, `recomposeAfterMembersChanged` rend `.pending(.resultUnknown)`
alors que le test attendait `.membersChanged`.

Le produit est cohérent avec le contrat : sans entrée dans `membersChanged`, la garde
`guard let refused = membersChanged[clientMessageID]` renvoie `.resultUnknown`. Une réponse
perdue n'établit pas un refus serveur `MEMBERS_CHANGED` et n'autorise aucune recomposition.
Le produit n'est pas modifié pour fabriquer un refus inexistant.

L'attente du seul cas concerné est ajustée à `.resultUnknown`. Le même test vérifie
désormais, après l'essai refusé : aucun nouveau chiffrement, aucun nouveau CAS
(`replaceCalls` inchangé), aucun nouveau POST (`sends` inchangé), et l'intention conserve
exactement le même `mediaID`, `createdAt` et `messageCiphertext`. Aucune autre assertion
n'est retirée ni élargie.

Limite : aucun Swift local, le RED est le run Apple cité ; aucun GREEN n'est revendiqué.
Le helper `DeadlineBox` n'est pas rouvert.
