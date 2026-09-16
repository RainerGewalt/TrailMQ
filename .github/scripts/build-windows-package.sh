#!/usr/bin/env bash
# TrailMQ — build the Windows launcher payload and portable archive.
#
# Produces the tree the installer packages and the ZIP a user can unpack
# without installing anything:
#
#   TrailMQ-<version>-windows-x64/
#     trailmq.exe          the launcher
#     release.yaml         the release contract it reads its version from
#     recipes/             read-only runtime assets
#     scenarios/           the demo scenario pack
#     START-HERE.md        the only orientation a downloader gets
#
# The payload deliberately carries no marker file. An extracted archive is a
# portable copy: everything lives in the folder the user chose, and deleting
# that folder removes TrailMQ. The installer writes the marker itself, which is
# what moves the user's data out of Program Files.
#
# Usage:
#   .github/scripts/build-windows-package.sh [output-dir]
#
# Requires: bash, go, zip (or PowerShell's Compress-Archive on Windows CI).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}" || exit 2

OUT_DIR="${1:-${REPO_ROOT}/dist}"
CONTRACT="scripts/release-contract.sh"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required tool missing: %s\n' "$1" >&2
    exit 2
  }
}
need go

VERSION="$("${CONTRACT}" get version)" || {
  printf 'Could not read the release version from release.yaml\n' >&2
  exit 1
}

NAME="TrailMQ-${VERSION}-windows-x64"
STAGE="${OUT_DIR}/${NAME}"

mkdir -p "${STAGE}"
rm -rf "${STAGE:?}"/*

printf 'Building %s\n' "${NAME}"

# ---------------------------------------------------------------------------
# The launcher
#
# -trimpath keeps build-machine paths out of the binary, and the version is not
# stamped in: the launcher reads release.yaml, so a binary and a contract that
# disagree is a state that cannot arise.
# ---------------------------------------------------------------------------
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags="-s -w" \
  -o "${STAGE}/trailmq.exe" ./cmd/trailmq || exit 1
printf '  trailmq.exe\n'

# ---------------------------------------------------------------------------
# Product assets
#
# Only what the runtime needs. No scripts, no shell launcher, no development
# paths: on Windows those would be unusable anyway, and shipping them would
# suggest the evaluation needs a POSIX environment it does not need.
# ---------------------------------------------------------------------------
cp release.yaml "${STAGE}/"

mkdir -p "${STAGE}/recipes/secure-mqtt-core"
for asset in docker-compose.yaml config.yaml nginx.conf recipe.yaml README.md; do
  cp "recipes/secure-mqtt-core/${asset}" "${STAGE}/recipes/secure-mqtt-core/" 2>/dev/null || true
done
printf '  recipes/\n'

mkdir -p "${STAGE}/scenarios"
cp scenarios/*.json "${STAGE}/scenarios/" 2>/dev/null || true
printf '  scenarios/\n'

cat >"${STAGE}/START-HERE.md" <<EOF
# TrailMQ ${VERSION} for Windows

An MQTT broker that decides whether an action is allowed, enforces that
decision, and keeps a reviewable record of it.

## What you need

**Docker Desktop.** Nothing else — no Git, no WSL, no OpenSSL, no MQTT client.

Internet access is needed once, for the first image pull of about 1 GB.

## Start it

Open a terminal in this folder and run:

    trailmq.exe quickstart

That checks Docker, generates local certificates and credentials, starts
TrailMQ and waits for it to be ready.

Then:

    trailmq.exe demo unauthorized-machine-command
    trailmq.exe open

The first shows what TrailMQ does with a machine command that is not
permitted. The second opens the web interface, where the same refusal is
listed under Activity.

## Everything else

    trailmq.exe doctor        check this machine
    trailmq.exe verify        the decision proof, as PASS/FAIL
    trailmq.exe credentials   the generated evaluation logins
    trailmq.exe status        what is running
    trailmq.exe stop          stop it, keeping your data
    trailmq.exe help          the full command list

## Removing it

Run \`trailmq.exe stop\`, then delete this folder. Everything TrailMQ
generated lives inside it. The downloaded container images are removed with
\`docker image rm\`.

## Scope

This is a local, non-production evaluation. Production and commercial
deployment require the corresponding agreement.

Documentation: https://github.com/RainerGewalt/TrailMQ
Contact: contact@trailmq.com
EOF
printf '  START-HERE.md\n'

# ---------------------------------------------------------------------------
# Portable archive
# ---------------------------------------------------------------------------
ARCHIVE="${OUT_DIR}/${NAME}.zip"
rm -f "${ARCHIVE}"

if command -v zip >/dev/null 2>&1; then
  (cd "${OUT_DIR}" && zip -qr "${NAME}.zip" "${NAME}")
elif command -v powershell.exe >/dev/null 2>&1; then
  # Windows runners have no zip, but they do have Compress-Archive.
  powershell.exe -NoProfile -Command \
    "Compress-Archive -Path '${STAGE}\\*' -DestinationPath '${ARCHIVE}' -Force" || exit 1
else
  printf 'Neither zip nor PowerShell is available to create the archive\n' >&2
  exit 1
fi
printf '  %s\n' "${NAME}.zip"

printf '\nPayload staged at %s\n' "${STAGE}"
