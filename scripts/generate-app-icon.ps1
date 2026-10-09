# Reproduce the « La trace » app icons from the versioned brand kit.
# The former procedural laboratory icon must never overwrite the product icon.
# iOS applies its own corner mask; these source PNGs are opaque full squares.
$ErrorActionPreference = 'Stop'
$drivyKitDirectory = Join-Path $PSScriptRoot '../docs/implementation/assets/brand-20261006/kit'
$drivyIconDirectory = Join-Path $PSScriptRoot '../apps/ios/Drivy/Resources/Assets.xcassets/AppIcon.appiconset'
$drivyIconSources = @{
    'AppIcon.png' = 'drivy-app-icon-1024.png'
    'AppIcon-dark.png' = 'drivy-app-icon-dark-1024.png'
    'AppIcon-tinted.png' = 'drivy-app-icon-tinted-1024.png'
}
foreach ($drivySource in $drivyIconSources.Values) {
    if (-not (Test-Path -LiteralPath (Join-Path $drivyKitDirectory $drivySource) -PathType Leaf)) {
        throw "Brand kit source missing: $drivySource"
    }
}
[IO.Directory]::CreateDirectory($drivyIconDirectory) | Out-Null
foreach ($drivyFilename in $drivyIconSources.Keys) {
    Copy-Item -LiteralPath (Join-Path $drivyKitDirectory $drivyIconSources[$drivyFilename]) -Destination (Join-Path $drivyIconDirectory $drivyFilename) -Force
}
$drivyIconEntries = @(
    @{ filename = 'AppIcon.png'; idiom = 'universal'; platform = 'ios'; size = '1024x1024' },
    @{ filename = 'AppIcon-dark.png'; idiom = 'universal'; platform = 'ios'; size = '1024x1024'; appearances = @(@{ appearance = 'luminosity'; value = 'dark' }) },
    @{ filename = 'AppIcon-tinted.png'; idiom = 'universal'; platform = 'ios'; size = '1024x1024'; appearances = @(@{ appearance = 'luminosity'; value = 'tinted' }) }
)
@{ images = $drivyIconEntries; info = @{ author = 'xcode'; version = 1 } } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $drivyIconDirectory 'Contents.json') -Encoding utf8
Write-Output 'La trace: default, dark and tinted AppIcon assets synchronized.'
