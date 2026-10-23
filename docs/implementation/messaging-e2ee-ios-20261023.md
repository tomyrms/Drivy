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
- Rotation : session de groupe jetée (`discardRoomKey`) quand un membre a quitté depuis le dernier envoi de cet appareil, quand `membersEpoch` (réponse `GET conversations/{id}/members`, augmente à chaque départ et retour) a changé, ou quand le sync annonce un départ (`device_lists.left`) touchant un salon mémorisé ; rotation périodique 7 jours ou 100 messages.
- Sauvegarde : `m.megolm_backup.v1.curve25519-aes-sha2`, clé de récupération base58 montrée une fois ; restauration vérifie que la clé correspond à `auth_data.public_key` et renvoie (importées, échouées). Échec d'envoi à la sauvegarde : drapeau `backupPending` scellé, nouvel essai au prochain open/sync, exposé par `backupPending(scope:)` pour l'UI de sauvegarde.
- Déchiffrement sans clé de salon (`MissingRoomKey` seulement) : un sync partagé par lot (un seul en vol, pas de nouveau sync dans les 5 s suivantes).
- Vérification croisée de ses propres appareils : comparaison d'empreinte ed25519 puis signature croisée (`device_signing/upload`, `signatures/upload`). L'UI reste à faire.
- Store : SQLite chiffré de matrix-sdk-crypto avec passphrase 32 octets aléatoire en Keychain (`AfterFirstUnlockThisDeviceOnly`), dossier `completeUntilFirstUserAuthentication`, exclu des sauvegardes. Store présent sans passphrase : le secret Keychain est écrit avant la création du dossier ; un store vide sans secret (essai interrompu) est recréé, un store non vide sans secret reste une erreur, jamais d'ouverture en clair. État auxiliaire (jeton de sync, membres) scellé AES-GCM.
- Relais : `MessagingCryptoHTTPRelay`, contrat convenu avec l'agent backend (en-tête `X-Drivy-Device-Id`, réponses Matrix brutes dans `data`, 409 `BACKUP_VERSION_CONFLICT`).

## Risque accepté : confiance au premier usage

Le serveur Drivy fournit la liste des membres et les clés d'appareils (`keys/query`) ; les appareils non vérifiés sont acceptés (`onlyAllowTrustedDevices: false`, `senderDeviceTrustRequirement: .untrusted`). Un serveur compromis pourrait donc ajouter un membre ou un appareil et recevoir les clés des messages suivants. Risque accepté pour cette phase : les droits scolaires sont déjà relus au serveur, et la vérification croisée de ses propres appareils existe. À revoir : vérification entre personnes et alerte de changement d'identité.

## Activation

Injecté seulement dans `MessagingDevelopmentEntry` (DEBUG + simulateur + `-messaging-development`). Messages reste masqué en Release.

## Non qualifié

- Tests `MatrixMessagingCryptographyTests` écrits, non exécutés (#84), dont l'échange réel à deux appareils et la rotation.
- Aucun essai contre l'API réelle, aucune mesure sur appareil physique.
