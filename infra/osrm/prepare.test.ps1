# Test de l'orchestration PowerShell. Docker est remplace, aucun conteneur ni reseau.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
$global:OsrmDockerCalls = [System.Collections.Generic.List[object]]::new()
$global:OsrmFailPartition = $false
function global:docker {
    $call = @($args)
    $global:OsrmDockerCalls.Add($call)
    $global:LASTEXITCODE = 0
    if ($global:OsrmFailPartition -and $call -contains 'osrm-partition') {
        $global:LASTEXITCODE = 2
        return
    }
    if ($call[-1] -like 'mkdir /data/pkg*') {
        $index = [Array]::IndexOf($call, '-v')
        $mount = $call[$index + 1]
        $directory = $mount.Substring(0, $mount.Length - ':/data'.Length)
        [System.IO.File]::WriteAllText((Join-Path $directory 'osrm-ch-v26.10.0.tar'), 'synthetic archive')
    }
}
try {
    New-Item -ItemType Directory -Path $root | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'prepare.ps1') $root
    $source = Join-Path $root 'synthetic.osm.pbf'
    [System.IO.File]::WriteAllText($source, 'public synthetic test fixture')
    $lock = Get-Content -Raw (Join-Path $PSScriptRoot 'runtime-lock.json') | ConvertFrom-Json
    $lock.source.sha256 = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
    $lock | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $root 'runtime-lock.json')
    $script = Join-Path $root 'prepare.ps1'
    $destination = Join-Path $root 'output with spaces'
    & $script -PbfPath $source -OutputDirectory $destination
    if ($global:OsrmDockerCalls.Count -ne 5) { throw 'Expected pull, extract, partition, customize, package.' }
    foreach ($call in $global:OsrmDockerCalls) {
        if ($call -notcontains $lock.image) { throw 'Image digest missing.' }
        if ($call[0] -eq 'run' -and ($call -notcontains '--network' -or $call -notcontains 'none')) { throw 'Network not disabled.' }
    }
    if (!(Test-Path (Join-Path $destination 'osrm-ch-v26.10.0.tar.sha256'))) { throw 'Archive hash missing.' }
    $refused = $false
    try { & $script -PbfPath $source -OutputDirectory $destination } catch { $refused = $true }
    if (!$refused -or $global:OsrmDockerCalls.Count -ne 5) { throw 'Existing destination must be refused before Docker.' }
    $global:OsrmDockerCalls.Clear()
    $global:OsrmFailPartition = $true
    $refused = $false
    try { & $script -PbfPath $source -OutputDirectory (Join-Path $root 'failed') } catch { $refused = $true }
    if (!$refused -or $global:OsrmDockerCalls.Count -ne 3) { throw 'Partition failure must stop before customize.' }
    Write-Output 'PASS: digest, reseau coupe, chemin avec espaces, archive SHA256, refus ecrasement, arret sur erreur.'
} finally {
    Remove-Item Function:\docker
    Remove-Variable OsrmDockerCalls, OsrmFailPartition -Scope Global
    # Seulement le repertoire temporaire cree par ce test.
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
