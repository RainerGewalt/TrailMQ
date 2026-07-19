#!/usr/bin/env bash
# TrailMQ — guided demo against the running local stack.
# Shows one allowed MQTT delivery and one denied publish, then points to
# the recorded evidence. Non-interactive; exits non-zero if the allowed
# path does not deliver.
#
# Uses local mosquitto clients when available, otherwise falls back to a
# dockerized client (eclipse-mosquitto) on the stack's network.

set -euo pipefail

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

require_active_recipe
check_docker || exit 1

recipe_dir="${TRAILMQ_ROOT}/recipes/${ACTIVE_RECIPE}"
ca_file="${recipe_dir}/certs/ca_cert.pem"

# ------------------------------------------------------------------
# Preconditions: stack running, credentials present
# ------------------------------------------------------------------
if ! docker container inspect trailmq-backend >/dev/null 2>&1; then
  log_err "Backend container not found. Start the stack first: ./trailmq start"
  exit 1
fi
if [ "$(docker container inspect -f '{{.State.Running}}' trailmq-backend)" != "true" ]; then
  log_err "Backend container is not running. Check './trailmq status' and './trailmq logs backend'."
  exit 1
fi

admin_pw_file="${recipe_dir}/secrets/testadmin.pwd"
user_pw_file="${recipe_dir}/secrets/testuser.pwd"
for f in "${admin_pw_file}" "${user_pw_file}" "${ca_file}"; do
  if [ ! -s "$f" ]; then
    log_err "Missing $f — run './trailmq start' first."
    exit 1
  fi
done
ADMIN_PW="$(cat "${admin_pw_file}")"
USER_PW="$(cat "${user_pw_file}")"

log_step "Waiting for the backend to be ready…"
ready=false
for _ in $(seq 1 30); do
  if docker exec trailmq-backend wget -qO- http://localhost:8443/ready >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if ! $ready; then
  log_err "Backend did not report ready. Check './trailmq logs backend'."
  exit 1
fi
log_ok "Backend is ready."

# ------------------------------------------------------------------
# Client tooling: local mosquitto clients or dockerized fallback
# ------------------------------------------------------------------
use_docker_client=false
if ! command -v mosquitto_pub >/dev/null 2>&1 || ! command -v mosquitto_sub >/dev/null 2>&1; then
  use_docker_client=true
  stack_net="$(docker container inspect trailmq-backend \
    -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null)"
  if [ -z "${stack_net}" ]; then
    log_err "Could not determine the stack's Docker network."
    exit 1
  fi
  log_info "mosquitto clients not found locally — using a dockerized client (eclipse-mosquitto)."
fi

mqtt_host() { $use_docker_client && printf 'backend' || printf 'localhost'; }
mqtt_ca()   { $use_docker_client && printf '/demo-certs/ca_cert.pem' || printf '%s' "${ca_file}"; }

mq() {
  # mq <pub|sub> <args…>
  local tool="mosquitto_$1"
  shift
  if $use_docker_client; then
    docker run --rm --network "${stack_net}" \
      -v "${recipe_dir}/certs:/demo-certs:ro" \
      eclipse-mosquitto:2 "${tool}" "$@"
  else
    "${tool}" "$@"
  fi
}

# ------------------------------------------------------------------
# Step 1 — allowed delivery through the public/ namespace
# ------------------------------------------------------------------
cat <<EOF

${C_BOLD}TrailMQ Demo${C_RESET} — two minutes, two decisions

${C_BOLD}Step 1: an allowed delivery${C_RESET}
  ${C_DIM}testuser (role: publisher) publishes to public/demo/temperature.
  testadmin subscribes. The public/ namespace is open to all roles.${C_RESET}

EOF

sub_out="$(mktemp)"
trap 'rm -f "${sub_out}"' EXIT

mq sub -h "$(mqtt_host)" -p 8883 --cafile "$(mqtt_ca)" \
  -u testadmin -P "${ADMIN_PW}" \
  -i trailmq-demo-dashboard \
  -t 'public/#' -T 'trailmq/#' -C 1 -W 15 -v > "${sub_out}" 2>/dev/null &
sub_pid=$!
sleep 2

payload="{\"value\":21.4,\"unit\":\"degC\",\"demo\":\"$(date +%H:%M:%S)\"}"
if mq pub -h "$(mqtt_host)" -p 8883 --cafile "$(mqtt_ca)" \
  -u testuser -P "${USER_PW}" \
  -i trailmq-demo-sensor \
  -t 'public/demo/temperature' -q 1 -m "${payload}" 2>/dev/null; then
  log_ok "Publish accepted (QoS 1, TLS, authenticated as testuser)."
else
  log_err "Publish failed — check './trailmq logs backend'."
  exit 1
fi

wait "${sub_pid}" 2>/dev/null || true
if grep -qF "${payload}" "${sub_out}"; then
  log_ok "Subscriber received it:"
  printf '    %s\n' "$(cat "${sub_out}")"
else
  log_err "Subscriber did not receive the message. Check './trailmq logs backend'."
  exit 1
fi

# ------------------------------------------------------------------
# Step 2 — denied publish into the restricted/ namespace
# ------------------------------------------------------------------
cat <<EOF

${C_BOLD}Step 2: a denied publish${C_RESET}
  ${C_DIM}The same testuser now publishes to restricted/ops/config.
  That namespace is admin-only — TrailMQ fails closed.${C_RESET}

EOF

if mq pub -h "$(mqtt_host)" -p 8883 --cafile "$(mqtt_ca)" \
  -u testuser -P "${USER_PW}" \
  -i trailmq-demo-sensor \
  -t 'restricted/ops/config' -q 1 -m 'should-not-arrive' >/dev/null 2>&1; then
  log_warn "Expected a denial, but the publish was accepted. Check the ACL configuration."
else
  log_ok "Denied. The broker refused the QoS 1 publish and closed the connection."
fi

deny_line="$(docker logs trailmq-backend --since 2m 2>&1 \
  | grep -F '[ACLMon] DENY' | grep -F 'restricted/ops/config' | tail -n 1 || true)"
if [ -n "${deny_line}" ]; then
  log_info "Broker decision record:"
  printf '    %s\n' "${deny_line#*] }"
fi

# ------------------------------------------------------------------
# Wrap up
# ------------------------------------------------------------------
cat <<EOF

${C_BOLD}What just happened${C_RESET}
  Both decisions — the allowed delivery and the denial — are recorded.

  1. Open ${C_CYAN}$(trailmq_http_base_url)/trailmq/${C_RESET} and log in as ${C_BOLD}testadmin${C_RESET}
     (password: ./trailmq credentials)
  2. Open ${C_BOLD}Evidence${C_RESET} — the recorded event timeline
  3. Filter ${C_BOLD}Outcome → Blocked${C_RESET} to see the denied publish as a recorded event

${C_BOLD}Go deeper${C_RESET}
  docs/scenarios/          six guided walkthroughs (allow, deny, govern, tamper, users, queues)
  docs/connect-a-client.md connect your own MQTT client

EOF
