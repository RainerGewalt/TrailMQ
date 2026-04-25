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

# --- Recipe helpers ---

require_active_recipe() {
  if [ ! -f "${ACTIVE_RECIPE_FILE}" ]; then
    log_err "No active recipe. Run './trailmq launch' first."
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
  Web UI    ${C_CYAN}http://localhost/trailmq/${C_RESET}
  REST API  ${C_CYAN}http://localhost/api${C_RESET}
  MQTT TLS  ${C_CYAN}localhost:8883${C_RESET}
  MQTT WS   ${C_CYAN}ws://localhost/mqtt${C_RESET}

${C_DIM}Active recipe: ${ACTIVE_RECIPE}${C_RESET}
EOF
}

print_menu() {
  cat <<EOF
${C_BOLD}TrailMQ${C_RESET} — audit-first MQTT control plane

${C_BOLD}Usage${C_RESET}
  ./trailmq <command>

${C_BOLD}Commands${C_RESET}
  ${C_GREEN}launch${C_RESET}     Guided setup — pick a Starter Kit and start
  ${C_GREEN}up${C_RESET}         Start the active recipe
  ${C_GREEN}down${C_RESET}       Stop the active recipe
  ${C_GREEN}status${C_RESET}     Show services, ports and audit status
  ${C_GREEN}logs${C_RESET}       Tail logs for the active recipe
  ${C_GREEN}doctor${C_RESET}     Check Docker, ports, certs, config
  ${C_GREEN}certs${C_RESET}      Generate local demo certificates
  ${C_GREEN}demo${C_RESET}       Run a guided demo (coming soon)
  ${C_GREEN}reset${C_RESET}      Stop stack and wipe runtime data
  ${C_GREEN}purge${C_RESET}      Remove stack, runtime data, certs, secrets and active recipe
  ${C_GREEN}version${C_RESET}    Show version info

${C_BOLD}First time here?${C_RESET}
  ./trailmq launch
EOF
}
