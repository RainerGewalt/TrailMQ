#!/usr/bin/env bash
# TrailMQ — negative controls for the public distribution gate.
#
# A gate that is only ever run against a healthy tree proves nothing. This script
# builds a fresh-clone copy of the repository, confirms the gate passes on it,
# then reintroduces one real regression at a time and confirms the gate rejects
# each one for the right reason.
#
# The clean copy contains only git-tracked files, so it also proves the gate
# holds on a clone where no runtime folder has been generated yet.
#
# Run it locally exactly as CI does:
#   .github/scripts/negative-controls.sh
#
# Requires: the same tools as check-distribution.sh.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}" || exit 2

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

PRISTINE="${WORK}/pristine"
RECIPE="recipes/secure-mqtt-core"
COMPOSE="${RECIPE}/docker-compose.yaml"

# Every control mutates a healthy tree, so each pattern it matches has to name
# the release this tree actually ships. Hardcoding that version meant the seds
# quietly matched nothing after a version bump: the tree stayed healthy, the
# gate correctly passed it, and the control reported the gate as having
# accepted a regression it was never shown. The version comes from the contract
# for the same reason every other version in this repository does.
REL="$(scripts/release-contract.sh get version)"
if [ -z "${REL}" ]; then
  printf 'could not read the release version from release.yaml\n' >&2
  exit 2
fi

# The wrong value a control injects. Any released version that is not this one
# will do; it only has to differ, or the mutation is not a mutation.
OTHER="3.0.0"
[ "${OTHER}" = "${REL}" ] && OTHER="2.0.0"

FAILED=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_RED=""; C_GREEN=""
fi

ok()   { printf "%s[PASS]%s %s\n" "${C_GREEN}" "${C_RESET}" "$*"; }
bad()  {
  FAILED=$((FAILED + 1))
  printf "%s[FAIL]%s %s\n" "${C_RED}" "${C_RESET}" "$1"
  [ -n "${2:-}" ] && printf "       %s%s%s\n" "${C_DIM}" "$2" "${C_RESET}"
}

# ---------------------------------------------------------------------------
# Build the fresh-clone copy: tracked files only, re-indexed so the gate's git
# based checks (file modes, tracked sources) behave exactly as on a real clone.
# ---------------------------------------------------------------------------
mkdir -p "${PRISTINE}"
git ls-files -z | while IFS= read -r -d '' f; do
  mkdir -p "${PRISTINE}/$(dirname "${f}")"
  cp -p "${f}" "${PRISTINE}/${f}"
done
(
  cd "${PRISTINE}" &&
    git init -q &&
    git add -Af >/dev/null
)

run_gate() { # run_gate <tree-dir> -> prints output, returns gate exit code
  ( cd "$1" && NO_COLOR=1 bash .github/scripts/check-distribution.sh 2>&1 )
}

# ---------------------------------------------------------------------------
printf "\n%sBaseline%s\n" "${C_BOLD}" "${C_RESET}"
# ---------------------------------------------------------------------------
if baseline_out="$(run_gate "${PRISTINE}")"; then
  ok "Gate passes on a clean, freshly cloned tree"
else
  bad "Gate does not pass on a clean tree — every negative control below is meaningless" \
    "$(printf '%s' "${baseline_out}" | grep -E '^\[FAIL\]' | head -n 10)"
  printf "\n%s1 control failed.%s\n" "${C_RED}" "${C_RESET}"
  exit 1
fi

# ---------------------------------------------------------------------------
printf "\n%sRegressions the gate must reject%s\n" "${C_BOLD}" "${C_RESET}"
# ---------------------------------------------------------------------------
# control <name> <expected-message-substring> <mutation-command…>
# The mutation runs with the copy as the working directory.
control() {
  local name="$1" expect="$2"
  shift 2

  local tree="${WORK}/case-${name}"
  rm -rf "${tree}"
  cp -a "${PRISTINE}" "${tree}"

  if ! ( cd "${tree}" && "$@" ) >/dev/null 2>&1; then
    bad "${name}: could not apply the mutation"
    return
  fi
  # Keep the index in step so git-based checks see the mutated tree.
  ( cd "${tree}" && git add -Af >/dev/null 2>&1 )

  local out
  if out="$(run_gate "${tree}")"; then
    bad "${name}: gate accepted the regression"
    return
  fi
  if printf '%s' "${out}" | grep -qF "${expect}"; then
    ok "${name}: rejected — ${expect}"
  else
    bad "${name}: rejected, but not for the expected reason" \
      "expected to see: ${expect}"
  fi
}

# --- Compose validity ------------------------------------------------------
control invalid-compose \
  "does not parse" \
  bash -c "printf '  bogus:\n    image\n' >> ${COMPOSE}"

# --- The release contract --------------------------------------------------
# These are the controls that matter most for the contract's central claim:
# that release.yaml is the source of version truth rather than a file that
# happens to sit next to one.
control contract-unreadable \
  "release.yaml is not in the documented shape" \
  bash -c "printf 'runtime:\n   backend: 3.1.0\n' >> release.yaml"

control contract-unknown-key \
  "declares a key no rule enforces" \
  bash -c "printf 'laucher: 3.1.0\n' >> release.yaml"

control contract-missing-key \
  "missing a required key" \
  sed -i "/^  ghcr: required$/d" release.yaml

control contract-mixed-runtime \
  "runtime.frontend does not name the release version" \
  sed -i "s/^  frontend: ${REL}$/  frontend: ${OTHER}/" release.yaml

# Compose drifting away from the contract is the drift this slice exists to
# catch, and it must be reported against the contract — not against whatever
# Compose happens to say.
control contract-compose-drift \
  "backend default does not name the release contract version" \
  sed -i "s|rainergewalt/trailmq-backend:${REL}}|rainergewalt/trailmq-backend:${OTHER}}|" "${COMPOSE}"

control contract-badge-drift \
  "README release badge does not name the shipped release" \
  sed -i "s|published%20release-${REL}-blue|published%20release-${OTHER}-blue|" README.md

# Declaring a track is a claim that a published artifact exists, so each thing
# that claim depends on has to be individually enforceable. The opposite
# direction is deliberately absent: source for an undeclared track is legal,
# and the baseline run proves it — cmd/trailmq is present while
# distribution.launcher is null, and the gate passes.
# Each control declares a track and then removes exactly one link of the
# evidence chain, so a partial claim fails on the part that is missing rather
# than on whichever check happens to run first.
control contract-track-without-build \
  "but nothing builds it" \
  bash -c "sed -i 's/^  windows_installer: null\$/  windows_installer: ${REL}/' release.yaml &&
           rm -rf distribution/windows"

control contract-track-without-publisher \
  "but nothing publishes it" \
  bash -c "sed -i 's/^  launcher: null\$/  launcher: ${REL}/' release.yaml &&
           rm -f .github/workflows/launcher-release.yml"

control contract-publisher-without-artifact \
  "publishes no artifact" \
  sed -i "/release upload/d; /upload-artifact/d" .github/workflows/evaluation-bundle.yml

control contract-publisher-without-verification \
  "verifies nothing it builds" \
  sed -i "s|\.github/scripts/|unchecked/|g" .github/workflows/evaluation-bundle.yml

control contract-publisher-off-release \
  "does not run when a release is published" \
  sed -i "/^  release:$/d" .github/workflows/evaluation-bundle.yml

control contract-orphan-compatibility \
  "disagree about existing" \
  sed -i "s/^  compatible_with: null$/  compatible_with: 3.1.0/" release.yaml

control contract-bad-surface \
  "not a recognized release obligation" \
  sed -i "s/^  docker: required$/  docker: maybe/" release.yaml

# --- Registry surfaces -----------------------------------------------------
# The registry page is where a stranger decides whether to pull the image, so
# these guard the two ways it goes wrong: text that drifts from the release,
# and text that describes a product surface which no longer exists.
REGISTRY="distribution/registry"

control registry-literal-version \
  "contains a literal version" \
  sed -i "s/{{version}}/3.1.0/" "${REGISTRY}/trailmq-backend.md"

control registry-unknown-placeholder \
  "uses an unknown placeholder" \
  bash -c "printf '\nBuilt for {{relase}}.\n' >> ${REGISTRY}/trailmq-backend.md"

control registry-missing-text \
  "is published but has no canonical registry text" \
  rm -f "${REGISTRY}/trailmq-frontend.md"

control registry-missing-ghcr \
  "does not name ghcr.io/rainergewalt/trailmq-backend" \
  sed -i "/^Also published to GHCR/d" "${REGISTRY}/trailmq-backend.md"

control registry-stale-surface \
  "does not name the 'Activity' surface" \
  sed -i "s/Activity/Events/g" "${REGISTRY}/trailmq-frontend.md"

control registry-open-source-license \
  "claims an open-source license" \
  sed -i "s/^  licenses: LicenseRef-TrailMQ-Evaluation$/  licenses: MIT/" "${REGISTRY}/oci-labels.yaml"

control registry-missing-label \
  "OCI label 'vendor' is empty or missing" \
  sed -i "/^  vendor: TrailMQ$/d" "${REGISTRY}/oci-labels.yaml"

# --- Scenario pack ---------------------------------------------------------
# Scenarios are what a stranger is shown. These guard the two ways that goes
# wrong: a story the runner cannot execute, and a story describing a release
# that has moved on.
SCENARIO="scenarios/unauthorized-machine-command.json"

control scenario-stale-compatibility \
  "was written for another release" \
  sed -i "s/\"compatibleWith\": \"${REL}\"/\"compatibleWith\": \"${OTHER}\"/" "${SCENARIO}"

control scenario-missing-explanation \
  "steps missing a headline, explanation or topic" \
  sed -i '0,/"explanation":/s//"explanation": "",  "unused":/' "${SCENARIO}"

control scenario-unknown-step-kind \
  "steps with an unknown kind" \
  sed -i 's/"kind": "publish_denied"/"kind": "publish_probably"/' "${SCENARIO}"

control scenario-dangling-actor \
  "refer to actors the scenario does not define" \
  sed -i 's/"actor": "operator"/"actor": "nobody"/' "${SCENARIO}"

control scenario-id-mismatch \
  "id does not match the file name" \
  sed -i 's/"id": "unauthorized-machine-command"/"id": "something-else"/' "${SCENARIO}"

control scenario-invalid-json \
  "is not valid JSON" \
  bash -c "printf ',\n' >> ${SCENARIO}"

# --- Stale recipe metadata -------------------------------------------------
control stale-recipe-image \
  "recipe.yaml images.backend is stale" \
  sed -i "s|backend: rainergewalt/trailmq-backend:.*|backend: rainergewalt/trailmq-backend:3.0.0|" "${RECIPE}/recipe.yaml"

control stale-recipe-port \
  "ports contradict Compose" \
  sed -i "s|- { host: 80,|- { host: 8080,|" "${RECIPE}/recipe.yaml"

# --- The proxy/port drift this gate exists to catch ------------------------
control stale-proxy-listen-port \
  "listen port does not match the Compose proxy port" \
  sed -i "s|^        listen 8080;|        listen 8081;|" "${RECIPE}/nginx.conf"

control stale-proxy-upstream \
  "proxies to a port" \
  sed -i "s|proxy_pass http://frontend:8080/;|proxy_pass http://frontend:3000/;|" "${RECIPE}/nginx.conf"

control backend-port-drift \
  "is not exposed or published by the backend" \
  sed -i "s|^rest_port: 8443|rest_port: 8444|" "${RECIPE}/config.yaml"

# --- Missing referenced files ----------------------------------------------
control missing-nginx-conf \
  "nginx.conf is missing but referenced by Compose" \
  rm -f "${RECIPE}/nginx.conf"

control unprepared-bind-mount \
  "which does not exist and is not created by scripts/launch.sh" \
  sed -i "s|      - ./nginx.conf:/etc/nginx/nginx.conf:ro|      - ./nginx.conf:/etc/nginx/nginx.conf:ro\n      - ./not-created-anywhere:/app/x:ro|" "${COMPOSE}"

# --- Image reference sanity ------------------------------------------------
control unpinned-image \
  "is not a pinned trailmq-backend tag" \
  sed -i "s|rainergewalt/trailmq-backend:${REL}}|rainergewalt/trailmq-backend:latest}|" "${COMPOSE}"

control unpinned-proxy-digest \
  "is not digest-pinned" \
  sed -i "s|nginxinc/nginx-unprivileged:1.27-alpine@sha256:[0-9a-f]*|nginxinc/nginx-unprivileged:1.27-alpine|g" "${COMPOSE}"

control stale-documented-image \
  "Stale TrailMQ image reference" \
  sed -i "s|rainergewalt/trailmq-frontend:${REL}|rainergewalt/trailmq-frontend:${OTHER}|" "${RECIPE}/README.md"

# --- Hardened deployment invariants ----------------------------------------
control privileged-service \
  "privileged mode is enabled" \
  sed -i "s|^    read_only: true|    privileged: true\n    read_only: true|" "${COMPOSE}"

control writable-root-filesystem \
  "root filesystem is not read-only" \
  sed -i "0,/^    read_only: true/s||    read_only: false|" "${COMPOSE}"

control added-capability \
  "adds Linux capabilities" \
  sed -i "0,/^    cap_drop:/s||    cap_add:\n      - NET_ADMIN\n    cap_drop:|" "${COMPOSE}"

control dropped-no-new-privileges \
  "missing security_opt no-new-privileges:true" \
  sed -i "0,/^      - no-new-privileges:true/s||      - seccomp:unconfined|" "${COMPOSE}"

control docker-socket-mount \
  "mounts the Docker socket" \
  sed -i "s|      - ./nginx.conf:/etc/nginx/nginx.conf:ro|      - ./nginx.conf:/etc/nginx/nginx.conf:ro\n      - /var/run/docker.sock:/var/run/docker.sock:ro|" "${COMPOSE}"

control host-namespace \
  "uses the host namespace" \
  sed -i "s|^  frontend:|  frontend:\n    pid: host|" "${COMPOSE}"

# --- Quickstart-sensitive documentation ------------------------------------
control broken-doc-link \
  "Broken relative link" \
  bash -c "printf '\n[gone](does-not-exist.md)\n' >> docs/quickstart.md"

control undocumented-cli-command \
  "which the CLI does not handle" \
  bash -c "printf '\n\`\`\`bash\n./trailmq nonexistent\n\`\`\`\n' >> docs/quickstart.md"

# --- Broken launcher --------------------------------------------------------
control broken-script-syntax \
  "[FAIL] bash -n scripts/doctor.sh" \
  bash -c "printf 'if [ 1 -eq 1 ]; then\n' >> scripts/doctor.sh"

# ---------------------------------------------------------------------------
printf "\n%sBundle self-containment%s\n" "${C_BOLD}" "${C_RESET}"
# ---------------------------------------------------------------------------
# The bundle is checked as a bundle, so its controls run against staged content
# rather than through the distribution gate. The property under test is the one
# a downloader experiences: a link in the download must lead somewhere.
BUNDLE="${WORK}/bundle"
cp -a "${PRISTINE}" "${BUNDLE}"
BUNDLE_VERSION="$(scripts/release-contract.sh get version)"

if .github/scripts/stage-evaluation-bundle.sh "${BUNDLE}" "${BUNDLE_VERSION}" >/dev/null 2>&1; then
  if .github/scripts/check-bundle-links.sh "${BUNDLE}" >/dev/null 2>&1; then
    ok "staged bundle: every relative link resolves inside the bundle"
  else
    bad "staged bundle: links do not resolve in freshly staged content" \
      "$(.github/scripts/check-bundle-links.sh "${BUNDLE}" 2>&1 | head -n 5)"
  fi

  # Removal is what broke these links in the first place, so the fix has to be
  # visible in the staged output rather than assumed.
  if grep -rq 'https://github.com/RainerGewalt/TrailMQ/blob/master/CONTRIBUTING.md' "${BUNDLE}"; then
    ok "staged bundle: links to stripped paths point at the canonical document"
  else
    bad "staged bundle: a link to a stripped path was not repointed"
  fi

  # And the check must actually be able to fail. A link checker that passes on
  # a bundle with a missing document is not a check.
  rm -f "${BUNDLE}/docs/troubleshooting.md"
  if .github/scripts/check-bundle-links.sh "${BUNDLE}" >/dev/null 2>&1; then
    bad "staged bundle: link check accepted a bundle with a missing document"
  else
    ok "missing-bundle-document: rejected — a removed target is reported"
  fi
else
  bad "staged bundle: staging failed" \
    "$(.github/scripts/stage-evaluation-bundle.sh "${BUNDLE}" "${BUNDLE_VERSION}" 2>&1 | head -n 5)"
fi

# ---------------------------------------------------------------------------
printf "\n%sResult%s\n" "${C_BOLD}" "${C_RESET}"
# ---------------------------------------------------------------------------
if [ "${FAILED}" -eq 0 ]; then
  printf "%sAll negative controls behaved as expected.%s\n" "${C_GREEN}" "${C_RESET}"
  exit 0
fi
printf "%s%s control(s) failed.%s\n" "${C_RED}" "${FAILED}" "${C_RESET}"
exit 1
