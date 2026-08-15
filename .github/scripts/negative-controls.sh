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
  sed -i "s|rainergewalt/trailmq-backend:3.1.0}|rainergewalt/trailmq-backend:latest}|" "${COMPOSE}"

control unpinned-proxy-digest \
  "is not digest-pinned" \
  sed -i "s|nginxinc/nginx-unprivileged:1.27-alpine@sha256:[0-9a-f]*|nginxinc/nginx-unprivileged:1.27-alpine|g" "${COMPOSE}"

control stale-documented-image \
  "Stale TrailMQ image reference" \
  sed -i "s|rainergewalt/trailmq-frontend:3.1.0|rainergewalt/trailmq-frontend:3.0.0|" "${RECIPE}/README.md"

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
printf "\n%sResult%s\n" "${C_BOLD}" "${C_RESET}"
# ---------------------------------------------------------------------------
if [ "${FAILED}" -eq 0 ]; then
  printf "%sAll negative controls behaved as expected.%s\n" "${C_GREEN}" "${C_RESET}"
  exit 0
fi
printf "%s%s control(s) failed.%s\n" "${C_RED}" "${FAILED}" "${C_RESET}"
exit 1
