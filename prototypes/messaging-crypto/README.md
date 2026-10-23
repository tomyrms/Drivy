# Prototype synthétique Matrix crypto

## Mise à jour de qualification, 23 octobre 2026 à 22:11 UTC

Le mandat ciblé du porteur du 23 octobre à 22:10 UTC autorise désormais l'exécution ci-dessous. Les mentions « non exécuté » plus bas décrivent l'état historique initial, pas ce résultat.

`cargo test --locked --offline --manifest-path prototypes/messaging-crypto/Cargo.toml` : code retour 0, **4 scénarios passés, 0 échec, 0 ignoré, 0 filtré**, 8,09 s pour les scénarios. Durée murale mesurée de la commande : 29,017546 s, préparation Cargo annoncée : 11,23 s. Les cibles bibliothèque et doctests découvrent chacune 0 test et ne constituent pas une preuve supplémentaire.

Sources exécutées au HEAD `e2657c493029153d46f2ca4ae034ebe8d01304bd`, dernier commit du prototype `60e845f5275fcab822bb9ce335892dda9be5702b`, sans modification du code ou du lockfile. Environnement Windows x86_64, cargo/rustc 1.99.0. Aucun correctif requis. Les clés et messages synthétiques restent en mémoire.

Ce résultat qualifie uniquement les quatre scénarios de primitives SDK 0.19.1. Il ne qualifie pas le binaire iOS FFI 0.17.0, la confiance réelle, les sauvegardes serveur, la persistance, les autorisations scolaires, la résidence suisse ni l'affichage de Messages. Rapport consolidé : `../../docs/qa/validation-finale-20261021.md`.

Autorisation du coordinateur confirmée le 23 octobre 2026 à 01:26 UTC : extension du périmètre à `prototypes/messaging-crypto/**`. **Sources de scénarios écrites, aucun scénario exécuté**, conformément à #84. Aucune activation Drivy ni décision de confidentialité utilisateur n'en découle.

## Périmètre

Machine officielle `matrix-sdk-crypto::OlmMachine`, sans transport réseau. Le laboratoire simule uniquement les réponses standard `/keys/upload`, `/keys/query`, `/keys/claim` et la livraison d'événements `to-device` en mémoire. Les signatures, clés, sessions Olm, sessions Megolm, rotation et export chiffré sont produits/traités par le SDK, jamais par une implémentation cryptographique locale.

- Quatre machines : deux appareils d'un moniteur synthétique, un élève synthétique, un membre synthétique retiré.
- Identifiants exclusivement `example.invalid`, aucun compte réel, aucune configuration réseau ou credential lu.
- Clés aléatoires créées uniquement si les scénarios sont ultérieurement autorisés et exécutés. Aucun état, export, contenu déchiffré ou clé écrit sur disque par le harness.
- Pas de homeserver déployé, pas de dépendance du produit Drivy vers cette crate, pas de binaire applicatif, pas de subscriber de logs/traces.
- Les téléchargements de dépendances et la recherche des avis utilisent les registres/sources publics. Ce n'est pas un flux de conversations ni un service de chat externe.

## Scénarios écrits, non exécutés

| Test | Assertions prévues |
|---|---|
| `group_rotation_excludes_removed_member_but_does_not_erase_received_history` | Les deux appareils et membres initiaux déchiffrent, `discard_room_key` et partage standard renouvellent le session ID, le retiré ne possède pas la nouvelle clé même s'il obtient le ciphertext, son ancien message reste lisible. |
| `second_device_is_excluded_until_explicit_trust_and_excluded_again_after_revocation` | Appareil non approuvé exclu, approbation manuelle de fixture puis nouvelle session, pas d'ancien historique automatique, blacklist + rotation excluent les prochains messages sans effacer les anciens. |
| `replacement_device_with_same_user_id_does_not_recover_historical_keys` | Nouvelle machine du même compte sans les secrets ne peut pas lire l'historique. Ce n'est pas un test OIDC réel. |
| `recovery_requires_the_user_secret_for_a_standard_encrypted_key_export` | Export fichier chiffré SDK, phrase synthétique incorrecte refusée, nouveau terminal sans clés refusé, import officiel avec la phrase correcte puis accès attendu. Pas de sauvegarde serveur Matrix. |

Les exclusions vérifient précisément `MegolmError::MissingRoomKey`, pas seulement n'importe quelle erreur. Les tests remettent volontairement les événements chiffrés au destinataire exclu : un refus de routage ne peut pas faire passer la vérification cryptographique. Les assertions de contenu n'impriment pas le texte attendu/réel.

## Hypothèses explicites, non destinées à la production

- `OnlyTrustedDevices` pour partager, confiance `LocalTrust::Verified` attribuée par la fixture. Ce n'est pas une validation SAS/QR/cross-signing, ni une vérification humaine livrée.
- `TrustRequirement::Untrusted` à la réception uniquement pour isoler le comportement des primitives, puisque le cross-signing n'est pas amorcé. Cette permissivité n'est pas la politique Drivy et doit être remplacée avant tout client réel.
- Liste des membres injectée explicitement dans le harness. Aucune preuve d'autorisation scolaire, protection contre serveur malveillant ou admission de nouveaux membres n'en découle.
- Les sources de scénarios couvrent un seul expéditeur de groupe. La rotation de tous les expéditeurs, les concurrents, le hors-ligne durable, SAS, les sauvegardes serveur, iOS/Keychain et la résidence sont hors qualification.
- Les magasins sont en mémoire. Pas de persistance chiffrée ou de résistance au rollback démontrée.
- La phrase d'export littérale est une fixture publique synthétique, jamais un secret réel ou un défaut de production. Le nombre d'itérations d'export est un paramètre de scénario, pas une politique approuvée.

## Versions et reproductibilité

Dépendances directes exactes : `matrix-sdk-crypto =0.19.1`, `ruma =0.17.1`, `serde_json =1.0.154`, `tokio =1.54.1`. `Cargo.lock` versionne les résolutions et checksums, dont vodozemac `0.11.1`. Aucun patch/fork ni feature SDK `testing`, forwarding automatique ou algorithme expérimental activé directement.

Provenances déclarées par `.cargo_vcs_info.json` des crates téléchargées :

- matrix-sdk-crypto : `b18166c68bb958a21f0bca8b2d8320cb53583362`, chemin `crates/matrix-sdk-crypto`.
- vodozemac : `3e11ae87d157da6bcac3cbf7825d37c8f5ed60af`.

Ces métadonnées de provenance ne remplacent pas une vérification reproductible des sources/artefacts. Voir `SECURITY-REVIEW.md` pour les avis et les features transitives sensibles.

## Commandes de compilation uniquement

Depuis la racine du dépôt :

```text
cargo check --locked --offline --all-targets --manifest-path prototypes/messaging-crypto/Cargo.toml
cargo build --locked --offline --tests --manifest-path prototypes/messaging-crypto/Cargo.toml
cargo fmt --check --manifest-path prototypes/messaging-crypto/Cargo.toml
```

`cargo build --tests` compile et lie les binaires de test, **sans les exécuter**. Ne pas remplacer par `cargo test` dans le cadre #84. Les dépendances doivent avoir été téléchargées avant le mode offline. `target/` est ignoré dans Git.

## Preuves du 23 octobre 2026

- Résolution et téléchargement de dépendances : réussis, lockfile créé.
- `cargo check --locked --offline --all-targets` : réussi avec les quatre scénarios.
- Compilation native des binaires des quatre scénarios : réussie avec `cargo build --locked --offline --tests`, code retour 0. Aucun binaire exécuté.
- Exécution de scénarios : **NON EXÉCUTÉE**. Aucune assertion n'est présentée comme passée, pas de résultat TDD rouge/vert revendiqué.
- Chaîne locale observée : Windows x86_64, cargo 1.99.0, rustc 1.99.0. Pas de compilation Swift/Apple.

## Sources

- API officielle de la version fixée : `https://docs.rs/matrix-sdk-crypto/0.19.1/matrix_sdk_crypto/`.
- Tutoriel officiel : `https://docs.rs/matrix-sdk-crypto/0.19.1/matrix_sdk_crypto/tutorial/`.
- Code source des APIs inspecté dans la crate téléchargée : `src/machine/mod.rs`, `src/types/requests/`, `src/store/mod.rs`, `src/file_encryption/key_export.rs`. Le harness n'utilise aucune API interne de test.
- Notes de décision : `../../docs/implementation/messaging-security-20261023.md` et `../../docs/implementation/messaging-residency-20261023.md`.
