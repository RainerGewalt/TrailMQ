#!/usr/bin/env bash
# TrailMQ — status. A proud little product-feel dashboard in your terminal.
# Sections: Core → Audit → Plugins → Open.

set -euo pipefail

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

if ! has_active_recipe; then
  log_err "No active recipe. Run './trailmq launch' first."
  exit 1
fi

require_active_recipe
recipe_dir="${TRAILMQ_ROOT}/recipes/${ACTIVE_RECIPE}"

# --- Pretty recipe label (falls back to id) ---
recipe_label="${ACTIVE_RECIPE}"
if [ -f "${recipe_dir}/recipe.yaml" ]; then
  name_line="$(grep -E '^name:' "${recipe_dir}/recipe.yaml" | head -n1 | sed -E 's/^name:[[:space:]]*//')"
  if [ -n "${name_line}" ]; then
    recipe_label="${name_line}"
  fi
fi

# --- Helper: container state of a compose service, empty if not created ---
container_state() {
  local svc="$1"
  compose_cmd ps --format '{{.State}}' "${svc}" 2>/dev/null | head -n1 || true
}

# --- Helper: print a service line "<label>   <state>" padded left ---
print_service() {
  local label="$1" state="$2"
  case "${state}" in
    running)
      printf "${C_GREEN}✓${C_RESET} %-18s %s\n" "${label}" "running"
      ;;
    "")
      printf "${C_DIM}○${C_RESET} %-18s %s\n" "${label}" "not started"
      ;;
    *)
      printf "${C_YELLOW}!${C_RESET} %-18s %s\n" "${label}" "${state}"
      ;;
  esac
}

cat <<EOF

${C_BOLD}TrailMQ Status${C_RESET}
${C_DIM}Recipe: ${recipe_label} (${ACTIVE_RECIPE})${C_RESET}

${C_BOLD}Core${C_RESET}
EOF

print_service "Backend"        "$(container_state backend)"
print_service "Frontend"       "$(container_state frontend)"
print_service "Reverse Proxy"  "$(container_state nginx)"

# --- Audit section ---
# The chain itself runs inside the backend; if the backend is running
# we report it as enabled. Archive file count is a concrete number we
# can always compute.
backend_state="$(container_state backend)"
echo
echo "${C_BOLD}Audit${C_RESET}"
if [ "${backend_state}" = "running" ]; then
  printf "${C_GREEN}✓${C_RESET} %-18s %s\n" "Audit"          "enabled"
  printf "${C_GREEN}✓${C_RESET} %-18s %s\n" "Evidence chain" "enabled"
else
  printf "${C_DIM}○${C_RESET} %-18s %s\n"   "Audit"          "backend not running"
  printf "${C_DIM}○${C_RESET} %-18s %s\n"   "Evidence chain" "backend not running"
fi
if [ -d "${recipe_dir}/audit-archive" ]; then
  archived="$(find "${recipe_dir}/audit-archive" -type f 2>/dev/null | wc -l | tr -d ' ')"
  printf "${C_DIM}○${C_RESET} %-18s %s\n" "Archived files" "${archived}"
fi

# --- Plugins section ---
# Parsed from plugins/catalog.yaml. Everything is "planned" today; we
# still show the list so the extension path is visible.
echo
echo "${C_BOLD}Plugins${C_RESET}"
catalog="${TRAILMQ_ROOT}/plugins/catalog.yaml"
if [ -f "${catalog}" ]; then
  awk '
    /^[[:space:]]*-[[:space:]]*id:/          { id=$0 }
    /^[[:space:]]*name:/                     { name=$0 }
    /^[[:space:]]*status:/ {
      sub(/^[[:space:]]*status:[[:space:]]*/, "", $0); status=$0
      sub(/^[[:space:]]*name:[[:space:]]*/, "", name)
      printf "%s|%s\n", name, status
      id=""; name=""; status=""
    }
  ' "${catalog}" | while IFS='|' read -r name status; do
    case "${status}" in
      available) printf "${C_GREEN}✓${C_RESET} %-28s %s\n" "${name}" "available" ;;
      beta)      printf "${C_YELLOW}!${C_RESET} %-28s %s\n" "${name}" "beta" ;;
      planned)   printf "${C_DIM}○${C_RESET} %-28s ${C_DIM}%s${C_RESET}\n" "${name}" "planned" ;;
      *)         printf "  %-28s %s\n" "${name}" "${status}" ;;
    esac
  done
else
  log_skip "No plugin catalog found."
fi

# --- Open section (access points) ---
echo
echo "${C_BOLD}Open${C_RESET}"
printf "  %-12s %s\n" "Web UI"   "${C_CYAN}http://localhost/trailmq/${C_RESET}"
printf "  %-12s %s\n" "REST API" "${C_CYAN}http://localhost/api${C_RESET}"
printf "  %-12s %s\n" "MQTT TLS" "${C_CYAN}localhost:8883${C_RESET}"
printf "  %-12s %s\n" "MQTT WS"  "${C_CYAN}ws://localhost/mqtt${C_RESET}"

echo
