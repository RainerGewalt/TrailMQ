#!/usr/bin/env bash
# Shared helpers for TrailMQ CLI scripts.
# Sourced by ./trailmq and all scripts in scripts/.
# shellcheck disable=SC2034  # colors are used by sourcing scripts

# --- Colors ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET="" ; C_DIM="" ; C_BOLD="" ; C_RED="" ; C_GREEN="" ; C_YELLOW="" ; C_BLUE="" ; C_CYAN=""
fi

log_info() { printf "%s\n" "$*"; }
log_step() { printf "${C_CYAN}→${C_RESET} %s\n" "$*"; }
log_ok()   { printf "${C_GREEN}✓${C_RESET} %s\n" "$*"; }
log_warn() { printf "${C_YELLOW}!${C_RESET} %s\n" "$*"; }
log_err()  { printf "${C_RED}✗${C_RESET} %s\n" "$*" 1>&2; }
log_skip() { printf "${C_DIM}○${C_RESET} %s\n" "$*"; }

# --- Paths ---
: "${TRAILMQ_ROOT:?TRAILMQ_ROOT must be set by the caller}"
TRAILMQ_STATE_DIR="${TRAILMQ_ROOT}/.trailmq"
ACTIVE_RECIPE_FILE="${TRAILMQ_STATE_DIR}/active-recipe"

mkdir -p "${TRAILMQ_STATE_DIR}"

# Load .env if present (silently — it's optional).
if [ -f "${TRAILMQ_ROOT}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${TRAILMQ_ROOT}/.env"
  set +a
fi

TRAILMQ_HTTP_PORT="${TRAILMQ_HTTP_PORT:-80}"
TRAILMQ_MQTT_TLS_PORT="${TRAILMQ_MQTT_TLS_PORT:-8883}"

trailmq_http_base_url() {
  if [ "${TRAILMQ_HTTP_PORT}" = "80" ]; then
    printf "http://localhost"
  else
    printf "http://localhost:%s" "${TRAILMQ_HTTP_PORT}"
  fi
}

trailmq_ws_url() {
  if [ "${TRAILMQ_HTTP_PORT}" = "80" ]; then
    printf "ws://localhost/mqtt"
  else
    printf "ws://localhost:%s/mqtt" "${TRAILMQ_HTTP_PORT}"
  fi
}

trailmq_mqtt_tls_address() {
  printf "localhost:%s" "${TRAILMQ_MQTT_TLS_PORT}"
}

print_evaluation_credentials() {
  local recipe="${1:-${ACTIVE_RECIPE:-}}"
  if [ -z "${recipe}" ]; then
    log_err "No recipe selected."
    return 1
  fi

  local recipe_dir="${TRAILMQ_ROOT}/recipes/${recipe}"
  if [ ! -d "${recipe_dir}" ]; then
    log_err "Recipe folder not found: recipes/${recipe}"
    return 1
  fi

  cat <<EOF

${C_BOLD}Evaluation login${C_RESET}  ${C_DIM}(local use only)${C_RESET}
EOF

  local found=false
  local user pwd_file
  for user in testadmin testuser; do
    pwd_file="${recipe_dir}/secrets/${user}.pwd"
    if [ -s "${pwd_file}" ]; then
      printf "  %-12s  %s\n" "${user}" "$(cat "${pwd_file}")"
      found=true
    else
      printf "  %-12s  %s\n" "${user}" "${C_DIM}missing: recipes/${recipe}/secrets/${user}.pwd${C_RESET}"
    fi
  done

  if ! $found; then
    echo
    log_info "Run './trailmq quickstart' to generate local evaluation passwords."
  fi
}

# --- Recipe helpers ---

require_active_recipe() {
  if [ ! -f "${ACTIVE_RECIPE_FILE}" ]; then
    log_err "No active recipe. Run './trailmq quickstart' first."
    exit 1
  fi
  ACTIVE_RECIPE="$(cat "${ACTIVE_RECIPE_FILE}")"
  if [ -z "${ACTIVE_RECIPE}" ] || [ ! -d "${TRAILMQ_ROOT}/recipes/${ACTIVE_RECIPE}" ]; then
    log_err "Active recipe '${ACTIVE_RECIPE}' not found in recipes/."
    exit 1
  fi
  export ACTIVE_RECIPE
}

has_active_recipe() {
  [ -f "${ACTIVE_RECIPE_FILE}" ] && [ -s "${ACTIVE_RECIPE_FILE}" ]
}

compose_cmd() {
  require_active_recipe >/dev/null || true
  local recipe_dir="${TRAILMQ_ROOT}/recipes/${ACTIVE_RECIPE}"
  (cd "${recipe_dir}" && docker compose "$@")
}

check_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    log_err "Docker not found. Install Docker 20.10+ and try again."
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    log_err "Docker Compose v2 not found. Run 'docker compose version' to check."
    return 1
  fi
  return 0
}

deconflict_container_names() {
  local recipe_dir="$1"

  if ! command -v docker >/dev/null 2>&1; then
    return 0
  fi

  local our_project="${COMPOSE_PROJECT_NAME:-}"
  if [ -z "${our_project}" ]; then
    our_project="$(basename "${recipe_dir}")"
    our_project="$(printf '%s' "${our_project}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"
  fi

  local reserved=(trailmq-backend trailmq-frontend trailmq-reverse-proxy)
  local foreign_names=()
  local foreign_projects=()

  for name in "${reserved[@]}"; do
    if docker container inspect "${name}" >/dev/null 2>&1; then
      local project=""
      project="$(docker container inspect \
        -f '{{ index .Config.Labels "com.docker.compose.project" }}' \
        "${name}" 2>/dev/null || true)"
      if [ "${project}" != "${our_project}" ]; then
        foreign_names+=("${name}")
        foreign_projects+=("${project:-<untracked>}")
      fi
    fi
  done

  if [ ${#foreign_names[@]} -eq 0 ]; then
    return 0
  fi

  echo
  log_warn "Found existing containers that share TrailMQ's reserved names:"
  local i=0
  while [ "${i}" -lt "${#foreign_names[@]}" ]; do
    printf "    %s  ${C_DIM}(compose project: %s)${C_RESET}\n" \
      "${foreign_names[$i]}" "${foreign_projects[$i]}"
    i=$((i + 1))
  done
  echo
  log_info "These will conflict with the new stack. Bind-mounted data (DB,"
  log_info "logs, certs) stays on disk — only the container hulls are removed."
  printf "\nRemove them and continue? [y/N] › "
  read -r answer
  if [ "${answer}" = "y" ] || [ "${answer}" = "Y" ]; then
    for name in "${foreign_names[@]}"; do
      if docker rm -f "${name}" >/dev/null 2>&1; then
        log_ok "Removed ${name}"
      else
        log_err "Failed to remove ${name}"
        return 1
      fi
    done
    return 0
  fi
  log_err "Aborted due to name conflict. Run the command again when ready."
  return 1
}

print_access_points() {
  require_active_recipe >/dev/null || return 0
  cat <<EOF

${C_BOLD}Open TrailMQ${C_RESET}
  Web UI    ${C_CYAN}$(trailmq_http_base_url)/trailmq/${C_RESET}
  REST API  ${C_CYAN}$(trailmq_http_base_url)/api/v1${C_RESET}
  MQTT TLS  ${C_CYAN}$(trailmq_mqtt_tls_address)${C_RESET}
  MQTT WS   ${C_CYAN}$(trailmq_ws_url)${C_RESET}

${C_DIM}Active recipe: ${ACTIVE_RECIPE}${C_RESET}
EOF
}

print_menu() {
  cat <<EOF
${C_BOLD}TrailMQ${C_RESET} — an MQTT broker that decides, enforces and records

${C_BOLD}Usage${C_RESET}
  ./trailmq <command>

${C_BOLD}Start here${C_RESET}
  ${C_GREEN}quickstart${C_RESET}   Set up and start the local evaluation stack
  ${C_GREEN}verify${C_RESET}       Prove it: allowed delivery, blocked publish, audit chain
  ${C_GREEN}open${C_RESET}         Show the local URLs
  ${C_GREEN}reset${C_RESET}        Stop the stack and wipe runtime data

${C_BOLD}Advanced${C_RESET}
  ${C_DIM}start${C_RESET}        Start or repair the setup (same as quickstart)
  ${C_DIM}launch${C_RESET}       Guided setup — pick a Starter Kit
  ${C_DIM}up / down${C_RESET}    Start / stop the active recipe
  ${C_DIM}status${C_RESET}       Show services, ports and audit status
  ${C_DIM}credentials${C_RESET}  Show the generated evaluation passwords
  ${C_DIM}logs${C_RESET}         Tail logs for the active recipe
  ${C_DIM}doctor${C_RESET}       Check Docker, ports, certs, config
  ${C_DIM}certs${C_RESET}        Generate local demo certificates
  ${C_DIM}purge${C_RESET}        Remove everything generated for the recipe
  ${C_DIM}version${C_RESET}      Show version info

${C_BOLD}First time here?${C_RESET}
  ./trailmq quickstart && ./trailmq verify
EOF
}
