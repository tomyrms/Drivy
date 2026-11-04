//! Vecteurs croisés du format Matrix « encrypted attachments v2 » (#97, T2a).
//!
//! Oracle : `AttachmentEncryptor`, `AttachmentDecryptor` et `MediaEncryptionInfo`
//! de `matrix-sdk-crypto` 0.19.1, la version épinglée par ce prototype. Ce
//! fichier n'écrit aucune primitive cryptographique : il ne fait que produire et
//! relire des octets avec le module officiel, puis publier le résultat dans
//! `apps/ios/DrivyTests/Fixtures/media-vectors.json` pour les tests Swift.
//!
//! Régénérer les vecteurs après un changement de format :
//!
//! ```text
//! # PowerShell
//! $env:DRIVY_MEDIA_VECTORS_WRITE = "1"; cargo test --locked --test media_vectors
//! # sh/bash
//! DRIVY_MEDIA_VECTORS_WRITE=1 cargo test --locked --test media_vectors
//! ```
//!
//! Les clés et les octets sont synthétiques : aucune donnée de personne, aucun
//! secret réel, aucune valeur issue d'un compte Drivy.

use std::env;
use std::ffi::OsStr;
use std::fs;
use std::io::{Cursor, Read};
use std::path::Path;

use matrix_sdk_crypto::{AttachmentDecryptor, AttachmentEncryptor, MediaEncryptionInfo};
use ruma::serde::{
    Base64,
    base64::{Standard, UrlSafe},
};
use serde_json::{Value, json};

/// Chemin du fichier consommé par `MessagingMediaCryptographyTests.swift`.
const FIXTURE_PATH: &str = concat!(
    env!("CARGO_MANIFEST_DIR"),
    "/../../apps/ios/DrivyTests/Fixtures/media-vectors.json"
);

/// Tailles stockées dans la fixture. `4 194 304` est exercé en mémoire par
/// `large_sizes_are_exercised_with_the_official_oracle` : un JSON de 4 Mio en
/// base64 n'apporterait rien et pèserait 5,6 Mo.
const STORED_SIZES: [usize; 6] = [0, 1, 15, 16, 17, 65_536];

/// Plafond produit (§4.3). La primitive accepte 0 octet ; l'upload refusera 0.
const MAX_MEDIA_BYTES: usize = 4_194_304;

/// Règle de clair partagée mot pour mot avec `MessagingMediaCryptographyTests.swift`
/// et documentée dans `docs/implementation/messaging-media-97-crypto.md`.
fn plaintext_byte(index: usize) -> u8 {
    let index = index as u64;
    (7 + 31 * index + (index >> 8)) as u8
}

fn plaintext(len: usize) -> Vec<u8> {
    (0..len).map(plaintext_byte).collect()
}

/// Chiffre avec l'implémentation officielle et rend l'info sérialisée.
fn seal(plain: &[u8]) -> (Vec<u8>, Value) {
    let mut reader = Cursor::new(plain);
    let mut encryptor = AttachmentEncryptor::new(&mut reader);
    let mut ciphertext = Vec::with_capacity(plain.len());
    encryptor
        .read_to_end(&mut ciphertext)
        .expect("le chiffreur officiel lit le clair");
    let info = encryptor.finish();
    (
        ciphertext,
        serde_json::to_value(&info).expect("sérialisation de MediaEncryptionInfo"),
    )
}

/// Déchiffre avec l'implémentation officielle. Toute erreur est rendue pour que
/// les cas de refus puissent être distingués d'un succès.
fn open(ciphertext: &[u8], info: &Value) -> Result<Vec<u8>, String> {
    let info: MediaEncryptionInfo =
        serde_json::from_value(info.clone()).map_err(|error| format!("info refusée: {error}"))?;
    let mut reader = Cursor::new(ciphertext);
    let mut decryptor = AttachmentDecryptor::new(&mut reader, info)
        .map_err(|error| format!("déchiffreur refusé: {error}"))?;
    let mut plain = Vec::with_capacity(ciphertext.len());
    decryptor
        .read_to_end(&mut plain)
        .map_err(|error| format!("lecture refusée: {error}"))?;
    Ok(plain)
}

fn field<'a>(info: &'a Value, pointer: &str) -> &'a str {
    info.pointer(pointer)
        .and_then(Value::as_str)
        .unwrap_or_else(|| panic!("champ texte absent: {pointer}"))
}

fn key_text(info: &Value) -> &str {
    field(info, "/key/k")
}

fn iv_text(info: &Value) -> &str {
    field(info, "/iv")
}

fn hash_text(info: &Value) -> &str {
    field(info, "/hashes/sha256")
}

/// `k` doit rester en base64url : `-` ou `_` prouve que l'alphabet n'est pas standard.
fn has_url_safe_symbol(text: &str) -> bool {
    text.chars().any(|symbol| symbol == '-' || symbol == '_')
}

/// `iv`/`sha256` doivent rester en base64 standard : `+` ou `/`.
fn has_standard_symbol(text: &str) -> bool {
    text.chars().any(|symbol| symbol == '+' || symbol == '/')
}

fn encode_standard(bytes: &[u8]) -> String {
    Base64::<Standard>::new(bytes.to_vec()).encode()
}

fn encode_url_safe(bytes: &[u8]) -> String {
    Base64::<UrlSafe>::new(bytes.to_vec()).encode()
}

fn decode_standard(text: &str) -> Vec<u8> {
    Base64::<Standard>::parse(text)
        .expect("base64 standard attendu dans la fixture")
        .into_inner()
}

/// Produit un vecteur dont la clé, l'IV et le hash couvrent tous les deux
/// alphabets. L'aléa est celui du module officiel : on ne peut pas imposer la
/// clé/IV à `AttachmentEncryptor`, donc on retire des tirages jusqu'à couvrir
/// les deux alphabets (voir la note de provenance dans le document T2a).
fn generate_vector(len: usize) -> (Vec<u8>, Value) {
    let plain = plaintext(len);
    for _ in 0..4_096 {
        let (ciphertext, info) = seal(&plain);
        if has_url_safe_symbol(key_text(&info))
            && has_standard_symbol(iv_text(&info))
            && has_standard_symbol(hash_text(&info))
        {
            return (ciphertext, info);
        }
    }
    panic!("aucun tirage officiel ne couvre les deux alphabets après 4096 tentatives");
}

fn set_text(base: &Value, pointer: &str, value: &str) -> Value {
    with_value(base, pointer, Value::String(value.to_owned()))
}

fn with_string(base: &Value, pointer: &str, transform: impl FnOnce(&str) -> String) -> Value {
    let mut copy = base.clone();
    let current = field(base, pointer).to_owned();
    *copy
        .pointer_mut(pointer)
        .unwrap_or_else(|| panic!("chemin absent: {pointer}")) = Value::String(transform(&current));
    copy
}

fn with_value(base: &Value, pointer: &str, value: Value) -> Value {
    let mut copy = base.clone();
    *copy
        .pointer_mut(pointer)
        .unwrap_or_else(|| panic!("chemin absent: {pointer}")) = value;
    copy
}

/// Remplace le premier caractère de `from` par `to` : sert à casser l'alphabet.
fn swap_first_symbol(value: &str, from: &str, to: char) -> String {
    let index = value
        .find(|symbol: char| from.contains(symbol))
        .unwrap_or_else(|| panic!("aucun caractère de « {from} » dans l'échantillon"));
    let mut symbols: Vec<char> = value.chars().collect();
    symbols[index] = to;
    symbols.into_iter().collect()
}

/// Remplissage : le nombre de `=` toléré dépend de la longueur du dernier
/// groupe de 4 (voir `padding_matrix`). Deux `=` est le maximum canonique.
fn padded(value: &str) -> String {
    let mut padded = value.to_owned();
    while padded.len() % 4 != 0 {
        padded.push('=');
    }
    padded
}

/// Borne d'encodage communiquée au décodeur Swift : longueur base64 maximale
/// pour `count` octets, remplissage compris. `((count * 4) + 2) / 3` est
/// l'arrondi supérieur de `count * 8 / 6`, plus deux `=` au plus.
fn encoded_length_limit(count: usize) -> usize {
    count
        .checked_mul(4)
        .and_then(|value| value.checked_add(2))
        .map(|value| value / 3 + 2)
        .expect("borne calculable pour des tailles de média bornées")
}

fn rejection(
    reference_size: usize,
    id: &str,
    reason: &str,
    refused_at: &str,
    ciphertext: &str,
    info: Value,
) -> Value {
    json!({
        "id": id,
        "reason": reason,
        "refusedAt": refused_at,
        "byteSize": reference_size,
        "ciphertext": ciphertext,
        "info": info,
    })
}

/// Objets que le module officiel refuse : le test l'affirme, la fixture ne fait
/// que les nommer. `refusedAt` distingue un refus de lecture de l'info (encodage,
/// longueur, en-tête JWK) d'un refus à la création du déchiffreur (version, hash
/// absent), pour que le test Swift sache quel mécanisme il doit reproduire.
fn rejections(ciphertext: &[u8], base: &Value) -> Vec<Value> {
    let encoded = encode_standard(ciphertext);
    let reference_size = ciphertext.len();
    let mut cases = Vec::new();

    cases.push(rejection(
        reference_size,
        "version-v1",
        "version",
        "decryptor",
        &encoded,
        with_value(base, "/v", json!("v1")),
    ));
    cases.push(rejection(
        reference_size,
        "kty-rsa",
        "kty",
        "deserialize",
        &encoded,
        with_value(base, "/key/kty", json!("RSA")),
    ));
    cases.push(rejection(
        reference_size,
        "alg-a256gcm",
        "alg",
        "deserialize",
        &encoded,
        with_value(base, "/key/alg", json!("A256GCM")),
    ));
    cases.push(rejection(
        reference_size,
        "ext-false",
        "ext",
        "deserialize",
        &encoded,
        with_value(base, "/key/ext", json!(false)),
    ));
    cases.push(rejection(
        reference_size,
        "key-ops-without-encrypt",
        "key_ops",
        "deserialize",
        &encoded,
        with_value(base, "/key/key_ops", json!(["decrypt"])),
    ));
    cases.push(rejection(
        reference_size,
        "key-ops-without-decrypt",
        "key_ops",
        "deserialize",
        &encoded,
        with_value(base, "/key/key_ops", json!(["encrypt"])),
    ));
    cases.push(rejection(
        reference_size,
        "key-standard-alphabet",
        "alphabet",
        "deserialize",
        &encoded,
        with_string(base, "/key/k", |value| swap_first_symbol(value, "-_", '+')),
    ));
    cases.push(rejection(
        reference_size,
        "iv-url-safe-alphabet",
        "alphabet",
        "deserialize",
        &encoded,
        with_string(base, "/iv", |value| swap_first_symbol(value, "+/", '-')),
    ));
    cases.push(rejection(
        reference_size,
        "hash-url-safe-alphabet",
        "alphabet",
        "deserialize",
        &encoded,
        with_string(base, "/hashes/sha256", |value| {
            swap_first_symbol(value, "+/", '_')
        }),
    ));
    cases.push(rejection(
        reference_size,
        "key-length-31",
        "length",
        "deserialize",
        &encoded,
        with_value(base, "/key/k", json!(encode_url_safe(&[7; 31]))),
    ));
    cases.push(rejection(
        reference_size,
        "key-length-33",
        "length",
        "deserialize",
        &encoded,
        with_value(base, "/key/k", json!(encode_url_safe(&[7; 33]))),
    ));
    cases.push(rejection(
        reference_size,
        "iv-length-15",
        "length",
        "deserialize",
        &encoded,
        with_value(base, "/iv", json!(encode_standard(&[0; 15]))),
    ));
    cases.push(rejection(
        reference_size,
        "iv-length-17",
        "length",
        "deserialize",
        &encoded,
        with_value(base, "/iv", json!(encode_standard(&[0; 17]))),
    ));
    cases.push(rejection(
        reference_size,
        "hash-length-31",
        "length",
        "deserialize",
        &encoded,
        with_value(base, "/hashes/sha256", json!(encode_standard(&[0; 31]))),
    ));
    cases.push(rejection(
        reference_size,
        "padding-too-long",
        "padding",
        "deserialize",
        &encoded,
        with_string(base, "/key/k", |value| format!("{}=", padded(value))),
    ));
    cases.push(rejection(
        reference_size,
        "whitespace-trailing",
        "alphabet",
        "deserialize",
        &encoded,
        with_string(base, "/key/k", |value| format!("{value}\n")),
    ));
    cases.push(rejection(
        reference_size,
        "hashes-absent",
        "hashes",
        "deserialize",
        &encoded,
        {
            let mut copy = base.clone();
            copy.as_object_mut().expect("objet info").remove("hashes");
            copy
        },
    ));
    cases.push(rejection(
        reference_size,
        "hash-sha512-only",
        "hashes",
        "decryptor",
        &encoded,
        with_value(
            base,
            "/hashes",
            json!({ "sha512": encode_standard(&[0; 32]) }),
        ),
    ));

    cases
}

/// Le remplissage est toléré en lecture (bibliothèque : `DecodePaddingMode::Indifferent`),
/// jamais réémis. Deux cas : canonique complet, et **partiel** — un seul `=`
/// sur un groupe de 22 caractères qui en tolère deux.
fn padding_cases(ciphertext: &[u8], base: &Value) -> Vec<Value> {
    let encoded = encode_standard(ciphertext);
    let key = key_text(base);
    let iv = iv_text(base);

    let canonical = with_value(
        &with_value(
            &set_text(base, "/key/k", &padded(key)),
            "/iv",
            Value::String(padded(iv)),
        ),
        "/hashes/sha256",
        Value::String(padded(hash_text(base))),
    );
    let partial = with_value(
        &set_text(base, "/key/k", &format!("{key}=")),
        "/iv",
        Value::String(format!("{iv}=")),
    );

    vec![
        json!({
            "id": "padded-key-iv-hash-accepted",
            "byteSize": ciphertext.len(),
            "ciphertext": encoded,
            "paddedInfo": canonical,
            "canonicalInfo": base,
        }),
        json!({
            "id": "partially-padded-iv-accepted",
            "byteSize": ciphertext.len(),
            "ciphertext": encoded,
            "paddedInfo": partial,
            "canonicalInfo": base,
        }),
    ]
}

/// Verdicts du module officiel sur le remplissage et les caractères refusés.
/// Les chaînes sont en base64 pur (ASCII), donc les découpes par octet sont sûres.
fn padding_matrix(base: &Value) -> Vec<Value> {
    let iv = iv_text(base).to_owned();
    let key = key_text(base).to_owned();
    let mut cases = Vec::new();

    let iv_cases = [
        ("iv-none", iv.clone()),
        ("iv-one-pad", format!("{iv}=")),
        ("iv-two-pads", format!("{iv}==")),
        ("iv-three-pads", format!("{iv}===")),
        ("iv-four-pads", format!("{}====", &iv[..18])),
        ("iv-pad-in-place-of-last-symbol", format!("{}=", &iv[..21])),
        ("iv-pad-in-middle", format!("{}={}", &iv[..10], &iv[11..])),
        ("iv-pad-then-symbol", format!("{iv}=A")),
        ("iv-whitespace", format!("{iv}\n")),
        ("iv-non-ascii", format!("{}é", &iv[..21])),
    ];
    for (id, encoded) in iv_cases {
        cases.push(matrix_case(id, "standard", 16, &encoded));
    }

    let key_cases = [
        ("key-none", key.clone()),
        ("key-one-pad", format!("{key}=")),
        ("key-two-pads", format!("{key}==")),
        (
            "key-pad-in-middle",
            format!("{}={}", &key[..10], &key[11..]),
        ),
    ];
    for (id, encoded) in key_cases {
        cases.push(matrix_case(id, "urlSafe", 32, &encoded));
    }

    cases
}

/// Interroge la bibliothèque exactement comme le fait le désérialiseur de `ruma`
/// (`Base64<Alphabet, [u8; N]>::parse`) et enregistre son verdict.
fn matrix_case(id: &str, alphabet: &str, count: usize, encoded: &str) -> Value {
    let decoded: Result<Vec<u8>, String> = match (alphabet, count) {
        ("urlSafe", 32) => Base64::<UrlSafe, [u8; 32]>::parse(encoded)
            .map(|value| value.into_inner().to_vec())
            .map_err(|error| error.to_string()),
        ("standard", 16) => Base64::<Standard, [u8; 16]>::parse(encoded)
            .map(|value| value.into_inner().to_vec())
            .map_err(|error| error.to_string()),
        _ => panic!("cas de matrice non couvert: {alphabet}/{count}"),
    };

    match decoded {
        Ok(bytes) => json!({
            "id": id,
            "alphabet": alphabet,
            "count": count,
            "encoded": encoded,
            "accepted": true,
            "decodedLength": bytes.len(),
            "decodedBase64Standard": encode_standard(&bytes),
        }),
        Err(reason) => json!({
            "id": id,
            "alphabet": alphabet,
            "count": count,
            "encoded": encoded,
            "accepted": false,
            "reason": reason,
        }),
    }
}

/// Borne d'encodage publiée pour que le décodeur Swift refuse une entrée
/// surdimensionnée avant toute copie.
fn encoding_limits() -> Value {
    let per_size: Vec<Value> = STORED_SIZES
        .iter()
        .map(|&size| {
            json!({
                "byteSize": size,
                "encodedLengthLimit": encoded_length_limit(size),
            })
        })
        .collect();

    json!({
        "maximumByteSize": MAX_MEDIA_BYTES,
        "encodedLengthLimitRule": "(count * 4 + 2) / 3 + 2 en division entière, contrôle avant allocation",
        "perSize": per_size,
    })
}

/// Vecteur publié par le module amont (identifiants `EXAMPLE_DATA` /
/// `example_key_json`). Il existe à l'identique en 0.17.0 (FFI liée dans l'app)
/// et en 0.19.1 (prototype) : c'est la preuve de continuité du format.
fn upstream_ciphertext() -> Vec<u8> {
    vec![
        179, 154, 118, 127, 186, 127, 110, 33, 203, 33, 33, 134, 67, 100, 173, 46, 235, 27, 215,
        172, 36, 26, 75, 47, 33, 160,
    ]
}

fn upstream_info() -> Value {
    json!({
        "v": "v2",
        "key": {
            "kty": "oct",
            "alg": "A256CTR",
            "ext": true,
            "k": "Voq2nkPme_x8no5-Tjq_laDAdxE6iDbxnlQXxwFPgE4",
            "key_ops": ["decrypt", "encrypt"]
        },
        "iv": "i0DovxYdJEcAAAAAAAAAAA",
        "hashes": {
            "sha256": "ANdt819a8bZl4jKy3Z+jcqtiNICa2y0AW4BBJ/iQRAU"
        }
    })
}

fn build_fixture() -> Value {
    let mut stored: Vec<(usize, Vec<u8>, Value)> = Vec::new();
    for len in STORED_SIZES {
        let (ciphertext, info) = generate_vector(len);
        stored.push((len, ciphertext, info));
    }

    let vectors: Vec<Value> = stored
        .iter()
        .map(|(len, ciphertext, info)| {
            json!({
                "id": format!("size-{len}"),
                "byteSize": len,
                "ciphertext": encode_standard(ciphertext),
                "info": info,
            })
        })
        .collect();

    let (_, reference_ciphertext, reference_info) = stored
        .iter()
        .find(|(len, _, _)| *len == 17)
        .expect("le vecteur de référence fait 17 octets");

    json!({
        "format": "matrix-encrypted-attachment-v2",
        "contract": "docs/implementation/medias-exploitation-contrat-20261104.md#431-norme-et-encodages",
        "oracle": "matrix-sdk-crypto 0.19.1 (AttachmentEncryptor/AttachmentDecryptor/MediaEncryptionInfo)",
        "generatedBy": "prototypes/messaging-crypto/tests/media_vectors.rs",
        "plaintextRule": "byte(i) = u8(7 + 31*i + (i >> 8)) pour i de 0 à n-1",
        "encodingNote": "k en base64url, iv et hashes.sha256 en base64 standard, tous sans remplissage (§4.3.1).",
        "upstreamVector": {
            "source": "matrix-sdk-crypto 0.17.0 et 0.19.1, src/file_encryption/attachments.rs, tests::EXAMPLE_DATA et example_key_json",
            "plaintext": "It's a secret to everybody",
            "ciphertext": upstream_ciphertext(),
            "info": upstream_info(),
        },
        "vectors": vectors,
        "rejections": rejections(reference_ciphertext, reference_info),
        "padding": padding_cases(reference_ciphertext, reference_info),
        "paddingMatrix": padding_matrix(reference_info),
        "limits": encoding_limits(),
    })
}

fn read_fixture() -> Value {
    let text = fs::read_to_string(FIXTURE_PATH).unwrap_or_else(|error| {
        panic!(
            "fixture absente ou illisible ({FIXTURE_PATH}): {error}. \
             Régénérer avec DRIVY_MEDIA_VECTORS_WRITE=1."
        )
    });
    serde_json::from_str(&text).expect("fixture JSON valide")
}

#[test]
fn regenerate_when_requested() {
    let Some(enabled) = env::var_os("DRIVY_MEDIA_VECTORS_WRITE") else {
        return;
    };
    // Activation explicite seulement : ni « 0 », ni « false », ni une valeur vide
    // ne doivent réécrire la fixture pendant une simple campagne de validation.
    if enabled != OsStr::new("1") {
        return;
    }
    let fixture = build_fixture();
    let mut text = serde_json::to_string_pretty(&fixture).expect("fixture sérialisable");
    text.push('\n');
    let path = Path::new(FIXTURE_PATH);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("répertoire de fixture");
    }
    // Écriture atomique : aucun test concurrent ne lit un fichier à moitié écrit.
    let temporary = path.with_extension("json.tmp");
    fs::write(&temporary, text).expect("écriture du fichier temporaire");
    fs::rename(&temporary, path).expect("remplacement de la fixture");
}

#[test]
fn committed_fixture_covers_the_required_sizes_and_alphabets() {
    let fixture = read_fixture();
    assert_eq!(fixture["format"], "matrix-encrypted-attachment-v2");

    let vectors = fixture["vectors"].as_array().expect("tableau vectors");
    let sizes: Vec<usize> = vectors
        .iter()
        .map(|vector| vector["byteSize"].as_u64().expect("byteSize entier") as usize)
        .collect();
    assert_eq!(sizes, STORED_SIZES);

    for vector in vectors {
        let id = vector["id"].as_str().expect("id");
        let len = vector["byteSize"].as_u64().expect("byteSize") as usize;
        let encoded = vector["ciphertext"].as_str().expect("ciphertext base64");
        assert!(
            !encoded.contains('='),
            "{id}: le ciphertext de la fixture ne porte aucun remplissage"
        );
        assert_eq!(
            decode_standard(encoded).len(),
            len,
            "{id}: taille du chiffré = taille du clair (CTR sans remplissage)"
        );
        let info = &vector["info"];
        assert!(
            has_url_safe_symbol(key_text(info)),
            "{id}: k couvre l'alphabet base64url"
        );
        assert!(
            has_standard_symbol(iv_text(info)),
            "{id}: iv couvre l'alphabet base64 standard"
        );
        assert!(
            has_standard_symbol(hash_text(info)),
            "{id}: sha256 couvre l'alphabet base64 standard"
        );
    }
}

#[test]
fn committed_vectors_open_with_the_official_module() {
    let fixture = read_fixture();
    for vector in fixture["vectors"].as_array().expect("tableau vectors") {
        let id = vector["id"].as_str().expect("id");
        let len = vector["byteSize"].as_u64().expect("byteSize") as usize;
        let ciphertext = decode_standard(vector["ciphertext"].as_str().expect("ciphertext"));
        let opened = open(&ciphertext, &vector["info"]).unwrap_or_else(|error| {
            panic!("{id}: le module officiel refuse son propre vecteur: {error}")
        });
        assert_eq!(opened, plaintext(len), "{id}: clair retrouvé");
        assert_eq!(
            opened.len(),
            ciphertext.len(),
            "{id}: CTR ne change pas la taille"
        );
    }
}

#[test]
fn committed_infos_are_canonical_for_the_official_module() {
    let fixture = read_fixture();
    for vector in fixture["vectors"].as_array().expect("tableau vectors") {
        let id = vector["id"].as_str().expect("id");
        let info = &vector["info"];
        let parsed: MediaEncryptionInfo =
            serde_json::from_value(info.clone()).expect("info acceptée par le module officiel");
        let reencoded = serde_json::to_value(&parsed).expect("réencodage");
        assert_eq!(&reencoded, info, "{id}: relecture/réécriture identique");
        assert_eq!(
            info["key"]["key_ops"],
            json!(["decrypt", "encrypt"]),
            "{id}: ordre et contenu de key_ops canoniques"
        );
        assert_eq!(info["v"], "v2", "{id}: version v2");
        assert_eq!(info["key"]["kty"], "oct", "{id}: kty");
        assert_eq!(info["key"]["alg"], "A256CTR", "{id}: alg");
        assert_eq!(info["key"]["ext"], true, "{id}: ext");
    }
}

#[test]
fn invalid_infos_are_refused_by_the_official_module() {
    let fixture = read_fixture();
    let cases = fixture["rejections"]
        .as_array()
        .expect("tableau rejections");
    assert!(cases.len() >= 15, "couverture des refus");
    for case in cases {
        let id = case["id"].as_str().expect("id");
        let ciphertext = decode_standard(case["ciphertext"].as_str().expect("ciphertext"));
        assert!(
            open(&ciphertext, &case["info"]).is_err(),
            "{id}: aucun clair ne doit être produit"
        );

        let parsed: Result<MediaEncryptionInfo, _> = serde_json::from_value(case["info"].clone());
        match case["refusedAt"].as_str() {
            Some("deserialize") => assert!(
                parsed.is_err(),
                "{id}: l'info est refusée à la lecture (encodage, longueur, en-tête)"
            ),
            Some("decryptor") => {
                let info = parsed.unwrap_or_else(|error| {
                    panic!("{id}: l'info devait rester lisible par le module: {error}")
                });
                let mut reader = Cursor::new(ciphertext.clone());
                assert!(
                    AttachmentDecryptor::new(&mut reader, info).is_err(),
                    "{id}: le déchiffreur refuse l'info"
                );
            }
            other => panic!("{id}: refusedAt inconnu ({other:?})"),
        }
    }
}

#[test]
fn padded_inputs_are_tolerated_and_reemitted_canonically() {
    let fixture = read_fixture();
    for case in fixture["padding"].as_array().expect("tableau padding") {
        let id = case["id"].as_str().expect("id");
        let ciphertext = decode_standard(case["ciphertext"].as_str().expect("ciphertext"));
        let opened = open(&ciphertext, &case["paddedInfo"])
            .unwrap_or_else(|error| panic!("{id}: remplissage refusé en lecture: {error}"));
        assert_eq!(
            opened,
            plaintext(17),
            "{id}: clair retrouvé malgré le remplissage"
        );

        let parsed: MediaEncryptionInfo = serde_json::from_value(case["paddedInfo"].clone())
            .expect("info remplie acceptée en lecture");
        let reencoded = serde_json::to_value(&parsed).expect("réencodage");
        assert_eq!(
            reencoded, case["canonicalInfo"],
            "{id}: la réécriture ne porte aucun remplissage"
        );
        for pointer in ["/key/k", "/iv", "/hashes/sha256"] {
            let text = reencoded
                .pointer(pointer)
                .and_then(Value::as_str)
                .expect("champ texte réencodé");
            assert!(
                !text.contains('='),
                "{id}: {pointer} réémis sans remplissage"
            );
        }
    }
}

#[test]
fn upstream_0_17_0_vector_still_opens() {
    let fixture = read_fixture();
    let upstream = &fixture["upstreamVector"];
    assert_eq!(
        upstream["info"],
        upstream_info(),
        "le vecteur amont est reproduit tel quel (source 0.17.0/0.19.1)"
    );
    assert_eq!(
        upstream["ciphertext"],
        json!(upstream_ciphertext()),
        "octets du vecteur amont"
    );

    let ciphertext: Vec<u8> = upstream["ciphertext"]
        .as_array()
        .expect("tableau d'octets")
        .iter()
        .map(|byte| byte.as_u64().expect("octet") as u8)
        .collect();
    let opened =
        open(&ciphertext, &upstream["info"]).expect("le module officiel ouvre le vecteur amont");
    assert_eq!(
        String::from_utf8(opened).expect("clair UTF-8"),
        upstream["plaintext"].as_str().expect("plaintext")
    );
}

#[test]
fn large_sizes_are_exercised_with_the_official_oracle() {
    for len in [65_536, MAX_MEDIA_BYTES] {
        let plain = plaintext(len);
        let (ciphertext, info) = seal(&plain);
        assert_eq!(ciphertext.len(), len, "{len}: taille du chiffré");
        let opened = open(&ciphertext, &info).expect("le module officiel relit son chiffré");
        assert_eq!(opened, plain, "{len}: clair identique");
    }
}

#[test]
fn padding_matrix_matches_the_library() {
    let fixture = read_fixture();
    let cases = fixture["paddingMatrix"]
        .as_array()
        .expect("tableau paddingMatrix");
    assert!(cases.len() >= 12, "couverture de la matrice de remplissage");
    for case in cases {
        let id = case["id"].as_str().expect("id");
        let alphabet = case["alphabet"].as_str().expect("alphabet");
        let count = case["count"].as_u64().expect("count") as usize;
        let encoded = case["encoded"].as_str().expect("encoded");
        let parsed: Result<Vec<u8>, String> = match (alphabet, count) {
            ("urlSafe", 32) => Base64::<UrlSafe, [u8; 32]>::parse(encoded)
                .map(|value| value.into_inner().to_vec())
                .map_err(|error| error.to_string()),
            ("standard", 16) => Base64::<Standard, [u8; 16]>::parse(encoded)
                .map(|value| value.into_inner().to_vec())
                .map_err(|error| error.to_string()),
            _ => panic!("{id}: cas non couvert"),
        };
        assert_eq!(
            parsed.is_ok(),
            case["accepted"].as_bool().expect("accepted"),
            "{id}: verdict du module officiel"
        );
        if let Ok(bytes) = parsed {
            assert_eq!(
                Some(bytes.len()),
                case["decodedLength"].as_u64().map(|value| value as usize),
                "{id}: longueur décodée"
            );
            assert_eq!(
                encode_standard(&bytes),
                case["decodedBase64Standard"]
                    .as_str()
                    .expect("decodedBase64Standard"),
                "{id}: octets décodés"
            );
        }
    }
}

#[test]
fn partial_padding_is_accepted_and_longer_padding_refused() {
    let fixture = read_fixture();
    let cases = fixture["paddingMatrix"]
        .as_array()
        .expect("tableau paddingMatrix");
    let verdict = |id: &str| -> bool {
        cases
            .iter()
            .find(|case| case["id"] == id)
            .unwrap_or_else(|| panic!("cas absent: {id}"))["accepted"]
            .as_bool()
            .expect("accepted")
    };
    for accepted in [
        "iv-none",
        "iv-one-pad",
        "iv-two-pads",
        "key-none",
        "key-one-pad",
    ] {
        assert!(verdict(accepted), "{accepted}: accepté par la bibliothèque");
    }
    for refused in [
        "iv-three-pads",
        "iv-four-pads",
        "iv-pad-in-place-of-last-symbol",
        "iv-pad-in-middle",
        "iv-pad-then-symbol",
        "iv-whitespace",
        "iv-non-ascii",
        "key-two-pads",
        "key-pad-in-middle",
    ] {
        assert!(!verdict(refused), "{refused}: refusé par la bibliothèque");
    }
}

#[test]
fn encoded_length_limit_covers_every_stored_vector() {
    let fixture = read_fixture();
    let limits = &fixture["limits"];
    assert_eq!(limits["maximumByteSize"], MAX_MEDIA_BYTES);
    let per_size = limits["perSize"].as_array().expect("tableau perSize");
    assert_eq!(per_size.len(), STORED_SIZES.len());
    let vectors = fixture["vectors"].as_array().expect("tableau vectors");

    for entry in per_size {
        let size = entry["byteSize"].as_u64().expect("byteSize") as usize;
        let limit = entry["encodedLengthLimit"]
            .as_u64()
            .expect("encodedLengthLimit") as usize;
        assert_eq!(
            limit,
            encoded_length_limit(size),
            "{size}: formule identique"
        );
        let vector = vectors
            .iter()
            .find(|vector| vector["byteSize"].as_u64() == Some(size as u64))
            .expect("vecteur de la taille");
        let encoded = vector["ciphertext"].as_str().expect("ciphertext");
        assert!(
            encoded.len() <= limit,
            "{size}: l'encodage réel tient dans la borne"
        );
        assert!(
            encoded.len() + 2 <= limit,
            "{size}: deux « = » tiendraient aussi"
        );
    }
}
