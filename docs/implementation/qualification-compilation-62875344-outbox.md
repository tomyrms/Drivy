# Qualification de compilation 62875344 — tests outbox (#97)

Date : 5 novembre 2026. Base locale : `541768e9a368a68c546053a77c28aa3b57616f91` (`tomyrms/issues-medias-outbox-97`).
Candidat Apple : `62875344` (Xcode 26.6 / Swift 6.3.3), run UI `41957174662`, job `127014762557`, exit 65.
Journal : `integration-issues-20261105/artifacts/qualification-62875344/artifacts-41957174662/Drivy-native-results-62875344d92406efdd353bf0343c278f18faacc9/ios/simulator-build.log`. Aucun test n'a été exécuté.

## Diagnostics

19 diagnostics dans `apps/ios/DrivyTests/MessagingMediaOutboxTests.swift` (lignes du journal) :

1. 14 erreurs `extraneous argument label 'scope:' in call` aux lignes 135, 155, 193, 253, 555, 582, 650, 679, 823, 843, 873, 896, 952 et 964. La déclaration privée ligne 1093 utilisait `_ scope`, alors que les 14 usages passent `scope:`.
2. 2 erreurs d'optionalité aux lignes 416 et 426 : `MessagingCiphertext?` fourni là où `MessagingCiphertext` est requis.
3. 3 erreurs d'inférence aux lignes 661, 845 et 877, probablement dérivées des expressions mal typées ci-dessus ; elles ne sont pas déclarées corrigées avant réexécution Apple.

## Correction

- La déclaration privée est alignée sur les 14 usages : `folderContents(scope: MessagingScope, root: URL)`.
- Dans `testEnvelopeNoOpResynchronizesBeforeSuccess`, `pending.messageCiphertext` est lié une fois par `try XCTUnwrap(...)` et cette valeur sert aux deux `replacement:`, `expected:` restant l'optional d'origine. L'identité de l'enveloppe, les injections de panne et la comparaison des octets de l'archive sont conservées.
- Aucune assertion, aucun comportement de test, aucun fichier produit/protocole modifié.

## Vérification et limites

- `git diff --check` propre ; 14 usages vérifiés ; aucun `folderContents` sans étiquette.
- Aucun Swift/Xcode sur le poste Windows : pas de faux GREEN local. Le RED est celui de la CI (exit 65).
- Le candidat doit être reconstruit et testé sur runner Apple ; les 3 diagnostics d'inférence ne sont pas revendiqués comme corrigés avant cette exécution.
