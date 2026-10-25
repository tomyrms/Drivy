// swift-tools-version: 5.9
// Liaisons UniFFI officielles de matrix-sdk-crypto (matrix-org/matrix-rust-sdk).
// Binaire : release matrix-sdk-crypto-ffi-0.17.0, archive MatrixSDKCryptoFFI.zip, SHA-256 épinglé ci-dessous.
// Sources Swift : copiées sans modification depuis Sources/ de la même archive (voir README.md).
import PackageDescription

let package = Package(
    name: "MatrixSDKCrypto",
    platforms: [.iOS(.v16), .macOS(.v12)],
    products: [
        .library(name: "MatrixSDKCrypto", targets: ["MatrixSDKCrypto"]),
    ],
    targets: [
        .binaryTarget(
            name: "MatrixSDKCryptoFFI",
            url: "https://github.com/matrix-org/matrix-rust-sdk/releases/download/matrix-sdk-crypto-ffi-0.17.0/MatrixSDKCryptoFFI.zip",
            checksum: "7d5e15e072eccb8cf105570bd50ebde9dece60b1bcef007139b4f265f2b0d75a"
        ),
        .target(
            name: "MatrixSDKCrypto",
            dependencies: ["MatrixSDKCryptoFFI"],
            path: "Sources/MatrixSDKCrypto"
        ),
    ],
    swiftLanguageVersions: [.v5]
)
