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

# What a bundle contains, and how it differs from the repository, is defined
# once in the staging script — which the distribution gate also runs, so a
# bundle defect fails a pull request instead of a release.
STAGE_BUNDLE=".github/scripts/stage-evaluation-bundle.sh"
CHECK_LINKS=".github/scripts/check-bundle-links.sh"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required tool missing: %s\n' "$1" >&2
    exit 2
  }
}
need git
need tar
need awk

# The release contract names the version, the same one the distribution gate
# reads. Taking it from there rather than from a Compose regex keeps a bundle
# from ever being named after a release it does not actually contain — and
# means a bundle cannot be built at all for a release nobody declared.
CONTRACT="scripts/release-contract.sh"
VERSION="$("${CONTRACT}" get distribution.evaluation_bundle)" || {
  printf 'Could not read distribution.evaluation_bundle from release.yaml\n' >&2
  exit 1
}
if [ "${VERSION}" = "null" ]; then
  printf 'release.yaml declares no evaluation bundle for this release\n' >&2
  exit 1
fi

# The gate already enforces this, but the builder is also run by hand. Failing
# here costs one comparison and stops a mislabelled asset from being produced
# on a machine that never ran the gate.
RELEASE_VERSION="$("${CONTRACT}" get version)"
if [ "${VERSION}" != "${RELEASE_VERSION}" ]; then
  printf 'release.yaml is inconsistent: evaluation bundle %s, release %s\n' \
    "${VERSION}" "${RELEASE_VERSION}" >&2
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

"${REPO_ROOT}/${STAGE_BUNDLE}" "${STAGE}/${NAME}" "${VERSION}" || exit 1

# A bundle whose documentation points at files it does not ship strands the
# reader on the exact path this asset exists to provide. Checking the staged
# content means a broken link cannot reach an archive at all.
if ! "${REPO_ROOT}/${CHECK_LINKS}" "${STAGE}/${NAME}"; then
  printf 'Refusing to package a bundle with unresolvable documentation links\n' >&2
  exit 1
fi

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
