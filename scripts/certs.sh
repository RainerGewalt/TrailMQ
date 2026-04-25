#!/usr/bin/env bash
# TrailMQ — generate local demo certificates.
# Self-signed. Local evaluation only. Not for production.
# Can be called directly: ./trailmq certs [recipe-name]

set -euo pipefail

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

# --- Determine target recipe ---
target="${1:-}"
if [ -z "${target}" ]; then
  if has_active_recipe; then
    target="$(cat "${ACTIVE_RECIPE_FILE}")"
  else
    log_err "No active recipe and no recipe argument."
    log_info "Usage: ./trailmq certs [recipe-name]"
    exit 1
  fi
fi

recipe_dir="${TRAILMQ_ROOT}/recipes/${target}"
if [ ! -d "${recipe_dir}" ]; then
  log_err "Recipe folder not found: ${recipe_dir}"
  exit 1
fi

certs_dir="${recipe_dir}/certs"
mkdir -p "${certs_dir}"

# --- openssl guard ---
if ! command -v openssl >/dev/null 2>&1; then
  log_err "openssl not found. Install openssl or provide certs manually in:"
  log_info "  ${certs_dir}/"
  exit 1
fi

# --- Skip if already present ---
if [ -f "${certs_dir}/server_cert.pem" ] && [ -f "${certs_dir}/server_key.pem" ] && [ -f "${certs_dir}/ca_cert.pem" ]; then
  log_info "Certificates already exist in recipes/${target}/certs/"
  printf "Overwrite? [y/N] › "
  read -r answer
  if [ "${answer}" != "y" ] && [ "${answer}" != "Y" ]; then
    log_info "Kept existing certificates."
    exit 0
  fi
fi

log_warn "Generating LOCAL DEMO certificates. Do not use for production."
echo

# --- Work in a temp dir so a failure doesn't leave a half-baked certs/ ---
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# 1) Root CA
log_step "Creating root CA…"
openssl genrsa -out "${tmp}/ca_key.pem" 4096 >/dev/null 2>&1
openssl req -x509 -new -nodes \
  -key "${tmp}/ca_key.pem" \
  -sha256 -days 365 \
  -subj "/CN=TrailMQ Local Demo CA/O=TrailMQ Demo/OU=Local Evaluation" \
  -out "${tmp}/ca_cert.pem" >/dev/null 2>&1
log_ok "Root CA created."

# 2) Server key + CSR
log_step "Creating server key and CSR…"
openssl genrsa -out "${tmp}/server_key.pem" 4096 >/dev/null 2>&1

cat > "${tmp}/server.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = localhost
O  = TrailMQ Demo
OU = Local Evaluation

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = backend
DNS.3 = nginx
DNS.4 = trailmq-backend
DNS.5 = trailmq-reverse-proxy
IP.1  = 127.0.0.1
IP.2  = ::1
EOF

openssl req -new \
  -key "${tmp}/server_key.pem" \
  -out "${tmp}/server.csr" \
  -config "${tmp}/server.cnf" >/dev/null 2>&1

# 3) Sign with CA
log_step "Signing server certificate with local CA…"
openssl x509 -req \
  -in "${tmp}/server.csr" \
  -CA "${tmp}/ca_cert.pem" \
  -CAkey "${tmp}/ca_key.pem" \
  -CAcreateserial \
  -out "${tmp}/server_cert.pem" \
  -days 365 -sha256 \
  -extensions v3_req \
  -extfile "${tmp}/server.cnf" >/dev/null 2>&1
log_ok "Server certificate signed."

# 4) Install into recipe certs/
install -m 0644 "${tmp}/ca_cert.pem"     "${certs_dir}/ca_cert.pem"
install -m 0644 "${tmp}/server_cert.pem" "${certs_dir}/server_cert.pem"
install -m 0600 "${tmp}/server_key.pem"  "${certs_dir}/server_key.pem"

echo
log_ok "${C_BOLD}Generated local demo certificates.${C_RESET} Do not use for production."
log_info "Location: recipes/${target}/certs/"
log_info "Files:    ca_cert.pem, server_cert.pem, server_key.pem (key: 0600)"
log_info "SANs:     localhost, backend, nginx, trailmq-backend, trailmq-reverse-proxy, 127.0.0.1, ::1"
log_info "Validity: 365 days"
