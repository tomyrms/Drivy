# Revue amont du prototype crypto

23 octobre 2026. Revue ciblée des avis officiels, **pas un audit exhaustif de toutes les dépendances ni une certification d'absence de vulnérabilité**. Aucun scénario exécuté. La compilation ne prouve pas la sécurité d'une intégration.

## Ensemble effectivement verrouillé

`Cargo.lock` : matrix-sdk-crypto 0.19.1, vodozemac 0.11.1. `cargo tree --locked --offline -i vodozemac` confirme le lien direct depuis le SDK. Licences amont : Apache-2.0 pour ces deux composants, MIT pour Ruma et Tokio, MIT OU Apache-2.0 pour serde_json selon leurs métadonnées Cargo. Les notices et licences transitives restent à inventorier avant distribution d'un client.

## Avis publiés inspectés

Les bornes ci-dessous sont celles des pages de mainteneurs consultées. Conclusion limitée : les versions verrouillées des composants crypto ne sont pas dans les plages affectées **de ces avis**, sans garantie sur d'autres défauts.

| Avis | Composant / plage affectée publiée | Correction publiée | Portée de cette revue |
|---|---|---|---|
| GHSA-45pr-7vv7-f64m, 29 septembre 2026 | matrix-sdk-crypto < 0.19.0 | 0.19.0 | 0.19.1 hors plage. Panique messages custom to-device avec identité absente. |
| GHSA-wfq4-36m3-9g42, 3 juin 2026 | matrix-sdk-crypto >= 0.12.0, < 0.16.1 | 0.16.1 | 0.19.1 hors plage. Liaison de l'expéditeur des messages to-device. |
| GHSA-x958-rvg6-956w, 10 juin 2025 | matrix-sdk-crypto >= 0.8.0, < 0.11.1 | 0.11.1 et 0.12.0 | 0.19.1 hors plage. Usurpation expéditeur par homeserver. |
| GHSA-r5vf-wf4h-82gg, 7 janvier 2025 | matrix-sdk-crypto < 0.8.0 | 0.8.0 | 0.19.1 hors plage. Changement d'identité vérifiée à signaler au client. |
| GHSA-4qg4-cvh2-crgg, 18 juillet 2024 | matrix-sdk-crypto < 0.7.2 | 0.7.2 | 0.19.1 hors plage. Vérification de l'identité propre. |
| GHSA-9ggc-845v-gcgv, 13 mai 2024 | matrix-sdk-crypto 0.7.0 | 0.7.1 | 0.19.1 hors plage. Exposition de clé de sauvegarde dans logs. Aucun subscriber dans ce prototype. |
| GHSA-j8cm-g7r6-hfpq, 17 juillet 2024 | vodozemac < 0.7.0 | 0.7.0 | 0.11.1 hors plage. Base64 non constant-time lors d'import de secrets. |
| GHSA-c3hm-hxwf-g5c6, 2 mai 2024 | vodozemac 0.5.0, 0.5.1 | 0.6.0 | 0.11.1 hors plage. Dégradation de zeroization. |
| GHSA-h97m-27fx-42rx, 3 juin 2026 | matrix-sdk-ui < 0.16.1 | 0.16.1 | SDK UI absent du prototype. À revoir pour client complet, validation des éditions chiffrées. |

Les listes amont contiennent aussi des avis portant sur EventCache, RoomMember et événements join_rules : pas une preuve de couverture de ces surfaces par la machine crypto. Ils devront être revus lors du choix du SDK client/homeserver complet. Aucun `cargo audit` ou audit de toutes les transitives exécuté ici.

## Avertissement de conception non masqué par les avis corrigés

`cargo tree -e features -i vodozemac` montre que matrix-sdk-crypto active transitivement `insecure-pk-encryption`, `experimental-session-config` et, via les defaults/compatibilité, `libolm-compat` et `precomputed-tables`. Le `default-features = false` du SDK **ne supprime pas ces features transitives**.

Le source officiel de vodozemac 0.11.1, `src/pk_encryption.rs`, avertit que le mécanisme de compatibilité `m.megolm_backup.v1.curve25519-aes-sha2` n'authentifie pas le ciphertext. **Aucune adoption de sauvegarde serveur de ce type n'est autorisée ou qualifiée.** Ce point doit être tranché avant choisir une récupération réelle, pas contourné avec une surcouche cryptographique maison.

Le prototype appelle uniquement le chemin **export fichier chiffré** `encrypt_room_key_export` / `decrypt_room_key_export` et l'import du store, distinct du module `PkEncryption` et des APIs de sauvegarde serveur. Il n'appelle ni `PkEncryption`, ni `PkDecryption`, ni `BackupMachine`. Cela limite le scénario, mais ne transforme pas la crate ou le mécanisme de sauvegarde complet en « sûr par défaut ». La récupération produit reste bloquée jusqu'à choix/revue d'un mécanisme maintenu approprié.

Autre limite volontaire : l'absence de cross-signing/SAS dans la fixture oblige à ne pas confondre confiance locale synthétique et identité réelle. Le paramètre de déchiffrement `Untrusted` est documenté comme impropre à reprendre tel quel dans Drivy.

## Références officielles

Toutes consultées le 23 octobre 2026. Chaque identifiant du tableau correspond à la page située sous son préfixe officiel :

```text
https://github.com/matrix-org/matrix-rust-sdk/security/advisories/GHSA-45pr-7vv7-f64m
https://github.com/matrix-org/matrix-rust-sdk/security/advisories/GHSA-wfq4-36m3-9g42
https://github.com/matrix-org/matrix-rust-sdk/security/advisories/GHSA-x958-rvg6-956w
https://github.com/matrix-org/matrix-rust-sdk/security/advisories/GHSA-r5vf-wf4h-82gg
https://github.com/matrix-org/matrix-rust-sdk/security/advisories/GHSA-4qg4-cvh2-crgg
https://github.com/matrix-org/matrix-rust-sdk/security/advisories/GHSA-9ggc-845v-gcgv
https://github.com/matrix-org/vodozemac/security/advisories/GHSA-j8cm-g7r6-hfpq
https://github.com/matrix-org/vodozemac/security/advisories/GHSA-c3hm-hxwf-g5c6
https://github.com/matrix-org/matrix-rust-sdk/security/advisories/GHSA-h97m-27fx-42rx
https://github.com/matrix-org/matrix-rust-sdk/security/advisories
https://github.com/matrix-org/vodozemac/security/advisories
```

Source versionné inspecté dans l'archive Cargo de vodozemac 0.11.1 : `src/pk_encryption.rs` lignes 15–24, provenance Git déclarée `3e11ae87d157da6bcac3cbf7825d37c8f5ed60af`. SDK 0.19.1 `Cargo.toml` : features vodozemac lignes 321–326. Les checksums d'archives sont conservés dans `Cargo.lock`, aucun téléchargement de code arbitraire n'est utilisé dans le harness.
