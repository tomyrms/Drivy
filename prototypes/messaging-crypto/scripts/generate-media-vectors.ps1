# Régénère apps/ios/DrivyTests/Fixtures/media-vectors.json avec l'oracle officiel.
#
# L'oracle est `matrix-sdk-crypto` 0.19.1, la version déjà épinglée par
# prototypes/messaging-crypto/Cargo.lock. Aucune dépendance, aucun résolveur et
# aucun lockfile ne sont modifiés : `--locked` échoue plutôt que de changer une
# version.
#
# Usage (depuis la racine du dépôt) :
#   pwsh -File prototypes/messaging-crypto/scripts/generate-media-vectors.ps1
#
# Équivalent sh/bash, sans ce script :
#   DRIVY_MEDIA_VECTORS_WRITE=1 cargo test --locked \
#     --manifest-path prototypes/messaging-crypto/Cargo.toml \
#     --test media_vectors regenerate_when_requested -- --exact

$ErrorActionPreference = "Stop"

$env:DRIVY_MEDIA_VECTORS_WRITE = "1"
try {
    cargo test --locked --manifest-path prototypes/messaging-crypto/Cargo.toml `
        --test media_vectors regenerate_when_requested -- --exact
    if ($LASTEXITCODE -ne 0) {
        throw "génération des vecteurs échouée (code $LASTEXITCODE)"
    }
}
finally {
    Remove-Item Env:DRIVY_MEDIA_VECTORS_WRITE -ErrorAction SilentlyContinue
}

Write-Host "Fixture réécrite. Vérifier : git diff apps/ios/DrivyTests/Fixtures/media-vectors.json"
Write-Host "Puis : cargo test --locked --manifest-path prototypes/messaging-crypto/Cargo.toml --test media_vectors"
