#!/usr/bin/env bash
# TrailMQ — doctor. Runs a series of sanity checks.
# Zero exit only if blocking checks fail.

set -uo pipefail

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

problems=0

cat <<EOF

${C_BOLD}TrailMQ Doctor${C_RESET}

EOF

# --- 1. Docker ---
if command -v docker >/dev/null 2>&1; then
  docker_ver="$(docker --version 2>/dev/null | head -n1)"
  log_ok "Docker installed       ${C_DIM}(${docker_ver})${C_RESET}"
else
  log_err "Docker installed       (missing — install Docker 20.10+)"
  problems=$((problems + 1))
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  compose_ver="$(docker compose version --short 2>/dev/null || echo "unknown")"
  log_ok "Docker Compose v2      ${C_DIM}(${compose_ver})${C_RESET}"
else
  log_err "Docker Compose v2      (missing — 'docker compose' not recognized)"
  problems=$((problems + 1))
fi

# --- 2. Active recipe ---
if has_active_recipe; then
  ACTIVE_RECIPE="$(cat "${ACTIVE_RECIPE_FILE}")"
  recipe_dir="${TRAILMQ_ROOT}/recipes/${ACTIVE_RECIPE}"
  if [ -d "${recipe_dir}" ]; then
    log_ok "Active recipe          ${C_DIM}(${ACTIVE_RECIPE})${C_RESET}"
  else
    log_err "Active recipe          (set to '${ACTIVE_RECIPE}' but folder missing)"
    problems=$((problems + 1))
    echo
    log_err "Cannot run further checks without a valid recipe."
    exit 1
  fi
else
  log_warn "Active recipe          (none — run './trailmq quickstart')"
  echo
  log_info "Doctor stops here. Run './trailmq quickstart' and re-run './trailmq doctor'."
  exit 1
fi

# --- 3. Config file ---
if [ -f "${recipe_dir}/config.yaml" ]; then
  log_ok "Config file exists     ${C_DIM}(recipes/${ACTIVE_RECIPE}/config.yaml)${C_RESET}"
else
  log_err "Config file exists     (missing — recipes/${ACTIVE_RECIPE}/config.yaml)"
  problems=$((problems + 1))
fi

# --- 4. Certs ---
certs_ok=true
for f in server_cert.pem server_key.pem ca_cert.pem; do
  if [ ! -f "${recipe_dir}/certs/${f}" ]; then
    certs_ok=false
    break
  fi
done
if $certs_ok; then
  log_ok "TLS certificates       ${C_DIM}(recipes/${ACTIVE_RECIPE}/certs/)${C_RESET}"
else
  log_err "TLS certificates       (missing — run './trailmq certs' to generate demo certs)"
  problems=$((problems + 1))
fi

# --- 5. Secrets ---
if [ -f "${recipe_dir}/secrets/jwtsecret.txt" ] && [ -s "${recipe_dir}/secrets/jwtsecret.txt" ]; then
  log_ok "JWT secret             ${C_DIM}(recipes/${ACTIVE_RECIPE}/secrets/jwtsecret.txt)${C_RESET}"
else
  log_err "JWT secret             (missing or empty)"
  problems=$((problems + 1))
fi

# --- 5b. Evaluation credentials ---
creds_ok=true
for user in testadmin testuser; do
  if [ ! -s "${recipe_dir}/secrets/${user}.pwd" ]; then
    creds_ok=false
    break
  fi
done
if $creds_ok; then
  log_ok "Evaluation credentials ${C_DIM}(recipes/${ACTIVE_RECIPE}/secrets/{testadmin,testuser}.pwd)${C_RESET}"
else
  log_warn "Evaluation credentials (missing — './trailmq quickstart' will generate them)"
fi

# --- 5c. Referenced password files ---
if [ -f "${recipe_dir}/config.yaml" ]; then
  missing_pw_files=0

  while IFS= read -r ref; do
    ref="$(printf '%s' "$ref" | sed -E 's/[[:space:]]+#.*$//' | tr -d "\"'")"
    [ -z "$ref" ] && continue

    if [[ "$ref" == /app/* ]]; then
      host_path="${recipe_dir}/${ref#/app/}"
    elif [[ "$ref" == /* ]]; then
      host_path="$ref"
    else
      host_path="${recipe_dir}/${ref#./}"
    fi

    if [ ! -f "$host_path" ]; then
      log_err "Password file missing  ${C_DIM}(${ref})${C_RESET}"
      missing_pw_files=$((missing_pw_files + 1))
    fi
  done < <(grep -E '^[[:space:]]*password_file:[[:space:]]*' "${recipe_dir}/config.yaml" | sed -E 's/^[[:space:]]*password_file:[[:space:]]*//')

  if [ "$missing_pw_files" -eq 0 ]; then
    log_ok "Password files         ${C_DIM}(all referenced files exist)${C_RESET}"
  else
    problems=$((problems + missing_pw_files))
  fi
fi

# --- 6. LICENSE file ---
if [ -f "${TRAILMQ_ROOT}/LICENSE" ]; then
  log_ok "LICENSE file           ${C_DIM}(repo root)${C_RESET}"
else
  log_warn "LICENSE file           (missing at repo root)"
fi

# --- 7. Plaintext passwords in config ---
if [ -f "${recipe_dir}/config.yaml" ]; then
  # shellcheck disable=SC2126
  risky_pw="$(grep -E '^[[:space:]]*password:[[:space:]]+[^[:space:]]' "${recipe_dir}/config.yaml" \
               | grep -vE '^[[:space:]]*password:[[:space:]]+CHANGE_ME[[:space:]]*$' \
               | wc -l | tr -d ' ')"
  if [ "${risky_pw}" -eq 0 ]; then
    log_ok "No plaintext passwords ${C_DIM}(in config.yaml)${C_RESET}"
  else
    log_warn "Plaintext passwords    (${risky_pw} line(s) in config.yaml — consider password_file/password_hash)"
  fi
fi

# --- 8. Ports free? ---
check_port() {
  local port="$1"
  local label="$2"
  if command -v ss >/dev/null 2>&1; then
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"; then
      log_warn "Port ${port} in use     ${C_DIM}(${label} may conflict or TrailMQ already runs)${C_RESET}"
      return 1
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"${port}" -sTCP:LISTEN -P -n >/dev/null 2>&1; then
      log_warn "Port ${port} in use     ${C_DIM}(${label} may conflict or TrailMQ already runs)${C_RESET}"
      return 1
    fi
  else
    return 0
  fi
  log_ok "Port ${port} free      ${C_DIM}(${label})${C_RESET}"
  return 0
}

check_port "${TRAILMQ_HTTP_PORT}" "HTTP / Web UI / REST API" || true
check_port "${TRAILMQ_MQTT_TLS_PORT}" "MQTT TLS" || true

# --- 9. Summary ---
echo
if [ "${problems}" -eq 0 ]; then
  log_ok "${C_BOLD}All blocking checks passed.${C_RESET}"
  exit 0
else
  log_err "${C_BOLD}${problems} blocking check(s) failed.${C_RESET}"
  exit 1
fi
