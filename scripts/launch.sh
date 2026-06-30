#!/usr/bin/env bash
# TrailMQ — guided Starter Kit selection and first run.
# Invoked by: ./trailmq quickstart or ./trailmq launch

set -euo pipefail

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

quickstart=false
case "${1:-}" in
  --quickstart|--yes|-y)
    quickstart=true
    shift || true
    ;;
esac

# ------------------------------------------------------------------
# Intro
# ------------------------------------------------------------------
if $quickstart; then
  cat <<EOF

${C_BOLD}TrailMQ Quickstart${C_RESET}

Using ${C_BOLD}Secure MQTT Core${C_RESET} with local demo certificates and
generated local evaluation credentials.

EOF
  recipe="secure-mqtt-core"
else
  cat <<EOF

${C_BOLD}🚀 TrailMQ Launcher${C_RESET}

${C_BOLD}Available now${C_RESET}

  ${C_GREEN}[1]${C_RESET} Secure MQTT Core         ${C_DIM}— policies, audit trail, evidence chain${C_RESET}

${C_BOLD}Preview${C_RESET}  ${C_DIM}(planned for a future release)${C_RESET}

  ${C_DIM}[ ] Explain Decisions        planned${C_RESET}
  ${C_DIM}[ ] Live vs Historical KPI   planned${C_RESET}
  ${C_DIM}[ ] Audit Evidence Demo      planned${C_RESET}

EOF

  printf "Choose a Starter Kit › "
  read -r choice

  case "${choice}" in
    1) recipe="secure-mqtt-core" ;;
    *)
      log_err "Invalid choice. Only option [1] is available right now."
      exit 1
      ;;
  esac
fi

recipe_dir="${TRAILMQ_ROOT}/recipes/${recipe}"
if [ ! -d "${recipe_dir}" ]; then
  log_err "Recipe folder missing: ${recipe_dir}"
  exit 1
fi

echo
log_step "Recipe selected:  ${C_BOLD}${recipe}${C_RESET}"

# ------------------------------------------------------------------
# Prepare runtime folders so bind mounts work on fresh clones
# ------------------------------------------------------------------
mkdir -p \
  "${recipe_dir}/data" \
  "${recipe_dir}/logs" \
  "${recipe_dir}/audit-archive" \
  "${recipe_dir}/certs" \
  "${recipe_dir}/secrets"
log_ok "Runtime folders prepared."

# ------------------------------------------------------------------
# Config check
# ------------------------------------------------------------------
if [ ! -f "${recipe_dir}/config.yaml" ]; then
  log_err "Missing config.yaml in ${recipe_dir}"
  exit 1
fi
log_ok "Config ready: recipes/${recipe}/config.yaml"

# ------------------------------------------------------------------
# Certificates — offer to generate demo certs if missing or incomplete
# ------------------------------------------------------------------
certs_complete=true
for cert_file in server_cert.pem server_key.pem ca_cert.pem; do
  if [ ! -f "${recipe_dir}/certs/${cert_file}" ]; then
    certs_complete=false
    break
  fi
done

if ! $certs_complete; then
  echo
  if $quickstart; then
    log_warn "TLS certificates missing or incomplete. Generating local demo certificates."
    "${TRAILMQ_ROOT}/scripts/certs.sh" "${recipe}"
  else
    log_warn "TLS certificates missing or incomplete."
    cat <<EOF

How should we proceed?

  ${C_GREEN}[1]${C_RESET} Generate local demo certificates  ${C_DIM}(self-signed, local use only)${C_RESET}
  ${C_GREEN}[2]${C_RESET} Use my own certificates           ${C_DIM}(you'll add them manually)${C_RESET}
  ${C_GREEN}[3]${C_RESET} Continue without certificates     ${C_DIM}(backend will fail to start)${C_RESET}

EOF
    printf "Choose › "
    read -r cert_choice

    case "${cert_choice}" in
      1)
        "${TRAILMQ_ROOT}/scripts/certs.sh" "${recipe}"
        ;;
      2)
        log_info "Place these files in recipes/${recipe}/certs/ and re-run './trailmq start':"
        log_info "  - server_cert.pem"
        log_info "  - server_key.pem"
        log_info "  - ca_cert.pem"
        exit 0
        ;;
      3)
        log_warn "Continuing without certificates. Backend will not start."
        ;;
      *)
        log_err "Invalid choice."
        exit 1
        ;;
    esac
  fi
else
  log_ok "Certificates present."
fi

# ------------------------------------------------------------------
# JWT secret
# ------------------------------------------------------------------
if [ ! -f "${recipe_dir}/secrets/jwtsecret.txt" ]; then
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 > "${recipe_dir}/secrets/jwtsecret.txt"
    chmod 600 "${recipe_dir}/secrets/jwtsecret.txt"
    log_ok "JWT secret generated: recipes/${recipe}/secrets/jwtsecret.txt"
  else
    log_warn "openssl not found — cannot generate JWT secret automatically."
    log_info "Create recipes/${recipe}/secrets/jwtsecret.txt manually (>= 32 bytes)."
  fi
else
  log_ok "JWT secret present."
fi

# ------------------------------------------------------------------
# Evaluation user credentials
# Generate once, print once. If the files already exist we leave
# them alone — user can cat them or delete to regenerate.
# ------------------------------------------------------------------
demo_users=(testadmin testuser)
generated_new_creds=false
for user in "${demo_users[@]}"; do
  pwd_file="${recipe_dir}/secrets/${user}.pwd"
  if [ ! -f "${pwd_file}" ]; then
    if command -v openssl >/dev/null 2>&1; then
      # 18 bytes base64 ≈ 24 URL-safe chars. Strip newlines and '+/=' for readability.
      openssl rand -base64 18 | tr -d '\n+/=' | head -c 20 > "${pwd_file}"
      chmod 600 "${pwd_file}"
      generated_new_creds=true
    else
      log_warn "openssl missing — create ${pwd_file} manually (>= 12 chars)."
    fi
  fi
done
if $generated_new_creds; then
  log_ok "Evaluation credentials generated."
fi

# ------------------------------------------------------------------
# Persist active recipe
# ------------------------------------------------------------------
echo "${recipe}" > "${ACTIVE_RECIPE_FILE}"
log_ok "Active recipe set."

# ------------------------------------------------------------------
# Docker check
# ------------------------------------------------------------------
check_docker || exit 1

# ------------------------------------------------------------------
# Deconflict with containers from a previous setup
# ------------------------------------------------------------------
if ! deconflict_container_names "${recipe_dir}"; then
  exit 1
fi

# ------------------------------------------------------------------
# Start stack
# ------------------------------------------------------------------
echo
log_step "Starting stack…"
(cd "${recipe_dir}" && docker compose up -d)
log_ok "Stack is up."

ACTIVE_RECIPE="${recipe}"
export ACTIVE_RECIPE
print_access_points

print_evaluation_credentials "${recipe}"

cat <<EOF

${C_BOLD}Next steps${C_RESET}
  1. Open ${C_CYAN}$(trailmq_http_base_url)/trailmq/${C_RESET} in your browser
  2. Log in as ${C_BOLD}testadmin${C_RESET}
  3. Run ${C_GREEN}./trailmq status${C_RESET} to see service health
  4. Run ${C_GREEN}./trailmq credentials${C_RESET} if you need the login again

EOF
