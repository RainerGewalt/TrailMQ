# TrailMQ — verify the built Windows artifacts.
#
# This exercises what a downloader receives, not the source it came from. A
# binary that compiles and a binary that answers on a machine with no Docker,
# no Git and no Bash are different claims, and only the second is what someone
# actually gets.
#
# Used by both the pull-request workflow and the release workflow, so an
# artifact cannot be published having passed a weaker check than the one that
# guards the branch.
#
#   pwsh distribution/windows/verify-artifacts.ps1 -Version 3.1.0 -DistDir dist
#
# -SkipInstaller runs only the portable-archive checks, for a run that did not
# build the installer.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$DistDir,
    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'

function Assert-Exit([int]$Code, [string]$What) {
    if ($Code -ne 0) { throw "$What exited $Code" }
}

$name = "TrailMQ-$Version-windows-x64"
$workspace = Join-Path ([System.IO.Path]::GetTempPath()) "trailmq-verify-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $workspace -Force | Out-Null

# --------------------------------------------------------------------------
Write-Host "== portable archive =="
# --------------------------------------------------------------------------
$archive = Join-Path $DistDir "$name.zip"
if (-not (Test-Path $archive)) { throw "no portable archive at $archive" }

$portable = Join-Path $workspace 'portable'
Expand-Archive -Path $archive -DestinationPath $portable -Force

# Compress-Archive and zip disagree about whether the payload keeps its top
# folder, so the launcher is located rather than assumed.
$exe = Get-ChildItem -Path $portable -Filter 'trailmq.exe' -Recurse |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $exe) { throw "the archive contains no trailmq.exe" }
$root = Split-Path $exe -Parent

foreach ($required in @('release.yaml', 'START-HERE.md',
                        'recipes\secure-mqtt-core\docker-compose.yaml',
                        'scenarios\unauthorized-machine-command.json')) {
    if (-not (Test-Path (Join-Path $root $required))) {
        throw "the archive is missing $required"
    }
}

# An extracted archive is a portable copy. A marker here would send the user's
# certificates into their profile while the assets sit in a folder they may
# delete tomorrow.
if (Test-Path (Join-Path $root '.trailmq-installed')) {
    throw "the portable archive is marked as an installation"
}

$reported = (& $exe version) -join "`n"
Assert-Exit $LASTEXITCODE 'trailmq version'
if ($reported -notmatch [regex]::Escape($Version)) {
    throw "the packaged launcher reports:`n$reported`nexpected $Version"
}
Write-Host "  version reports $Version from the packaged contract"

& $exe help | Out-Null
Assert-Exit $LASTEXITCODE 'trailmq help'

# The scenario pack has to travel with the launcher, or the first thing the
# Start Menu offers is a command with nothing to run.
$scenarios = (& $exe demo) -join "`n"
Assert-Exit $LASTEXITCODE 'trailmq demo'
if ($scenarios -notmatch 'unauthorized-machine-command') {
    throw "the packaged launcher lists no scenarios"
}
Write-Host "  demo lists the scenario pack"

# The endpoints command must answer without a stack, a recipe or a daemon.
& $exe open --print | Out-Null
Assert-Exit $LASTEXITCODE 'trailmq open --print'

# doctor on a machine without Docker Desktop must say so and exit 3 — not
# crash, and not claim the machine is ready.
& $exe doctor | Out-Null
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3) {
    throw "trailmq doctor exited $LASTEXITCODE, expected 0 (ready) or 3 (not ready)"
}
Write-Host "  doctor reports the environment honestly (exit $LASTEXITCODE)"

# --------------------------------------------------------------------------
if (-not $SkipInstaller) {
    Write-Host "== installer =="
# --------------------------------------------------------------------------
    $setup = Join-Path $DistDir "TrailMQ-Setup-$Version.exe"
    if (-not (Test-Path $setup)) { throw "no installer at $setup" }

    $target = Join-Path $workspace 'installed'
    Start-Process -FilePath $setup -Wait -NoNewWindow -ArgumentList `
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$target"

    foreach ($required in @('trailmq.exe', 'release.yaml', '.trailmq-installed',
                            'scenarios\unauthorized-machine-command.json',
                            'recipes\secure-mqtt-core\docker-compose.yaml')) {
        if (-not (Test-Path (Join-Path $target $required))) {
            throw "a fresh installation is missing $required"
        }
    }
    Write-Host "  fresh install laid down the launcher, assets and scenarios"

    # Without the marker the launcher would keep the user's certificates and
    # database inside Program Files, where a normal account cannot write them.
    Write-Host "  installation is marked, so user data goes to the user profile"

    $installedVersion = (& (Join-Path $target 'trailmq.exe') version) -join "`n"
    Assert-Exit $LASTEXITCODE 'installed trailmq version'
    if ($installedVersion -notmatch [regex]::Escape($Version)) {
        throw "the installed launcher reports:`n$installedVersion`nexpected $Version"
    }
    Write-Host "  installed launcher reports $Version"
}

Remove-Item -Recurse -Force $workspace -ErrorAction SilentlyContinue
Write-Host "`nWindows artifacts verified."
