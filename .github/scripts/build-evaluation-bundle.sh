#!/usr/bin/env bash
# TrailMQ — build the downloadable evaluation bundles.
#
# Produces the assets a GitHub Release offers to someone who should not have to
# clone anything: an archive that contains the public distribution exactly as
# this commit defines it, plus a checksum file.
#
# Nothing built here is ever committed. The bundle content comes from
# `git archive`, so it is precisely the tracked tree at the given revision —
# no runtime data, no generated certificates, no local .env, no editor state.
# That property is the reason for using git archive rather than copying the
# working directory, which would silently pick up whatever a developer had
# lying around.
#
# Usage:
#   .github/scripts/build-evaluation-bundle.sh [revision] [output-dir]
#
# Defaults: revision HEAD, output dir dist/ (gitignored).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"

REVISION="${1:-HEAD}"
OUT_DIR="${2:-${REPO_ROOT}/dist}"

# Paths that exist for people who develop TrailMQ, not for people who evaluate
# it. Shipping them makes the bundle look like a repository, which is the exact
# impression this asset exists to avoid.
DEV_ONLY=(
  .github
  CONTRIBUTING.md
  .gitignore
)

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required tool missing: %s\n' "$1" >&2
    exit 2
  }
}
need git
need tar

# The published Compose default is the single source of truth for the version,
# the same one the distribution gate reads. Deriving it here keeps a bundle from
# ever being named after a release it does not actually contain.
compose_file="recipes/secure-mqtt-core/docker-compose.yaml"
VERSION="$(sed -nE 's/.*rainergewalt\/trailmq-backend:([0-9][A-Za-z0-9._-]*)\}.*/\1/p' \
  "${compose_file}" | head -n1)"
if [ -z "${VERSION}" ]; then
  printf 'Could not derive the release version from %s\n' "${compose_file}" >&2
  exit 1
fi

NAME="TrailMQ-Evaluation-${VERSION}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

mkdir -p "${OUT_DIR}"
rm -f "${OUT_DIR}/${NAME}."* "${OUT_DIR}/SHA256SUMS"

printf 'Building %s from %s\n' "${NAME}" "${REVISION}"

mkdir -p "${STAGE}/${NAME}"
git archive --format=tar "${REVISION}" | tar -x -C "${STAGE}/${NAME}"

for path in "${DEV_ONLY[@]}"; do
  rm -rf "${STAGE:?}/${NAME}/${path}"
done

# ---------------------------------------------------------------------------
# The one file that only exists in the bundle.
#
# Someone who downloaded a zip has not read the repository README and has no
# reason to. This is the whole orientation they get, so it states the
# requirement honestly — this bundle runs TrailMQ in Docker — and then gets out
# of the way.
# ---------------------------------------------------------------------------
cat >"${STAGE}/${NAME}/START-HERE.md" <<EOF
# TrailMQ ${VERSION} — evaluation bundle

An MQTT broker that decides whether an action is allowed, enforces that
decision, and keeps a reviewable record of it.

## What you need

- **Docker** 20.10 or newer, with **Docker Compose v2**
  (\`docker compose version\` must work)
- **Bash** — present on Linux and macOS; on Windows use WSL or Git Bash
- Internet access for the first image pull (about 1 GB)

This bundle runs TrailMQ in containers. It does not install anything on your
system, register a service, or write outside this folder.

## Start it

\`\`\`bash
./trailmq try
\`\`\`

That checks prerequisites, generates local credentials and demo certificates,
starts the stack, and then makes TrailMQ decide twice — one MQTT publish that
is allowed and one that is refused — before opening the Web UI.

## Then

\`\`\`bash
./trailmq connect   # everything your own MQTT client needs, on one screen
./trailmq verify    # the same proof as a reproducible PASS/FAIL run
./trailmq reset     # back to a clean evaluation
./trailmq help      # everything else
\`\`\`

## Remove it

\`\`\`bash
./trailmq purge     # stop containers and delete everything generated here
\`\`\`

Then delete this folder. Nothing remains outside it except the downloaded
container images, which \`docker image rm\` removes.

## Prefer to be shown?

A 20-minute technical walkthrough, no sales deck — write to
**contact@trailmq.com** with your broker, your use case, and the one thing you
want to understand.

Full documentation: \`README.md\` and \`docs/\`.
EOF

# ---------------------------------------------------------------------------
# Archives
#
# Two formats of identical content, because the platforms differ in what they
# can open without extra tooling, not in what they need to run. tar.gz keeps the
# executable bits that the launcher depends on; zip does not carry them
# reliably, which is called out in the release notes rather than papered over.
# ---------------------------------------------------------------------------
tar -czf "${OUT_DIR}/${NAME}.tar.gz" -C "${STAGE}" "${NAME}"
printf '  %s\n' "${NAME}.tar.gz"

if command -v zip >/dev/null 2>&1; then
  (cd "${STAGE}" && zip -qr "${OUT_DIR}/${NAME}.zip" "${NAME}")
  printf '  %s\n' "${NAME}.zip"
else
  printf 'zip not installed — skipping %s.zip\n' "${NAME}" >&2
fi

(
  cd "${OUT_DIR}"
  # Checksums over the assets as published, so a user can verify the exact file
  # they downloaded without trusting the page it came from.
  sha256sum "${NAME}".* >SHA256SUMS
)
printf '  SHA256SUMS\n'

printf '\nBundle contents:\n'
tar -tzf "${OUT_DIR}/${NAME}.tar.gz" | sed -E "s|^${NAME}/||" | awk -F/ 'NF<=2' | sort | sed 's/^/  /'
