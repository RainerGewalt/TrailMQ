#!/usr/bin/env bash
# TrailMQ — everything an MQTT client needs, on one screen.
# Invoked by: ./trailmq connect
#
# This command creates nothing. Every value below is read from the state the
# launcher already produced — generated passwords in the recipe's secrets/,
# the demo CA in its certs/, and the host ports resolved by common.sh from
# .env. That is deliberate: a second source of connection settings is a second
# thing that can disagree with the running stack.
#
# It also hands the user the two topics that demonstrate the product before
# they have read anything about roles or namespaces: one that is allowed and
# one that is refused, with the reason.
#
# The passwords printed here are local evaluation credentials, and printing
# them is the point — a client cannot connect without them. But this output is
# also exactly what people paste into an issue or leave on screen while
# recording. '--redact' (or TRAILMQ_REDACT=1) keeps the layout and replaces
# every secret with a placeholder, so the same command is safe to show.

set -uo pipefail

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

redact=false
if [ "${TRAILMQ_REDACT:-}" = "1" ]; then
  redact=true
fi
while [ $# -gt 0 ]; do
  case "$1" in
    --redact) redact=true ; shift ;;
    *) shift ;;
  esac
done

require_active_recipe

recipe_dir="${TRAILMQ_ROOT}/recipes/${ACTIVE_RECIPE}"
ca_file="$(trailmq_ca_path "${ACTIVE_RECIPE}")"
mqtt_port="${TRAILMQ_MQTT_TLS_PORT}"

read_secret() {
  local file="${recipe_dir}/secrets/$1.pwd"
  if $redact; then
    printf '<%s password — run without --redact>' "$1"
  elif [ -s "${file}" ]; then
    cat "${file}"
  else
    printf '<run ./trailmq try first>'
  fi
}

user_pw="$(read_secret testuser)"
admin_pw="$(read_secret testadmin)"

# Not fatal — the settings are still correct and worth showing, the user just
# cannot connect with them yet. Saying so up front beats a refused TCP connect.
stack_running=true
if ! docker container inspect trailmq-backend >/dev/null 2>&1 ||
  [ "$(docker container inspect -f '{{.State.Running}}' trailmq-backend 2>/dev/null)" != "true" ]; then
  stack_running=false
fi

cat <<EOF

${C_BOLD}Connect your MQTT client${C_RESET}
${C_DIM}Everything below is live configuration of the running evaluation.${C_RESET}
EOF

if ! $stack_running; then
  echo
  log_warn "TrailMQ is not running right now — start it with './trailmq try'."
fi

cat <<EOF

${C_BOLD}Endpoint${C_RESET}
  Host        localhost
  Port        ${mqtt_port}
  Protocol    MQTT over TLS ${C_DIM}(TLS 1.3, server-authenticated)${C_RESET}
  CA cert     ${ca_file}

${C_BOLD}Credentials${C_RESET}  ${C_DIM}(generated locally, for this evaluation only)${C_RESET}
  ${C_BOLD}testuser${C_RESET}    ${user_pw}
              ${C_DIM}role: publisher — start here, this is the interesting one${C_RESET}
  testadmin   ${admin_pw}
              ${C_DIM}role: admin — use it to subscribe and to log into the Web UI${C_RESET}

${C_BOLD}Two topics that show what TrailMQ does${C_RESET}  ${C_DIM}(as testuser)${C_RESET}
  ${C_GREEN}✓${C_RESET} public/demo/temperature
    ${C_DIM}allowed — public/# is open to every known role${C_RESET}
  ${C_RED}✕${C_RESET} restricted/ops/config
    ${C_DIM}denied — restricted/# is admin-only, and testuser is not an admin${C_RESET}

  ${C_DIM}The denial is the point. It is a recorded decision, not a dropped packet:
  Web UI → Activity → filter Outcome: Denied.${C_RESET}
EOF

if [ ! -s "${ca_file}" ]; then
  echo
  log_warn "CA certificate not found at the path above."
  log_info "Run './trailmq try' (or './trailmq certs ${ACTIVE_RECIPE}') to generate it."
fi

cat <<EOF

${C_BOLD}MQTT Explorer${C_RESET}  ${C_DIM}(Connections → + → these fields)${C_RESET}
  Name                     TrailMQ
  Protocol                 mqtt://
  Host / Port              localhost / ${mqtt_port}
  Validate certificate     on
  Encryption (tls)         on
  Username / Password      testuser / ${user_pw}
  Advanced → Certificates → CA certificate
                           ${ca_file}

${C_DIM}Subscribe to public/# and publish to public/demo/temperature — then try
restricted/ops/config and watch it refuse.${C_RESET}

${C_BOLD}mosquitto${C_RESET}  ${C_DIM}(copy-paste, two terminals)${C_RESET}

  ${C_DIM}# 1 — watch, as admin${C_RESET}
  mosquitto_sub -h localhost -p ${mqtt_port} --cafile '${ca_file}' \\
    -u testadmin -P '${admin_pw}' -t 'public/#' -v

  ${C_DIM}# 2 — allowed publish, as testuser${C_RESET}
  mosquitto_pub -h localhost -p ${mqtt_port} --cafile '${ca_file}' \\
    -u testuser -P '${user_pw}' \\
    -t 'public/demo/temperature' -m '{"value":21.4,"unit":"degC"}'

  ${C_DIM}# 3 — denied publish, as testuser (this one is supposed to fail)${C_RESET}
  mosquitto_pub -h localhost -p ${mqtt_port} --cafile '${ca_file}' \\
    -u testuser -P '${user_pw}' \\
    -t 'restricted/ops/config' -q 1 -m 'should-not-arrive'

${C_BOLD}Web UI and API${C_RESET}
  Web UI      $(trailmq_http_base_url)/trailmq/  ${C_DIM}(log in as testadmin)${C_RESET}
  REST API    $(trailmq_http_base_url)/api/v1
  MQTT WS     $(trailmq_ws_url)

${C_BOLD}Other clients${C_RESET}
  ${C_DIM}Python (paho-mqtt), Node.js (mqtt.js) and browser WebSocket examples:${C_RESET}
  docs/connect-a-client.md

EOF

if ! $redact; then
  cat <<EOF
${C_DIM}Sharing this output or recording your screen? Run './trailmq connect --redact'
to print the same page with the passwords masked.${C_RESET}

EOF
fi
