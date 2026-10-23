# Messagerie : chiffrement de bout en bout iOS (#67), 23 octobre 2026

## Bibliothèque

- `matrix-sdk-crypto-ffi` 0.17.0, distribution Apple officielle de matrix-org (release `matrix-sdk-crypto-ffi-0.17.0`, `MatrixSDKCryptoFFI.zip`, SHA-256 `7d5e15e0…d75a`). matrix-org publie ce binaire pour CocoaPods (`MatrixSDKCrypto.podspec`), pas de `Package.swift`. Le paquet local `apps/ios/Packages/MatrixSDKCrypto` reprend ce podspec en SwiftPM : cible binaire épinglée par URL + somme, sources Swift UniFFI copiées sans modification.
- Pas de build xcframework depuis `prototypes/messaging-crypto` : le binaire officiel suffit et reste vérifiable.
- `Package.resolved` inchangé : un paquet local n'y est pas épinglé ; l'intégrité vient de la somme de la cible binaire.

## Implémentation

- `MatrixMessagingCryptography` (MessagingCore) conforme à `MessagingCryptography` et `MessagingKeyManagement`.
- Identifiants Matrix : `@<personId>:drivy`, `!<conversationId>:drivy`, appareil 16 caractères [A-Z0-9] aléatoires.
- Enveloppe : `scheme = megolm.v1`, `keyId` = session Megolm (base64url), `payload` = contenu `m.room.encrypted` JSON.
- Déchiffrement : exige l'enveloppe complète (`decrypt(_ message:)`) car l'expéditeur fait partie de l'authentification ; la forme sans expéditeur est refusée. `mismatchedSender` refusé.
- Rotation : session de groupe jetée (`discardRoomKey`) quand un membre a quitté depuis le dernier envoi (liste `GET conversations/{id}/members`) ; rotation périodique 7 jours ou 100 messages.
- Sauvegarde : `m.megolm_backup.v1.curve25519-aes-sha2`, clé de récupération base58 montrée une fois ; restauration vérifie que la clé correspond à `auth_data.public_key`.
- Vérification croisée de ses propres appareils : comparaison d'empreinte ed25519 puis signature croisée (`device_signing/upload`, `signatures/upload`). L'UI reste à faire.
- Store : SQLite chiffré de matrix-sdk-crypto avec passphrase 32 octets aléatoire en Keychain (`AfterFirstUnlockThisDeviceOnly`), dossier `completeUntilFirstUserAuthentication`, exclu des sauvegardes. Store présent sans passphrase : erreur, jamais de recréation ni ouverture en clair. État auxiliaire (jeton de sync, membres) scellé AES-GCM.
- Relais : `MessagingCryptoHTTPRelay`, contrat convenu avec l'agent backend (en-tête `X-Drivy-Device-Id`, réponses Matrix brutes dans `data`, 409 `BACKUP_VERSION_CONFLICT`).

## Activation

Injecté seulement dans `MessagingDevelopmentEntry` (DEBUG + simulateur + `-messaging-development`). Messages reste masqué en Release.

## Non qualifié

- Tests `MatrixMessagingCryptographyTests` écrits, non exécutés (#84), dont l'échange réel à deux appareils et la rotation.
- Aucun essai contre l'API réelle, aucune mesure sur appareil physique.
