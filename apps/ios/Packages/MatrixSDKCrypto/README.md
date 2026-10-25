# MatrixSDKCrypto (paquet local)

Enveloppe SPM de la distribution Apple officielle de `matrix-sdk-crypto-ffi` publiée par matrix-org.

- Source : release GitHub `matrix-org/matrix-rust-sdk` `matrix-sdk-crypto-ffi-0.17.0` (26 mai 2026), actif `MatrixSDKCryptoFFI.zip`.
- SHA-256 de l'archive : `7d5e15e072eccb8cf105570bd50ebde9dece60b1bcef007139b4f265f2b0d75a` (digest GitHub et calcul local identiques). SwiftPM refuse toute archive dont la somme diffère.
- matrix-org ne publie pas de `Package.swift` pour ce binaire : la voie officielle est le podspec `MatrixSDKCrypto` (`bindings/apple/MatrixSDKCrypto.podspec`) qui vend la même archive. Ce paquet reprend exactement ce podspec : `vendored_frameworks` = cible binaire, `source_files` = `Sources/*.swift` copiés sans modification depuis l'archive.
- Version identique à celle utilisée par `matrix-ios-sdk` (`MatrixSDKCrypto 0.17.0`).
- Licence Apache-2.0 (`LICENSE`).

Mise à jour : télécharger la nouvelle archive, vérifier le digest de la release, recopier `Sources/*.swift`, changer URL et somme dans `Package.swift`.
