//! In-memory simulation of standard Matrix key-directory and to-device delivery.
//! It does not implement encryption, a homeserver, OIDC, or production trust UX.
//! Only public SDK APIs generate keys, sign, establish Olm, and operate Megolm.

use std::collections::BTreeMap;

use matrix_sdk_crypto::{
    CollectStrategy, DecryptionSettings, EncryptionSettings, EncryptionSyncChanges, LocalTrust,
    MegolmError, OlmMachine, TrustRequirement,
    types::{events::room::encrypted::EncryptedEvent, requests::AnyOutgoingRequest},
};
use ruma::{
    OneTimeKeyAlgorithm, OwnedDeviceId, OwnedOneTimeKeyId, OwnedUserId, RoomId, UInt,
    api::client::{
        keys::{claim_keys, get_keys, upload_keys},
        to_device::send_event_to_device,
    },
    device_id,
    encryption::{DeviceKeys, OneTimeKey},
    events::room::{history_visibility::HistoryVisibility, message::RoomMessageEventContent},
    serde::Raw,
    to_device::DeviceIdOrAllDevices,
    user_id,
};
use serde_json::{Value, json};

type PublicDirectory = BTreeMap<OwnedUserId, BTreeMap<OwnedDeviceId, Raw<DeviceKeys>>>;
type PublicOneTimeKeys =
    BTreeMap<(OwnedUserId, OwnedDeviceId), BTreeMap<OwnedOneTimeKeyId, Raw<OneTimeKey>>>;
pub type Encrypted = Raw<EncryptedEvent>;

pub struct Lab {
    pub devices: Vec<OlmMachine>,
    one_time_keys: PublicOneTimeKeys,
}

// Incoming trust is deliberately permissive ONLY for this primitive study:
// cross-signing/SAS is not bootstrapped. Outgoing sharing is restricted below to
// manually fixture-approved devices. This is NOT the Drivy production policy.
fn decryption_settings() -> DecryptionSettings {
    DecryptionSettings {
        sender_device_trust_requirement: TrustRequirement::Untrusted,
    }
}

impl Lab {
    pub async fn new() -> Self {
        let devices = vec![
            OlmMachine::new(user_id!("@instructor:example.invalid"), device_id!("PHONE")).await,
            OlmMachine::new(
                user_id!("@instructor:example.invalid"),
                device_id!("TABLET"),
            )
            .await,
            OlmMachine::new(user_id!("@learner:example.invalid"), device_id!("LEARNER")).await,
            OlmMachine::new(user_id!("@removed:example.invalid"), device_id!("REMOVED")).await,
        ];
        let mut directory = PublicDirectory::new();
        let mut one_time_keys = PublicOneTimeKeys::new();

        for device in &devices {
            let outgoing = device
                .outgoing_requests()
                .await
                .expect("prepare key upload");
            let mut uploaded = false;
            for request in outgoing {
                if let AnyOutgoingRequest::KeysUpload(upload) = request.request() {
                    let public = upload
                        .device_keys
                        .clone()
                        .expect("initial public device keys");
                    directory
                        .entry(device.user_id().to_owned())
                        .or_default()
                        .insert(device.device_id().to_owned(), public);
                    one_time_keys.insert(
                        (device.user_id().to_owned(), device.device_id().to_owned()),
                        upload.one_time_keys.clone(),
                    );
                    let count =
                        UInt::try_from(upload.one_time_keys.len()).expect("bounded key count");
                    let response = upload_keys::v3::Response::new(BTreeMap::from([(
                        OneTimeKeyAlgorithm::SignedCurve25519,
                        count,
                    )]));
                    device
                        .mark_request_as_sent(request.request_id(), &response)
                        .await
                        .expect("acknowledge in-memory key upload");
                    uploaded = true;
                }
            }
            assert!(uploaded, "SDK must generate initial keys");
        }

        for device in &devices {
            device
                .update_tracked_users(directory.keys().map(|user| user.as_ref()))
                .await
                .expect("track synthetic users");
            let outgoing = device.outgoing_requests().await.expect("prepare key query");
            let mut queried = false;
            for request in outgoing {
                if let AnyOutgoingRequest::KeysQuery(query) = request.request() {
                    let mut response = get_keys::v3::Response::new();
                    for user in query.device_keys.keys() {
                        response
                            .device_keys
                            .insert(user.clone(), directory[user].clone());
                    }
                    device
                        .mark_request_as_sent(request.request_id(), &response)
                        .await
                        .expect("process standard device-key query response");
                    queried = true;
                }
            }
            assert!(queried, "SDK must query tracked devices");
        }
        Self {
            devices,
            one_time_keys,
        }
    }

    pub async fn trust_fixture_devices(&self) {
        // Trust is explicitly provided by this synthetic fixture, never inferred
        // from a server-supplied role or a successful login.
        for index in 1..self.devices.len() {
            self.set_sender_trust(index, LocalTrust::Verified).await;
        }
    }

    pub async fn set_sender_trust(&self, index: usize, trust: LocalTrust) {
        let recipient = &self.devices[index];
        self.devices[0]
            .get_device(recipient.user_id(), recipient.device_id(), None)
            .await
            .expect("lookup fixture device")
            .expect("fixture device exists")
            .set_local_trust(trust)
            .await
            .expect("persist fixture trust");
    }

    pub async fn share(&mut self, room: &RoomId, member_indices: &[usize]) {
        let sender = &self.devices[0];
        let users: Vec<OwnedUserId> = member_indices
            .iter()
            .map(|index| self.devices[*index].user_id().to_owned())
            .collect();
        if let Some((id, claim)) = sender
            .get_missing_sessions(users.iter().map(|u| u.as_ref()))
            .await
            .expect("request missing Olm sessions")
        {
            let mut response_keys = BTreeMap::new();
            for (user, targets) in claim.one_time_keys {
                for (device, _algorithm) in targets {
                    let pool = self
                        .one_time_keys
                        .get_mut(&(user.clone(), device.clone()))
                        .expect("public one-time key pool");
                    let (key_id, key) = pool.pop_first().expect("unused signed one-time key");
                    response_keys
                        .entry(user.clone())
                        .or_insert_with(BTreeMap::new)
                        .insert(device, BTreeMap::from([(key_id, key)]));
                }
            }
            sender
                .mark_request_as_sent(&id, &claim_keys::v3::Response::new(response_keys))
                .await
                .expect("establish SDK Olm sessions");
        }

        let settings = EncryptionSettings {
            sharing_strategy: CollectStrategy::OnlyTrustedDevices,
            history_visibility: HistoryVisibility::Joined,
            ..EncryptionSettings::default()
        };
        let requests = sender
            .share_room_key(room, users.iter().map(|u| u.as_ref()), settings)
            .await
            .expect("prepare SDK room-key messages");
        for request in requests {
            for (user, targets) in &request.messages {
                for (target, content) in targets {
                    let DeviceIdOrAllDevices::DeviceId(device_id) = target else {
                        panic!("wildcard routing not supported in this closed fixture");
                    };
                    let recipient = self
                        .devices
                        .iter()
                        .find(|candidate| {
                            candidate.user_id() == user && candidate.device_id() == device_id
                        })
                        .expect("recipient belongs to synthetic lab");
                    let event = serde_json::from_value(json!({
                        "sender": sender.user_id(),
                        "type": request.event_type,
                        "content": content,
                    }))
                    .expect("standard to-device event envelope");
                    recipient
                        .receive_sync_changes(
                            EncryptionSyncChanges {
                                to_device_events: vec![event],
                                changed_devices: &Default::default(),
                                one_time_keys_counts: &Default::default(),
                                unused_fallback_keys: None,
                                next_batch_token: None,
                            },
                            &decryption_settings(),
                        )
                        .await
                        .expect("receive SDK to-device message");
                }
            }
            sender
                .mark_request_as_sent(&request.txn_id, &send_event_to_device::v3::Response::new())
                .await
                .expect("acknowledge in-memory to-device delivery");
        }
    }
}

pub async fn encrypt(sender: &OlmMachine, room: &RoomId, event_id: &str, body: &str) -> Encrypted {
    let encrypted = sender
        .encrypt_room_event(room, RoomMessageEventContent::text_plain(body))
        .await
        .expect("SDK room encryption");
    let event: Encrypted = serde_json::from_value(json!({
        "type": "m.room.encrypted",
        "sender": sender.user_id(),
        "event_id": event_id,
        "origin_server_ts": 1,
        "content": encrypted.content,
    }))
    .expect("standard encrypted room event envelope");
    assert!(
        !event.json().get().contains(body),
        "transport must not contain synthetic plaintext"
    );
    event
}

pub fn session_id(event: &Encrypted) -> String {
    let value: Value = serde_json::from_str(event.json().get()).expect("event JSON");
    value["content"]["session_id"]
        .as_str()
        .expect("Megolm session identifier")
        .to_owned()
}

pub async fn assert_decrypts(device: &OlmMachine, room: &RoomId, event: &Encrypted, body: &str) {
    let decrypted = device
        .decrypt_room_event(event, room, &decryption_settings())
        .await
        .expect("authorized recipient must decrypt using SDK");
    let value: Value =
        serde_json::from_str(decrypted.event.json().get()).expect("decrypted event JSON");
    // Do not print payloads or cryptographic state when an assertion fails.
    assert!(
        value["content"]["body"].as_str() == Some(body),
        "unexpected synthetic plaintext"
    );
}

pub async fn assert_missing_key(device: &OlmMachine, room: &RoomId, event: &Encrypted) {
    let result = device
        .decrypt_room_event(event, room, &decryption_settings())
        .await;
    assert!(
        matches!(result, Err(MegolmError::MissingRoomKey(_))),
        "excluded or replacement device must lack the room key"
    );
}
