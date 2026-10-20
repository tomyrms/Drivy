# Preparation locale uniquement. Aucune commande SSH, pct, systemctl ou modification homelab.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PbfPath,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$VerifyOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$lockPath = Join-Path $PSScriptRoot 'runtime-lock.json'
$lock = Get-Content -Raw $lockPath | ConvertFrom-Json
$source = (Resolve-Path -LiteralPath $PbfPath).Path
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $lock.source.sha256) {
    throw 'Extrait different du SHA256 verrouille. Ne pas remplacer silencieusement la carte.'
}
if ($VerifyOnly) { Write-Output 'SHA256 de la source conforme.'; exit 0 }
$output = [System.IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'La destination doit etre nouvelle, aucun ecrasement autorise.' }

function Invoke-Docker {
    # Fonction simple : -v doit aller a Docker, pas au parametre commun Verbose.
    & docker @args
    if ($LASTEXITCODE -ne 0) { throw 'Commande Docker echouee. Le repertoire partiel reste disponible pour diagnostic.' }
}

# Le pull est le seul acces reseau de preparation. Les traitements sont tous sans reseau.
Invoke-Docker pull --platform $lock.platform $lock.image
New-Item -ItemType Directory -Path $output | Out-Null
Copy-Item -LiteralPath $source -Destination (Join-Path $output $lock.source.filename)
Copy-Item -LiteralPath $lockPath -Destination (Join-Path $output 'runtime-lock.json')
$mount = "${output}:/data"
$base = '/data/switzerland-latest.osrm'
Invoke-Docker run --rm --network none --platform $lock.platform -v $mount $lock.image osrm-extract -p $lock.profile -t $lock.threads /data/switzerland-latest.osm.pbf
Invoke-Docker run --rm --network none --platform $lock.platform -v $mount $lock.image osrm-partition -t $lock.threads $base
Invoke-Docker run --rm --network none --platform $lock.platform -v $mount $lock.image osrm-customize -t $lock.threads $base
Invoke-Docker run --rm --network none --platform $lock.platform -v $mount --entrypoint sh $lock.image -ec 'mkdir /data/pkg; cp /usr/local/bin/osrm-routed /data/pkg/; cp /data/switzerland-latest.osrm.* /data/pkg/; cp /data/runtime-lock.json /data/pkg/; osrm-routed --version > /data/pkg/OSRM_VERSION; cd /data/pkg; sha256sum osrm-routed switzerland-latest.osrm.* runtime-lock.json OSRM_VERSION > SHA256SUMS; tar -cf /data/osrm-ch-v26.10.0.tar .'
$archive = Join-Path $output 'osrm-ch-v26.10.0.tar'
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText("$archive.sha256", "$archiveHash  osrm-ch-v26.10.0.tar`n", [System.Text.UTF8Encoding]::new($false))
Write-Output 'Preparation terminee. Archive et SHA256 locaux, aucun deploiement effectue.'
