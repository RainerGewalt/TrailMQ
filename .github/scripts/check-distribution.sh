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
section "3. Image references and version consistency"
# --------------------------------------------------------------------------
# The Compose default for the backend is the single source of truth: it is what
# a user who sets no environment variable actually pulls.
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
  else
    fail "${dir}: backend default image is not a pinned trailmq-backend tag" "got '${backend_image}'"
  fi

  if [ -n "${CANONICAL_VERSION}" ] &&
    [ "${frontend_image}" = "rainergewalt/trailmq-frontend:${CANONICAL_VERSION}" ]; then
    pass "${dir}: frontend default matches the backend release (${CANONICAL_VERSION})"
  else
    fail "${dir}: frontend default does not match the backend release" \
      "frontend '${frontend_image}', expected 'rainergewalt/trailmq-frontend:${CANONICAL_VERSION}'"
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

if [ -z "${CANONICAL_VERSION}" ]; then
  fail "Could not determine the canonical release version from Compose"
else
  # Every place that names a TrailMQ image must name the release the recipe
  # actually pulls. Two paths are excluded on purpose: .env.example documents
  # pinning to an older published release, which is a supported user action
  # rather than drift, and .github/scripts holds the deliberate counter-examples
  # the negative controls inject.
  drift=0
  while IFS= read -r hit; do
    file="${hit%%:*}"
    tag="${hit##*:}"
    if [ "${tag}" != "${CANONICAL_VERSION}" ]; then
      fail "Stale TrailMQ image reference in ${file}" "${hit}"
      drift=$((drift + 1))
    fi
  done < <(
    git grep -oE 'rainergewalt/trailmq-(backend|frontend):[0-9][A-Za-z0-9._-]*' -- \
      . ':(exclude).env.example' ':(exclude).github/scripts'
  )
  if [ "${drift}" -eq 0 ]; then
    # This scan already covers ./trailmq, which prints these same defaults for
    # './trailmq version' — no separate check is needed for the CLI.
    pass "All TrailMQ image references name ${CANONICAL_VERSION}"
  fi

  badge="$(sed -nE 's@.*img\.shields\.io/badge/published%20release-([^-]+)-.*@\1@p' README.md | head -n1)"
  if [ "${badge}" = "${CANONICAL_VERSION}" ]; then
    pass "README release badge names ${CANONICAL_VERSION}"
  else
    fail "README release badge does not name the shipped release" \
      "badge '${badge}', Compose default '${CANONICAL_VERSION}'"
  fi

fi

# --------------------------------------------------------------------------
section "4. Port and proxy wiring"
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
section "5. Hardened deployment invariants (declared configuration)"
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
section "6. Documented first run is still possible"
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

# --------------------------------------------------------------------------
section "Result"
# --------------------------------------------------------------------------
if [ "${FAILED}" -eq 0 ]; then
  printf "%sPublic distribution gate passed.%s\n" "${C_GREEN}" "${C_RESET}"
  exit 0
fi
printf "%s%s check(s) failed.%s\n" "${C_RED}" "${FAILED}" "${C_RESET}"
exit 1
