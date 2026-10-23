//! Scenario sources only. Per #84 these have NOT been executed.
//! Mutations that should make these scenarios fail include retaining an old
//! outbound session after removal, sharing with an untrusted device, or treating
//! a replacement account login as possession of historical keys.
#![forbid(unsafe_code)]

mod support;

use matrix_sdk_crypto::{LocalTrust, OlmMachine};
use ruma::{device_id, room_id, user_id};
use support::{Lab, assert_decrypts, assert_missing_key, encrypt, session_id};

#[tokio::test]
async fn recovery_requires_the_user_secret_for_a_standard_encrypted_key_export() {
    use matrix_sdk_crypto::{decrypt_room_key_export, encrypt_room_key_export};
    use std::io::Cursor;

    let mut lab = Lab::new().await;
    let room = room_id!("!synthetic-recovery:example.invalid");
    lab.trust_fixture_devices().await;
    lab.share(room, &[0, 2]).await;
    let event = encrypt(&lab.devices[0], room, "$recoverable", "SYNTHETIC_RECOVERY").await;
    assert_decrypts(&lab.devices[2], room, &event, "SYNTHETIC_RECOVERY").await;
    let exported = lab.devices[2]
        .store()
        .export_room_keys(|session| session.room_id() == room)
        .await
        .expect("export only this synthetic room");
    assert!(
        !exported.is_empty(),
        "recipient must hold an inbound group session"
    );
    // Public test fixture string, NEVER a real credential or production default.
    let fixture_secret = "PUBLIC_SYNTHETIC_RECOVERY_PHRASE_NOT_A_REAL_SECRET";
    let encrypted_export = encrypt_room_key_export(&exported, fixture_secret, 100_000)
        .expect("SDK encrypted key export");
    assert!(
        decrypt_room_key_export(Cursor::new(&encrypted_export), "WRONG_SYNTHETIC_PHRASE").is_err(),
        "wrong recovery secret must fail"
    );
    let recovered = OlmMachine::new(
        user_id!("@learner:example.invalid"),
        device_id!("RECOVERED"),
    )
    .await;
    assert_missing_key(&recovered, room, &event).await;
    let keys = decrypt_room_key_export(Cursor::new(&encrypted_export), fixture_secret)
        .expect("SDK decrypts key export with fixture recovery secret");
    let imported = recovered
        .store()
        .import_exported_room_keys(keys, |_, _| {})
        .await
        .expect("SDK imports recovered room keys");
    assert!(
        imported.imported_count > 0,
        "room key must actually be imported"
    );
    assert_decrypts(&recovered, room, &event, "SYNTHETIC_RECOVERY").await;
}

#[tokio::test]
async fn group_rotation_excludes_removed_member_but_does_not_erase_received_history() {
    let mut lab = Lab::new().await;
    let room = room_id!("!synthetic-group:example.invalid");
    lab.trust_fixture_devices().await;
    lab.share(room, &[0, 2, 3]).await;
    let before = encrypt(&lab.devices[0], room, "$before", "SYNTHETIC_BEFORE").await;
    for recipient in [1, 2, 3] {
        assert_decrypts(&lab.devices[recipient], room, &before, "SYNTHETIC_BEFORE").await;
    }

    // Membership authority is simulated by this explicit recipient list. The
    // cryptographic rotation itself is performed by the official SDK.
    assert!(
        lab.devices[0]
            .discard_room_key(room)
            .await
            .expect("discard room key")
    );
    lab.share(room, &[0, 2]).await;
    let after = encrypt(&lab.devices[0], room, "$after", "SYNTHETIC_AFTER").await;
    assert!(
        session_id(&before) != session_id(&after),
        "SDK must rotate the session"
    );
    for recipient in [1, 2] {
        assert_decrypts(&lab.devices[recipient], room, &after, "SYNTHETIC_AFTER").await;
    }
    assert_missing_key(&lab.devices[3], room, &after).await;
    // Deliberately hand the excluded member the ciphertext, bypassing a server
    // ACL: denial must be due to missing cryptographic key, not routing alone.
    assert_decrypts(&lab.devices[3], room, &before, "SYNTHETIC_BEFORE").await;
}

#[tokio::test]
async fn second_device_is_excluded_until_explicit_trust_and_excluded_again_after_revocation() {
    let mut lab = Lab::new().await;
    let room = room_id!("!synthetic-devices:example.invalid");
    lab.trust_fixture_devices().await;
    lab.set_sender_trust(1, LocalTrust::Unset).await;
    lab.share(room, &[0, 2]).await;
    let first = encrypt(&lab.devices[0], room, "$untrusted", "SYNTHETIC_UNTRUSTED").await;
    assert_missing_key(&lab.devices[1], room, &first).await;
    assert_decrypts(&lab.devices[2], room, &first, "SYNTHETIC_UNTRUSTED").await;

    // Synthetic out-of-band fixture approval, not a shipped SAS/QR workflow.
    lab.set_sender_trust(1, LocalTrust::Verified).await;
    assert!(
        lab.devices[0]
            .discard_room_key(room)
            .await
            .expect("rotate for added device")
    );
    lab.share(room, &[0, 2]).await;
    let joined = encrypt(&lab.devices[0], room, "$verified", "SYNTHETIC_VERIFIED").await;
    assert_decrypts(&lab.devices[1], room, &joined, "SYNTHETIC_VERIFIED").await;
    assert_missing_key(&lab.devices[1], room, &first).await;

    lab.set_sender_trust(1, LocalTrust::BlackListed).await;
    assert!(
        lab.devices[0]
            .discard_room_key(room)
            .await
            .expect("rotate for revoked device")
    );
    lab.share(room, &[0, 2]).await;
    let revoked = encrypt(&lab.devices[0], room, "$revoked", "SYNTHETIC_REVOKED").await;
    assert_missing_key(&lab.devices[1], room, &revoked).await;
    assert_decrypts(&lab.devices[2], room, &revoked, "SYNTHETIC_REVOKED").await;
    assert_decrypts(&lab.devices[1], room, &joined, "SYNTHETIC_VERIFIED").await;
}

#[tokio::test]
async fn replacement_device_with_same_user_id_does_not_recover_historical_keys() {
    let mut lab = Lab::new().await;
    let room = room_id!("!synthetic-loss:example.invalid");
    lab.trust_fixture_devices().await;
    lab.share(room, &[0, 2]).await;
    let event = encrypt(&lab.devices[0], room, "$history", "SYNTHETIC_HISTORY").await;
    assert_decrypts(&lab.devices[2], room, &event, "SYNTHETIC_HISTORY").await;

    let replacement = OlmMachine::new(
        user_id!("@learner:example.invalid"),
        device_id!("REPLACEMENT"),
    )
    .await;
    assert_missing_key(&replacement, room, &event).await;
}
