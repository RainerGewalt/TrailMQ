#!/usr/bin/env bash
# TrailMQ — public distribution gate.
#
# Checks the promises this repository makes to a public user: the published
# Compose stack parses, the launcher scripts are syntactically sound, the recipe
# metadata still describes the Compose file it claims to describe, the proxy port
# wiring is internally consistent, the hardened defaults are still declared, and
# the documented first run is still reachable from a fresh clone.
#
# Everything here is static. No runtime image is pulled, built, started, signed
# or published, and no private infrastructure is contacted. Where the shellcheck
# binary is installed — which includes every CI runner used here — the whole gate
# runs offline; the pinned linter image below is only a fallback for machines
# without it.
#
# Run it locally exactly as CI does:
#   .github/scripts/check-distribution.sh
#
# Requires: bash 4+, docker compose v2, jq.

set -uo pipefail

# Fallback linter for machines without shellcheck installed. Pinned so a local
# run cannot silently use a different version than the one reviewed here.
SHELLCHECK_IMAGE="koalaman/shellcheck:v0.11.0"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}" || exit 2

FAILED=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_RED=""; C_GREEN=""
fi

section() { printf "\n%s%s%s\n" "${C_BOLD}" "$*" "${C_RESET}"; }
pass()    { printf "%s[PASS]%s %s\n" "${C_GREEN}" "${C_RESET}" "$*"; }
skip()    { printf "%s[SKIP] %s%s\n" "${C_DIM}" "$*" "${C_RESET}"; }
fail() {
  FAILED=$((FAILED + 1))
  printf "%s[FAIL]%s %s\n" "${C_RED}" "${C_RESET}" "$1"
  if [ -n "${2:-}" ]; then
    printf "       %s%s%s\n" "${C_DIM}" "$2" "${C_RESET}"
  fi
}

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf "%s[FAIL]%s Required tool missing: %s\n" "${C_RED}" "${C_RESET}" "$1"
    exit 2
  fi
}

need docker
need jq
if ! docker compose version >/dev/null 2>&1; then
  printf "%s[FAIL]%s Docker Compose v2 is required ('docker compose version' failed)\n" \
    "${C_RED}" "${C_RESET}"
  exit 2
fi

# Recipes are discovered, never hardcoded, so a new recipe is gated the day it
# is added rather than the day someone remembers to extend this script.
mapfile -t RECIPES < <(find recipes -mindepth 2 -maxdepth 2 -name docker-compose.yaml -printf '%h\n' | sort)
if [ "${#RECIPES[@]}" -eq 0 ]; then
  fail "No recipe found" "expected at least one recipes/*/docker-compose.yaml"
  exit 1
fi

# Rendered Compose config per recipe, resolved once. The TRAILMQ_* overrides are
# unset so the run describes the defaults a first-time user actually gets.
declare -A COMPOSE_JSON
render_compose() {
  local dir="$1"
  (
    cd "${dir}" || exit 1
    env -u TRAILMQ_BACKEND_IMAGE -u TRAILMQ_FRONTEND_IMAGE -u TRAILMQ_NGINX_IMAGE \
        -u TRAILMQ_HTTP_PORT -u TRAILMQ_MQTT_TLS_PORT \
      docker compose config --format json 2>/dev/null
  )
}

# --------------------------------------------------------------------------
section "1. Compose validity"
# --------------------------------------------------------------------------
for dir in "${RECIPES[@]}"; do
  if err="$(cd "${dir}" && docker compose config -q 2>&1)"; then
    pass "${dir}/docker-compose.yaml parses"
  else
    fail "${dir}/docker-compose.yaml does not parse" "${err}"
    continue
  fi

  json="$(render_compose "${dir}")"
  if [ -z "${json}" ] || ! printf '%s' "${json}" | jq -e . >/dev/null 2>&1; then
    fail "${dir}: rendered Compose config is not usable JSON"
    continue
  fi
  COMPOSE_JSON["${dir}"]="${json}"

  # The documented port overrides are part of the public contract (README,
  # docs/troubleshooting.md), so they have to survive rendering too.
  override_json="$(
    cd "${dir}" &&
      TRAILMQ_HTTP_PORT=8080 TRAILMQ_MQTT_TLS_PORT=8884 \
        docker compose config --format json 2>/dev/null
  )"
  published="$(printf '%s' "${override_json}" |
    jq -r '[.services[].ports // [] | .[].published] | sort | join(",")' 2>/dev/null)"
  if [ "${published}" = "8080,8884" ]; then
    pass "${dir}: TRAILMQ_HTTP_PORT / TRAILMQ_MQTT_TLS_PORT overrides still apply"
  else
    fail "${dir}: documented port overrides did not take effect" \
      "TRAILMQ_HTTP_PORT=8080 TRAILMQ_MQTT_TLS_PORT=8884 published '${published}', expected '8080,8884'"
  fi
done

# --------------------------------------------------------------------------
section "2. Shell script sanity"
# --------------------------------------------------------------------------
mapfile -t SHELL_FILES < <(
  {
    printf 'trailmq\n'
    find scripts .github/scripts -name '*.sh' -type f 2>/dev/null
  } | sort -u
)

for f in "${SHELL_FILES[@]}"; do
  if err="$(bash -n "${f}" 2>&1)"; then
    pass "bash -n ${f}"
  else
    fail "bash -n ${f}" "${err}"
  fi
done

# A clone whose launcher is not executable cannot run the documented first
# command, so the mode in the index is part of the contract.
for f in "${SHELL_FILES[@]}"; do
  mode="$(git ls-files -s -- "${f}" | awk '{print $1}')"
  if [ -z "${mode}" ]; then
    fail "${f} is not tracked by git"
  elif [ "${mode}" != "100755" ]; then
    fail "${f} is not executable in the git index" "mode ${mode}, expected 100755"
  fi
done
pass "executable bits checked for ${#SHELL_FILES[@]} shell files"

# An installed shellcheck is preferred over the pinned image on purpose. CI
# runners ship one, so the gate needs no network and cannot be turned red by a
# registry rate limit — which would be flake, not a finding. A linter upgrade can
# still surface a new warning, but that is a real finding in a real script, and
# the workflow logs the version it used.
if command -v shellcheck >/dev/null 2>&1; then
  if err="$(shellcheck --severity=warning --external-sources "${SHELL_FILES[@]}" 2>&1)"; then
    pass "shellcheck $(shellcheck --version | sed -n 's/^version: //p') (severity=warning)"
  else
    fail "shellcheck reported warnings or errors" "${err}"
  fi
elif docker image inspect "${SHELLCHECK_IMAGE}" >/dev/null 2>&1 ||
  docker pull -q "${SHELLCHECK_IMAGE}" >/dev/null 2>&1; then
  if err="$(docker run --rm -v "${REPO_ROOT}:/mnt:ro" -w /mnt "${SHELLCHECK_IMAGE}" \
    --severity=warning --external-sources "${SHELL_FILES[@]}" 2>&1)"; then
    pass "shellcheck ${SHELLCHECK_IMAGE#*:} (severity=warning, containerized)"
  else
    fail "shellcheck reported warnings or errors" "${err}"
  fi
else
  skip "shellcheck unavailable (not installed, ${SHELLCHECK_IMAGE} not pullable) — bash -n only"
fi

# --------------------------------------------------------------------------
section "3. Release contract"
# --------------------------------------------------------------------------
# release.yaml declares what belongs to this release. Everything downstream —
# Compose defaults, recipe metadata, the README badge, the launcher, the
# evaluation bundle — is checked against it rather than against another
# artifact that happens to be nearby.
#
# Declaration requires evidence; source presence does not require declaration.
#
# A track goes through implemented → packaged → released, and only the last
# state belongs in the contract. Code for a launcher, an installer or a
# scenario pack may exist here long before any release ships it, so the mere
# presence of cmd/trailmq says nothing about what TrailMQ 3.1.0 contained.
#
# What is checked is the other direction. Naming a version for a track means
# claiming a published artifact exists, so the gate requires the four things
# that claim depends on:
#
#   1. a build — the source or script the artifact is produced from;
#   2. a workflow that publishes it when a release is published;
#   3. a step in that workflow that verifies what it built;
#   4. the version taken from release.yaml, not typed into the workflow.
#
# Each entry is track|build|release-workflow. The workflow file is allowed not
# to exist yet — that is precisely what keeps a track undeclarable until
# someone builds the thing that ships it.
#
# Order matters: entries are listed, not iterated from an associative array,
# so the gate output is identical on every run.
TRACKS=(
  "distribution.evaluation_bundle|.github/scripts/build-evaluation-bundle.sh|.github/workflows/evaluation-bundle.yml"
  "distribution.launcher|cmd/trailmq|.github/workflows/launcher-release.yml"
  "distribution.windows_installer|distribution/windows|.github/workflows/launcher-release.yml"
  "demo.scenario_pack|scenarios|.github/workflows/scenario-pack.yml"
)

REQUIRED_CONTRACT_KEYS=(
  version
  runtime.backend
  runtime.frontend
  distribution.evaluation_bundle
  distribution.launcher
  distribution.windows_installer
  demo.scenario_pack
  demo.compatible_with
  public_surfaces.docker
  public_surfaces.ghcr
  public_surfaces.website.download
  public_surfaces.website.demo
)

CONTRACT_VERSION=""
CONTRACT_FLAT=""

cget() {
  printf '%s\n' "${CONTRACT_FLAT}" |
    awk -F'\t' -v k="$1" '$1 == k { print $2; found = 1; exit } END { exit !found }'
}

if [ ! -f release.yaml ]; then
  fail "release.yaml is missing" \
    "the release contract is the source of version truth for this repository"
elif ! CONTRACT_FLAT="$(scripts/release-contract.sh flatten 2>&1)"; then
  fail "release.yaml is not in the documented shape" "${CONTRACT_FLAT}"
  CONTRACT_FLAT=""
else
  pass "release.yaml reads in the documented shape"

  # A typo'd key is the failure this catches: 'laucher: 3.1.0' would otherwise
  # parse fine, declare nothing, and be enforced by no rule at all.
  missing=0
  for key in "${REQUIRED_CONTRACT_KEYS[@]}"; do
    if ! cget "${key}" >/dev/null; then
      fail "release.yaml is missing a required key" "${key}"
      missing=$((missing + 1))
    fi
  done
  while IFS= read -r key; do
    [ -z "${key}" ] && continue
    known=false
    for required in "${REQUIRED_CONTRACT_KEYS[@]}"; do
      [ "${key}" = "${required}" ] && known=true && break
    done
    ${known} || fail "release.yaml declares a key no rule enforces" "${key}"
  done < <(printf '%s\n' "${CONTRACT_FLAT}" | cut -f1)
  [ "${missing}" -eq 0 ] &&
    pass "release.yaml declares all ${#REQUIRED_CONTRACT_KEYS[@]} required keys"

  CONTRACT_VERSION="$(cget version || true)"
  if [[ "${CONTRACT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "release contract names version ${CONTRACT_VERSION}"
  else
    fail "release.yaml version is not a release version" "got '${CONTRACT_VERSION}'"
    CONTRACT_VERSION=""
  fi

  # Backend and frontend ship as one release. A mixed pair is a combination
  # nothing was tested against.
  for component in backend frontend; do
    declared="$(cget "runtime.${component}" || true)"
    if [ -n "${CONTRACT_VERSION}" ] && [ "${declared}" = "${CONTRACT_VERSION}" ]; then
      pass "runtime.${component} names the release version"
    else
      fail "runtime.${component} does not name the release version" \
        "runtime.${component} '${declared}', version '${CONTRACT_VERSION}'"
    fi
  done

  for entry in "${TRACKS[@]}"; do
    track="${entry%%|*}"
    remainder="${entry#*|}"
    build="${remainder%%|*}"
    workflow="${remainder#*|}"
    declared="$(cget "${track}" || true)"

    if [ "${declared}" = "null" ]; then
      # Source may exist. Work on a track is not a claim that a release
      # shipped it, and treating it as one would mean a launcher could not be
      # written without backdating it into an already-published release.
      if [ -e "${build}" ]; then
        pass "${track} is not part of this release (implementation present)"
      else
        pass "${track} is not part of this release"
      fi
      continue
    fi

    if [ -n "${CONTRACT_VERSION}" ] && [ "${declared}" != "${CONTRACT_VERSION}" ]; then
      fail "${track} does not name the release version" \
        "${track} '${declared}', version '${CONTRACT_VERSION}'"
      continue
    fi

    if [ ! -e "${build}" ]; then
      fail "release.yaml declares ${track} ${declared}, but nothing builds it" \
        "expected ${build}"
      continue
    fi

    if [ ! -f "${workflow}" ]; then
      fail "release.yaml declares ${track} ${declared}, but nothing publishes it" \
        "expected a release workflow at ${workflow} — a declared track is a claim that an artifact ships"
      continue
    fi

    track_ok=true

    # Published on release, not only when someone remembers to run it.
    if ! grep -qE '^[[:space:]]*release:[[:space:]]*$' "${workflow}"; then
      fail "${workflow} does not run when a release is published" \
        "${track} is declared for ${declared}, so its artifact has to be produced by the release"
      track_ok=false
    fi

    # Produces something. A workflow that builds and keeps nothing has not
    # shipped the artifact the contract is promising.
    if ! grep -qE 'release upload|upload-artifact' "${workflow}"; then
      fail "${workflow} publishes no artifact" \
        "expected a release upload or an artifact upload step"
      track_ok=false
    fi

    # Verifies what it built. Checked by requiring the workflow to run one of
    # this repository's own checks — an approximation of "a smoke test exists",
    # and a deliberate one: a publish workflow that runs none of the checks
    # this repository maintains is not verifying anything.
    if ! grep -q '\.github/scripts/' "${workflow}"; then
      fail "${workflow} verifies nothing it builds" \
        "expected it to run at least one check from .github/scripts/"
      track_ok=false
    fi

    # Takes the version from the contract rather than repeating it.
    if ! grep -qE 'release-contract\.sh|release\.yaml' "${workflow}" &&
      ! grep -qE 'release-contract\.sh|release\.yaml' "${build}" 2>/dev/null; then
      fail "${track} ${declared} is versioned outside the release contract" \
        "neither ${workflow} nor ${build} reads release.yaml"
      track_ok=false
    fi

    ${track_ok} && pass "${track} ${declared} is built, published and verified"
  done

  # A scenario pack names the runtime it was written against, which is not
  # automatically the current release — but it cannot be silent either way.
  pack="$(cget demo.scenario_pack || true)"
  compat="$(cget demo.compatible_with || true)"
  if [ "${pack}" = "null" ] && [ "${compat}" = "null" ]; then
    pass "no scenario pack is declared, and none claims compatibility"
  elif [ "${pack}" = "null" ] || [ "${compat}" = "null" ]; then
    fail "demo.scenario_pack and demo.compatible_with disagree about existing" \
      "scenario_pack '${pack}', compatible_with '${compat}'"
  elif [[ "${compat}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass "scenario pack ${pack} declares compatibility with runtime ${compat}"
  else
    fail "demo.compatible_with is not a runtime version" "got '${compat}'"
  fi

  # These name obligations this gate cannot verify — it never leaves the
  # repository. Checking the vocabulary still stops an unreadable value from
  # reaching the publication stage that does have to act on it.
  for surface in public_surfaces.docker public_surfaces.ghcr \
    public_surfaces.website.download public_surfaces.website.demo; do
    value="$(cget "${surface}" || true)"
    case "${value}" in
      required | optional)
        pass "${surface} is '${value}'" ;;
      *)
        fail "${surface} is not a recognized release obligation" \
          "got '${value}', expected 'required' or 'optional'" ;;
    esac
  done
fi

# --------------------------------------------------------------------------
section "4. Image references and version consistency"
# --------------------------------------------------------------------------
# What a user who sets no environment variable actually pulls has to be the
# release the contract declares.
CANONICAL_VERSION=""
for dir in "${RECIPES[@]}"; do
  json="${COMPOSE_JSON[${dir}]:-}"
  [ -z "${json}" ] && continue

  backend_image="$(printf '%s' "${json}" | jq -r '.services.backend.image // empty')"
  frontend_image="$(printf '%s' "${json}" | jq -r '.services.frontend.image // empty')"
  nginx_image="$(printf '%s' "${json}" | jq -r '.services.nginx.image // empty')"

  # A version-shaped tag, not a moving one: 'latest' would make the release the
  # documentation describes unknowable.
  if [[ "${backend_image}" =~ ^rainergewalt/trailmq-backend:([0-9][A-Za-z0-9._-]*)$ ]]; then
    CANONICAL_VERSION="${BASH_REMATCH[1]}"
    pass "${dir}: backend default resolves to ${backend_image}"

    if [ -n "${CONTRACT_VERSION}" ] && [ "${CANONICAL_VERSION}" != "${CONTRACT_VERSION}" ]; then
      fail "${dir}: backend default does not name the release contract version" \
        "Compose '${CANONICAL_VERSION}', release.yaml '${CONTRACT_VERSION}'"
    fi
  else
    fail "${dir}: backend default image is not a pinned trailmq-backend tag" "got '${backend_image}'"
  fi

  # The contract is the authority. Falling back to the Compose tag only keeps
  # the message useful in the run where the contract itself already failed.
  expected_version="${CONTRACT_VERSION:-${CANONICAL_VERSION}}"
  if [ -n "${expected_version}" ] &&
    [ "${frontend_image}" = "rainergewalt/trailmq-frontend:${expected_version}" ]; then
    pass "${dir}: frontend default matches the declared release (${expected_version})"
  else
    fail "${dir}: frontend default does not match the declared release" \
      "frontend '${frontend_image}', expected 'rainergewalt/trailmq-frontend:${expected_version}'"
  fi

  # A moving tag would let the proxy change under a rebuild, which is exactly
  # what the published hardening claims cannot happen.
  if [[ "${nginx_image}" =~ @sha256:[0-9a-f]{64}$ ]]; then
    pass "${dir}: reverse proxy image is digest-pinned"
  else
    fail "${dir}: reverse proxy image is not digest-pinned" "got '${nginx_image}'"
  fi

  # The public proxy contract is the unprivileged nginx variant. This is a name
  # check, not proof of the effective runtime user — see the note in section 5.
  if [[ "${nginx_image}" == nginxinc/nginx-unprivileged:* ]]; then
    pass "${dir}: reverse proxy uses the unprivileged nginx image"
  else
    fail "${dir}: reverse proxy is not the unprivileged nginx image" "got '${nginx_image}'"
  fi

  while IFS=$'\t' read -r svc image; do
    if [ "${image}" = "${image%:latest}" ] && [[ "${image}" == *:* ]]; then
      continue
    fi
    fail "${dir}: service '${svc}' uses an unpinned image" "got '${image}'"
  done < <(printf '%s' "${json}" | jq -r '.services | to_entries[] | "\(.key)\t\(.value.image)"')

  # recipe.yaml describes the recipe in the launcher and in status output. If it
  # drifts from Compose, the product tells the user something untrue.
  recipe_yaml="${dir}/recipe.yaml"
  if [ ! -f "${recipe_yaml}" ]; then
    fail "${dir}: recipe.yaml is missing"
  else
    recipe_id="$(sed -nE 's/^id:[[:space:]]*([^[:space:]#]+).*/\1/p' "${recipe_yaml}" | head -n1)"
    if [ "${recipe_id}" = "$(basename "${dir}")" ]; then
      pass "${dir}: recipe.yaml id matches the recipe folder"
    else
      fail "${dir}: recipe.yaml id does not match the folder" \
        "id '${recipe_id}', folder '$(basename "${dir}")'"
    fi

    for svc in backend frontend nginx; do
      declared="$(sed -nE "s/^[[:space:]]+${svc}:[[:space:]]*([^[:space:]#]+).*/\1/p" "${recipe_yaml}" | head -n1)"
      actual="$(printf '%s' "${json}" | jq -r --arg s "${svc}" '.services[$s].image // empty')"
      if [ -n "${declared}" ] && [ "${declared}" = "${actual}" ]; then
        pass "${dir}: recipe.yaml images.${svc} matches Compose"
      else
        fail "${dir}: recipe.yaml images.${svc} is stale" \
          "recipe.yaml '${declared}', Compose '${actual}'"
      fi
    done
  fi
done

RELEASE_VERSION="${CONTRACT_VERSION:-${CANONICAL_VERSION}}"
if [ -z "${RELEASE_VERSION}" ]; then
  fail "Could not determine the release version from release.yaml or Compose"
else
  # Every place that names a TrailMQ image must name the release being shipped.
  # Two paths are excluded on purpose: .env.example documents pinning to an
  # older published release, which is a supported user action rather than
  # drift, and .github/scripts holds the deliberate counter-examples the
  # negative controls inject.
  drift=0
  while IFS= read -r hit; do
    file="${hit%%:*}"
    tag="${hit##*:}"
    if [ "${tag}" != "${RELEASE_VERSION}" ]; then
      fail "Stale TrailMQ image reference in ${file}" "${hit}"
      drift=$((drift + 1))
    fi
  done < <(
    git grep -oE 'rainergewalt/trailmq-(backend|frontend):[0-9][A-Za-z0-9._-]*' -- \
      . ':(exclude).env.example' ':(exclude).github/scripts'
  )
  if [ "${drift}" -eq 0 ]; then
    pass "All TrailMQ image references name ${RELEASE_VERSION}"
  fi

  badge="$(sed -nE 's@.*img\.shields\.io/badge/published%20release-([^-]+)-.*@\1@p' README.md | head -n1)"
  if [ "${badge}" = "${RELEASE_VERSION}" ]; then
    pass "README release badge names ${RELEASE_VERSION}"
  else
    fail "README release badge does not name the shipped release" \
      "badge '${badge}', release ${RELEASE_VERSION}"
  fi

  # The launcher builds its image references from the contract, so this asks
  # the CLI what it would actually tell a user rather than trusting that the
  # wiring is still in place. It needs no Docker daemon and no active recipe.
  cli_version="$(bash ./trailmq version 2>/dev/null | sed -nE 's/^TrailMQ ([0-9][^ ]*) .*/\1/p' | head -n1)"
  if [ "${cli_version}" = "${RELEASE_VERSION}" ]; then
    pass "'./trailmq version' reports ${RELEASE_VERSION}"
  else
    fail "'./trailmq version' does not report the shipped release" \
      "CLI '${cli_version:-<no version line>}', release ${RELEASE_VERSION}"
  fi
fi

# --------------------------------------------------------------------------
section "5. Port and proxy wiring"
# --------------------------------------------------------------------------
for dir in "${RECIPES[@]}"; do
  json="${COMPOSE_JSON[${dir}]:-}"
  [ -z "${json}" ] && continue
  recipe_yaml="${dir}/recipe.yaml"
  [ -f "${recipe_yaml}" ] || continue

  # recipe.yaml ports:  - { host: 80, container: 8080, service: nginx, ... }
  #
  # This reads one documented flow-style shape rather than parsing YAML. That is
  # a deliberate trade — no parser dependency for a small, stable file — but it
  # is an assumption, so a reformatted block is reported as an unreadable file
  # instead of being mistaken for a port mismatch.
  compose_ports="$(printf '%s' "${json}" |
    jq -r '.services | to_entries[] | .key as $s | (.value.ports // [])[] |
           "\($s)\t\(.published)\t\(.target)"' | sort)"
  declared_ports="$(sed -nE \
    's/^[[:space:]]*-[[:space:]]*\{[[:space:]]*host:[[:space:]]*([0-9]+),[[:space:]]*container:[[:space:]]*([0-9]+),[[:space:]]*service:[[:space:]]*([A-Za-z0-9_-]+).*/\3\t\1\t\2/p' \
    "${recipe_yaml}" | sort)"

  if [ -z "${declared_ports}" ] && grep -qE '^ports:' "${recipe_yaml}"; then
    fail "${dir}: recipe.yaml has a ports: block this gate cannot read" \
      "expected entries shaped '- { host: N, container: N, service: NAME, name: \"…\" }'"
  elif [ "${compose_ports}" = "${declared_ports}" ]; then
    pass "${dir}: recipe.yaml ports match the published Compose ports"
  else
    fail "${dir}: recipe.yaml ports contradict Compose" \
      "recipe.yaml: $(printf '%s' "${declared_ports}" | tr '\n' ' ') | compose: $(printf '%s' "${compose_ports}" | tr '\n' ' ')"
  fi

  nginx_conf="${dir}/nginx.conf"
  if [ ! -f "${nginx_conf}" ]; then
    fail "${dir}: nginx.conf is missing but referenced by Compose"
  else
    # The proxy's container port is the one drift that silently breaks the
    # documented first run: the host mapping still looks right, nothing listens.
    listen_port="$(sed -nE 's/^[[:space:]]*listen[[:space:]]+([0-9]+);.*/\1/p' "${nginx_conf}" | head -n1)"
    proxy_target="$(printf '%s' "${json}" | jq -r '(.services.nginx.ports // [])[0].target // empty')"
    if [ -n "${listen_port}" ] && [ "${listen_port}" = "${proxy_target}" ]; then
      pass "${dir}: nginx.conf listens on the port Compose publishes to (${listen_port})"
    else
      fail "${dir}: nginx.conf listen port does not match the Compose proxy port" \
        "nginx.conf listens on '${listen_port}', Compose maps the host port to '${proxy_target}'"
    fi

    proxy_health="$(printf '%s' "${json}" | jq -r '.services.nginx.healthcheck.test // [] | join(" ")')"
    if [ -z "${proxy_health}" ] || [[ "${proxy_health}" == *":${listen_port}/"* ]]; then
      pass "${dir}: proxy healthcheck probes the port nginx listens on"
    else
      fail "${dir}: proxy healthcheck probes a port nginx does not listen on" \
        "healthcheck '${proxy_health}', listen ${listen_port}"
    fi

    # Every upstream nginx proxies to must be a real service on a port that
    # service actually exposes.
    while IFS=$'\t' read -r upstream port; do
      [ -z "${upstream}" ] && continue
      if ! printf '%s' "${json}" | jq -e --arg s "${upstream}" '.services[$s]' >/dev/null; then
        fail "${dir}: nginx.conf proxies to unknown service '${upstream}'"
        continue
      fi
      exposed="$(printf '%s' "${json}" | jq -r --arg s "${upstream}" \
        '[(.services[$s].expose // [])[] , ((.services[$s].ports // [])[] | .target | tostring)] | join(" ")')"
      if [[ " ${exposed} " == *" ${port} "* ]]; then
        pass "${dir}: nginx.conf → ${upstream}:${port} is an exposed port"
      else
        fail "${dir}: nginx.conf proxies to a port '${upstream}' does not expose" \
          "wants ${upstream}:${port}, service exposes: ${exposed:-none}"
      fi
    done < <(sed -nE 's@^[[:space:]]*proxy_pass[[:space:]]+http://([A-Za-z0-9_-]+):([0-9]+).*@\1\t\2@p' "${nginx_conf}" | sort -u)
  fi

  # config.yaml is what the backend binds. If it and Compose disagree, the proxy
  # points at nothing.
  config_yaml="${dir}/config.yaml"
  if [ ! -f "${config_yaml}" ]; then
    fail "${dir}: config.yaml is missing but mounted by Compose"
  else
    backend_exposed="$(printf '%s' "${json}" | jq -r \
      '[((.services.backend.expose // [])[]), ((.services.backend.ports // [])[] | .target | tostring)] | join(" ")')"
    for key in rest_port mqtt_ws_port mqtt_port; do
      value="$(sed -nE "s/^${key}:[[:space:]]*([0-9]+).*/\1/p" "${config_yaml}" | head -n1)"
      if [ -z "${value}" ]; then
        fail "${dir}: config.yaml does not define ${key}"
      elif [[ " ${backend_exposed} " == *" ${value} "* ]]; then
        pass "${dir}: config.yaml ${key}=${value} is reachable in Compose"
      else
        fail "${dir}: config.yaml ${key}=${value} is not exposed or published by the backend" \
          "backend offers: ${backend_exposed}"
      fi
    done

    rest_port="$(sed -nE 's/^rest_port:[[:space:]]*([0-9]+).*/\1/p' "${config_yaml}" | head -n1)"
    backend_health="$(printf '%s' "${json}" | jq -r '.services.backend.healthcheck.test // [] | join(" ")')"
    if [ -z "${backend_health}" ] || [[ "${backend_health}" == *":${rest_port}/"* ]]; then
      pass "${dir}: backend healthcheck probes the configured REST port"
    else
      fail "${dir}: backend healthcheck probes a port the backend does not serve REST on" \
        "healthcheck '${backend_health}', config.yaml rest_port ${rest_port}"
    fi
  fi
done

# --------------------------------------------------------------------------
section "6. Hardened deployment invariants (declared configuration)"
# --------------------------------------------------------------------------
# These read the rendered Compose configuration. They prove what the published
# deployment DECLARES. They do not prove effective runtime privileges, image
# users, or kernel-level confinement — that needs a running container and is out
# of scope for a PR gate.
for dir in "${RECIPES[@]}"; do
  json="${COMPOSE_JSON[${dir}]:-}"
  [ -z "${json}" ] && continue
  recipe_abs="$(cd "${dir}" && pwd)"

  mapfile -t services < <(printf '%s' "${json}" | jq -r '.services | keys[]')
  for svc in "${services[@]}"; do
    s="$(printf '%s' "${json}" | jq -c --arg s "${svc}" '.services[$s]')"
    q() { printf '%s' "${s}" | jq -r "$1"; }

    [ "$(q '.privileged // false')" = "false" ] ||
      fail "${dir}/${svc}: privileged mode is enabled"

    added="$(q '(.cap_add // []) | join(",")')"
    [ -z "${added}" ] ||
      fail "${dir}/${svc}: adds Linux capabilities" "cap_add: ${added}"

    [ "$(q '[(.cap_drop // [])[] | ascii_upcase] | index("ALL") != null')" = "true" ] ||
      fail "${dir}/${svc}: does not drop ALL capabilities"

    [ "$(q '(.security_opt // []) | index("no-new-privileges:true") != null')" = "true" ] ||
      fail "${dir}/${svc}: missing security_opt no-new-privileges:true"

    [ "$(q '.read_only // false')" = "true" ] ||
      fail "${dir}/${svc}: root filesystem is not read-only"

    for ns in network_mode pid ipc userns_mode; do
      value="$(q ".${ns} // \"\"")"
      case "${value}" in
        host|*:host) fail "${dir}/${svc}: uses the host namespace" "${ns}: ${value}" ;;
      esac
    done

    devices="$(q '(.devices // []) | length')"
    [ "${devices}" = "0" ] ||
      fail "${dir}/${svc}: passes host devices into the container"

    # A Docker socket mount is a full host escape and must never appear in a
    # public evaluation stack.
    while IFS= read -r src; do
      [ -z "${src}" ] && continue
      case "${src}" in
        */docker.sock)
          fail "${dir}/${svc}: mounts the Docker socket" "${src}" ;;
      esac
      # Every bind source must stay inside the recipe. Anything else reaches
      # into the evaluator's machine.
      if [[ "${src}" == /* ]] && [[ "${src}" != "${recipe_abs}"/* ]]; then
        fail "${dir}/${svc}: bind-mounts a path outside the recipe folder" "${src}"
      fi
    done < <(q '(.volumes // [])[] | select(.type == "bind") | .source')
  done
  pass "${dir}: ${#services[@]} services declare unprivileged, read-only, capability-dropped defaults"
done

# --------------------------------------------------------------------------
section "7. Documented first run is still possible"
# --------------------------------------------------------------------------
# Directories the launcher creates before `docker compose up`. Anything Compose
# bind-mounts must either be committed or appear here.
mapfile -t PREPARED < <(
  grep -oE '\$\{recipe_dir\}/[a-z][a-z-]*"' scripts/launch.sh |
    sed -E 's@\$\{recipe_dir\}/@@; s@"@@' | sort -u
)

for dir in "${RECIPES[@]}"; do
  json="${COMPOSE_JSON[${dir}]:-}"
  [ -z "${json}" ] && continue
  recipe_abs="$(cd "${dir}" && pwd)"

  missing=0
  while IFS= read -r src; do
    [ -z "${src}" ] && continue
    rel="${src#"${recipe_abs}"/}"
    top="${rel%%/*}"
    if [ -e "${src}" ]; then
      continue
    fi
    if printf '%s\n' "${PREPARED[@]}" | grep -qx "${top}"; then
      continue
    fi
    fail "${dir}: Compose mounts '${rel}', which does not exist and is not created by scripts/launch.sh"
    missing=$((missing + 1))
  done < <(printf '%s' "${json}" | jq -r '.services[] | (.volumes // [])[] | select(.type == "bind") | .source')

  if [ "${missing}" -eq 0 ]; then
    pass "${dir}: every bind mount is committed or prepared by the launcher"
  fi
done

# The launcher must not select a recipe that does not exist.
while IFS= read -r r; do
  if [ -d "recipes/${r}" ]; then
    pass "scripts/launch.sh selects an existing recipe (${r})"
  else
    fail "scripts/launch.sh selects a recipe that does not exist" "recipes/${r}"
  fi
done < <(sed -nE 's/^[[:space:]]*(recipe=|[0-9]+\) recipe=)"([a-z0-9-]+)".*/\2/p' scripts/launch.sh | sort -u)

# Every ./trailmq command the documentation tells a user to run must be a
# command the CLI actually dispatches.
cli_body="$(sed -n '/^case "\$cmd" in/,/^esac/p' trailmq)"
unknown=0
while IFS= read -r cmd; do
  if printf '%s' "${cli_body}" | grep -qE "(^|[ (|])${cmd}[)|]"; then
    continue
  fi
  fail "Documentation tells users to run './trailmq ${cmd}', which the CLI does not handle"
  unknown=$((unknown + 1))
done < <(grep -rhoE '\./trailmq [a-z][a-z-]*' --include='*.md' . | awk '{print $2}' | sort -u)
[ "${unknown}" -eq 0 ] && pass "Every documented ./trailmq command exists in the CLI"

# A broken relative link in the entry-point documentation strands a first-time
# reader on the exact path this repository exists to provide.
broken=0
while IFS= read -r doc; do
  doc_dir="$(dirname "${doc}")"
  while IFS= read -r target; do
    [ -z "${target}" ] && continue
    target="${target%%#*}"
    [ -z "${target}" ] && continue
    if [ ! -e "${doc_dir}/${target}" ]; then
      fail "Broken relative link in ${doc}" "→ ${target}"
      broken=$((broken + 1))
    fi
  done < <(grep -oE '\]\([^):]+\)' "${doc}" | sed -E 's/^\]\(//; s/\)$//' | grep -v '^#' | sort -u)
done < <(git ls-files '*.md')
[ "${broken}" -eq 0 ] && pass "All relative documentation links resolve"

# A link can resolve in the repository and still be broken in the download,
# because the bundle ships without the development and CI paths. Staging a
# throwaway copy through the same script the builder uses means the bundle is
# checked as a bundle here, at pull-request time, rather than at release time.
bundle_view="$(mktemp -d)"
if git ls-files -z | while IFS= read -r -d '' f; do
  mkdir -p "${bundle_view}/$(dirname "${f}")" && cp -p "${f}" "${bundle_view}/${f}"
done; then
  staged_version="${RELEASE_VERSION:-0.0.0}"
  if ! staging="$(.github/scripts/stage-evaluation-bundle.sh "${bundle_view}" "${staged_version}" 2>&1)"; then
    fail "The evaluation bundle cannot be staged" "${staging}"
  elif ! links="$(.github/scripts/check-bundle-links.sh "${bundle_view}" 2>&1)"; then
    fail "Documentation links that resolve here would break in the bundle" "${links}"
  else
    pass "Bundle documentation is self-contained (${links})"
  fi
fi
rm -rf "${bundle_view}"

# --------------------------------------------------------------------------
section "8. Registry surfaces"
# --------------------------------------------------------------------------
# Docker Hub and GHCR are the first TrailMQ page many people ever see, and for a
# closed-source product they are a trust surface rather than a mirror of the
# README. Their text lives in distribution/registry/ so it can be gated; what
# cannot be gated from here — whether the page was actually updated — belongs to
# the publication stage.
REGISTRY_DIR="distribution/registry"
LABELS_FILE="${REGISTRY_DIR}/oci-labels.yaml"
KNOWN_PLACEHOLDERS="version backend_version frontend_version"

# Components come from the contract, so adding a third published image makes
# its registry surface mandatory without touching this gate.
mapfile -t COMPONENTS < <(
  printf '%s\n' "${CONTRACT_FLAT}" | cut -f1 | sed -n 's/^runtime\.//p' | sort
)

if [ "${#COMPONENTS[@]}" -eq 0 ]; then
  fail "No published components found in the release contract" \
    "expected at least one runtime.* entry"
else
  for component in "${COMPONENTS[@]}"; do
    text="${REGISTRY_DIR}/trailmq-${component}.md"

    if [ ! -f "${text}" ]; then
      fail "${component} is published but has no canonical registry text" \
        "expected ${text}"
      continue
    fi

    # A literal version in registry text is a version nobody updates. This is
    # the whole reason the placeholders exist.
    literal="$(grep -nE '[0-9]+\.[0-9]+\.[0-9]+' "${text}" | head -n3)"
    if [ -n "${literal}" ]; then
      fail "${text} contains a literal version" \
        "use a placeholder instead: $(printf '%s' "${literal}" | tr '\n' ' ')"
    else
      pass "${text} names no literal version"
    fi

    unknown=0
    while IFS= read -r name; do
      [ -z "${name}" ] && continue
      case " ${KNOWN_PLACEHOLDERS} " in
        *" ${name} "*) ;;
        *)
          fail "${text} uses an unknown placeholder" \
            "{{${name}}} — known: ${KNOWN_PLACEHOLDERS}"
          unknown=$((unknown + 1))
          ;;
      esac
    done < <(grep -oE '\{\{[a-z_]+\}\}' "${text}" | sed -E 's/^\{\{|\}\}$//g' | sort -u)
    [ "${unknown}" -eq 0 ] && pass "${text} uses only known placeholders"

    # The rendered page is what a stranger reads, so the gate checks that
    # artifact rather than the template it came from.
    if ! rendered="$(.github/scripts/render-registry.sh text "${component}" 2>&1)"; then
      fail "${component} registry text does not render" "${rendered}"
      continue
    fi

    if [ -n "${RELEASE_VERSION}" ] &&
      printf '%s' "${rendered}" | grep -qF "${RELEASE_VERSION}"; then
      pass "${component} registry text renders naming ${RELEASE_VERSION}"
    else
      fail "${component} registry text renders without naming the release" \
        "expected ${RELEASE_VERSION} to appear once rendered"
    fi

    # One text serves both registries, so it has to point at both. A page that
    # names only Docker Hub is how the GHCR package ends up described
    # differently.
    for registry in "rainergewalt/trailmq-${component}" "ghcr.io/rainergewalt/trailmq-${component}"; do
      if printf '%s' "${rendered}" | grep -qF "${registry}"; then
        pass "${component} registry text names ${registry}"
      else
        fail "${component} registry text does not name ${registry}" \
          "one text serves Docker Hub and GHCR — both pull paths belong in it"
      fi
    done

    if grep -qF "This is a runtime image." "${text}"; then
      pass "${component} registry text separates the runtime image from the evaluation package"
    else
      fail "${component} registry text does not mark the image as a runtime image" \
        "a visitor who starts it standalone gets a broken container, not a product"
    fi
  done

  # The Preview ships exactly these surfaces. Naming one that was removed, or
  # omitting one that shipped, is the stale-surface problem this catches.
  frontend_text="${REGISTRY_DIR}/trailmq-frontend.md"
  if [ -f "${frontend_text}" ]; then
    missing_surface=0
    for surface in Overview Access Clients Activity; do
      grep -qF "${surface}" "${frontend_text}" ||
        {
          fail "Frontend registry text does not name the '${surface}' surface"
          missing_surface=$((missing_surface + 1))
        }
    done
    [ "${missing_surface}" -eq 0 ] &&
      pass "Frontend registry text names all four Preview surfaces"
  fi
fi

# --- OCI labels ------------------------------------------------------------
if [ ! -f "${LABELS_FILE}" ]; then
  fail "${LABELS_FILE} is missing" "the published images have no canonical label set"
elif ! labels_flat="$(scripts/release-contract.sh flatten "${LABELS_FILE}" 2>&1)"; then
  fail "${LABELS_FILE} is not in the documented shape" "${labels_flat}"
else
  pass "${LABELS_FILE} reads in the documented shape"

  for component in "${COMPONENTS[@]}"; do
    if ! emitted="$(.github/scripts/render-registry.sh labels "${component}" 2>&1)"; then
      fail "OCI labels for ${component} do not render" "${emitted}"
      continue
    fi

    missing_label=0
    for label in title description url source documentation vendor licenses \
      version revision created; do
      value="$(printf '%s\n' "${emitted}" |
        sed -n "s|^org\.opencontainers\.image\.${label}=||p" | head -n1)"
      if [ -z "${value}" ]; then
        fail "${component}: OCI label '${label}' is empty or missing"
        missing_label=$((missing_label + 1))
        continue
      fi

      case "${label}" in
        url | source | documentation)
          [[ "${value}" == https://* ]] ||
            {
              fail "${component}: OCI label '${label}' is not an https URL" "got '${value}'"
              missing_label=$((missing_label + 1))
            }
          ;;
        version)
          if [ -n "${RELEASE_VERSION}" ] && [ "${value}" != "${RELEASE_VERSION}" ]; then
            fail "${component}: OCI version label does not name the release" \
              "label '${value}', release ${RELEASE_VERSION}"
            missing_label=$((missing_label + 1))
          fi
          ;;
        licenses)
          # TrailMQ is proprietary. An OSI identifier here would tell every
          # scanner, and every reader, something untrue about what a puller
          # may do with the image.
          case "${value}" in
            MIT | Apache-2.0 | BSD-2-Clause | BSD-3-Clause | ISC | Unlicense | \
              GPL-2.0* | GPL-3.0* | LGPL-* | AGPL-* | MPL-2.0)
              fail "${component}: OCI licenses label claims an open-source license" \
                "got '${value}' — TrailMQ ships under a proprietary evaluation license"
              missing_label=$((missing_label + 1))
              ;;
          esac
          ;;
      esac
    done
    [ "${missing_label}" -eq 0 ] &&
      pass "${component}: OCI labels are complete and consistent with the release"
  done
fi

# --------------------------------------------------------------------------
section "9. Scenario pack"
# --------------------------------------------------------------------------
# Scenarios are the product's explanation format, and the same files are meant
# to drive both the local demo and the website walkthrough. A story that only
# one of them can tell, or that describes behaviour a release no longer has, is
# worse than no story — so the parts that can be checked from here are.
SCENARIO_DIR="scenarios"

if [ ! -d "${SCENARIO_DIR}" ]; then
  skip "no scenario pack in this tree"
else
  mapfile -t SCENARIO_FILES < <(find "${SCENARIO_DIR}" -maxdepth 1 -name '*.json' -type f | sort)

  if [ "${#SCENARIO_FILES[@]}" -eq 0 ]; then
    fail "${SCENARIO_DIR}/ exists but contains no scenarios"
  fi

  for file in "${SCENARIO_FILES[@]}"; do
    name="$(basename "${file}" .json)"

    if ! jq -e . "${file}" >/dev/null 2>&1; then
      fail "${file} is not valid JSON" "$(jq . "${file}" 2>&1 | head -n2)"
      continue
    fi

    # The file name is how the command line names a scenario and how a URL
    # addresses it. Disagreement means one of the two is wrong.
    id="$(jq -r '.id // ""' "${file}")"
    if [ "${id}" != "${name}" ]; then
      fail "${file}: id does not match the file name" "id '${id}', file '${name}'"
    fi

    missing="$(jq -r '
      [ if (.title // "") == "" then "title" else empty end,
        if (.question // "") == "" then "question" else empty end,
        if (.summary // "") == "" then "summary" else empty end,
        if (.compatibleWith // "") == "" then "compatibleWith" else empty end,
        if (.closing.headline // "") == "" then "closing.headline" else empty end,
        if (.closing.explanation // "") == "" then "closing.explanation" else empty end,
        if ((.steps // []) | length) == 0 then "steps" else empty end
      ] | join(", ")' "${file}")"
    if [ -n "${missing}" ]; then
      fail "${file} is missing required fields" "${missing}"
      continue
    fi

    # Every step carries all three disclosure levels. A step with no headline
    # reads as protocol trivia to the audience this exists for; one with no
    # explanation cannot answer the question the scenario claims to answer.
    incomplete="$(jq -r '
      [ .steps[] | select((.headline // "") == "" or (.explanation // "") == "" or (.topic // "") == "")
        | .id // "<no id>" ] | join(", ")' "${file}")"
    if [ -n "${incomplete}" ]; then
      fail "${file}: steps missing a headline, explanation or topic" "${incomplete}"
    fi

    # A step kind the runner does not implement would be silently skipped.
    unknown_kind="$(jq -r '
      [ .steps[] | select((.kind // "") as $k
        | ["publish_denied","publish_delivered","decision_record"] | index($k) | not)
        | "\(.id // "<no id>") (\(.kind // "none"))" ] | join(", ")' "${file}")"
    if [ -n "${unknown_kind}" ]; then
      fail "${file}: steps with an unknown kind" "${unknown_kind}"
    fi

    # Actors are bound to real evaluation identities. A step naming an actor
    # the scenario never defines cannot run.
    if ! dangling="$(jq -er '
      . as $doc
      | (($doc.actors // []) | map(.key)) as $keys
      | [ ($doc.steps // [])[]
          | (.actor // "") as $actor
          | select($actor != "" and ($keys | index($actor) | not))
          | $actor ]
      | unique | join(", ")' "${file}" 2>&1)"; then
      # A query that errors reports nothing, which would look exactly like a
      # scenario with no problem. Treat it as a finding, not as silence.
      fail "${file}: the actor references could not be checked" "${dangling}"
    elif [ -n "${dangling}" ]; then
      fail "${file}: steps refer to actors the scenario does not define" "${dangling}"
    fi

    # The scenario states which runtime it was written against. Letting that
    # fall behind is how a demo starts describing behaviour that changed.
    compatible="$(jq -r '.compatibleWith // ""' "${file}")"
    if [ -n "${RELEASE_VERSION}" ] && [ "${compatible}" != "${RELEASE_VERSION}" ]; then
      fail "${file} was written for another release" \
        "compatibleWith '${compatible}', this release is ${RELEASE_VERSION}"
    else
      pass "${file} is a complete scenario for ${compatible}"
    fi
  done
fi

# --------------------------------------------------------------------------
section "Result"
# --------------------------------------------------------------------------
if [ "${FAILED}" -eq 0 ]; then
  printf "%sPublic distribution gate passed.%s\n" "${C_GREEN}" "${C_RESET}"
  exit 0
fi
printf "%s%s check(s) failed.%s\n" "${C_RED}" "${FAILED}" "${C_RESET}"
exit 1
