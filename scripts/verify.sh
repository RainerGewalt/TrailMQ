#!/usr/bin/env bash
# TrailMQ — decision proof against the running local stack.
# Invoked by: ./trailmq verify   (./trailmq demo is an alias)
#
# Runs a fixed set of PASS/FAIL checks that prove the product claim, not
# just that containers are up: an authorized publish is delivered, a
# constrained one is blocked, the denial is a recorded decision, and the
# system/action audit chain is still intact. Exits non-zero if any check
# fails, so it doubles as a smoke gate.
#
# Dependencies: docker, plus either local mosquitto clients or none (falls
# back to a dockerized client). No curl/jq needed — the audit-chain check
# goes through `docker exec … wget`.

set -uo pipefail

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

# Optional machine-readable sink. './trailmq try' presents these same checks in
# product language, and it reads them from here rather than parsing the human
# output above — so there is exactly one implementation of the proof, and
# rewording a label can never silently break the guided run.
#
# Format: one "key<TAB>value" line per check or fact.
#
# The contract is deliberately small, and only these keys are part of it. Each
# carries "pass" or "fail":
#
#   ready          the backend answered /ready
#   tls_listener   the MQTT TLS listener accepted an authenticated client
#   allow          an authorized publish reached the subscriber
#   deny           an unauthorized publish was blocked
#   deny_recorded  the denial exists as an attributable decision record
#   api_auth       the REST API issued a token
#   audit_chain    the system/action audit chain validated
#
# One key is emitted only on failure, because it guards a precondition rather
# than proving a claim — absence means "did not apply", never "passed":
#
#   client         a usable MQTT client could not be arranged
#
# Everything below is informational. It is written for humans reading a guided
# run and must not be parsed or asserted on — the audit chain's entry count is
# a moving number, and deny_record carries a raw backend log line whose format
# belongs to the backend, not to this contract:
#
#   audit_chain_entries, deny_record, checks_passed, checks_total
RESULT_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --result-file)
      RESULT_FILE="${2:-}"
      shift 2 || shift
      ;;
    *)
      shift
      ;;
  esac
done
if [ -n "${RESULT_FILE}" ]; then
  : >"${RESULT_FILE}"
fi

emit_result() {
  [ -n "${RESULT_FILE}" ] || return 0
  printf '%s\t%s\n' "$1" "$2" >>"${RESULT_FILE}"
}

require_active_recipe
check_docker || exit 1

recipe_dir="${TRAILMQ_ROOT}/recipes/${ACTIVE_RECIPE}"
ca_file="${recipe_dir}/certs/ca_cert.pem"

CHECKS_TOTAL=0
CHECKS_PASSED=0

record_pass() {
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  CHECKS_PASSED=$((CHECKS_PASSED + 1))
  emit_result "$1" "pass"
  printf "${C_GREEN}[PASS]${C_RESET} %s\n" "$2"
}

record_fail() {
  CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
  emit_result "$1" "fail"
  printf "${C_RED}[FAIL]${C_RESET} %s\n" "$2"
  if [ -n "${3:-}" ]; then
    printf "       ${C_DIM}%s${C_RESET}\n" "$3"
  fi
}

finish() {
  emit_result checks_passed "${CHECKS_PASSED}"
  emit_result checks_total "${CHECKS_TOTAL}"
  echo
  printf "%s/%s checks passed\n" "${CHECKS_PASSED}" "${CHECKS_TOTAL}"
  if [ "${CHECKS_PASSED}" -eq "${CHECKS_TOTAL}" ] && [ "${CHECKS_TOTAL}" -gt 0 ]; then
    exit 0
  fi
  echo
  log_info "Something failed? Run ${C_GREEN}./trailmq doctor${C_RESET} and ${C_GREEN}./trailmq logs backend${C_RESET}."
  exit 1
}

cat <<EOF

${C_BOLD}TrailMQ decision proof${C_RESET}
${C_DIM}Not just "is it running" — does it decide, enforce and record?${C_RESET}

EOF

# ------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------
if ! docker container inspect trailmq-backend >/dev/null 2>&1 ||
  [ "$(docker container inspect -f '{{.State.Running}}' trailmq-backend 2>/dev/null)" != "true" ]; then
  record_fail ready "Runtime ready" "Backend container not running — start it with './trailmq start'"
  finish
fi

admin_pw_file="${recipe_dir}/secrets/testadmin.pwd"
user_pw_file="${recipe_dir}/secrets/testuser.pwd"
for f in "${admin_pw_file}" "${user_pw_file}" "${ca_file}"; do
  if [ ! -s "$f" ]; then
    record_fail ready "Runtime ready" "Missing $f — run './trailmq start' first"
    finish
  fi
done
ADMIN_PW="$(cat "${admin_pw_file}")"
USER_PW="$(cat "${user_pw_file}")"

ready=false
for _ in $(seq 1 30); do
  if docker exec trailmq-backend wget -qO- http://localhost:8443/ready >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 1
done
if $ready; then
  record_pass ready "Runtime ready"
else
  record_fail ready "Runtime ready" "Backend never reported ready"
  finish
fi

# ------------------------------------------------------------------
# Client tooling: local mosquitto clients, or a dockerized fallback
# ------------------------------------------------------------------
use_docker_client=false
if ! command -v mosquitto_pub >/dev/null 2>&1 || ! command -v mosquitto_sub >/dev/null 2>&1; then
  use_docker_client=true
  stack_net="$(docker container inspect trailmq-backend \
    -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null)"
  if [ -z "${stack_net}" ]; then
    record_fail client "MQTT client available" "Could not determine the stack's Docker network"
    finish
  fi
  log_info "${C_DIM}mosquitto clients not installed locally — using a dockerized client.${C_RESET}"
fi

mqtt_host() { $use_docker_client && printf 'backend' || printf 'localhost'; }
mqtt_ca() { $use_docker_client && printf '/verify-certs/ca_cert.pem' || printf '%s' "${ca_file}"; }

mq() {
  # mq <pub|sub> <args…>
  local tool="mosquitto_$1"
  shift
  if $use_docker_client; then
    docker run --rm --network "${stack_net}" \
      -v "${recipe_dir}/certs:/verify-certs:ro" \
      eclipse-mosquitto:2 "${tool}" "$@"
  else
    "${tool}" "$@"
  fi
}

# ------------------------------------------------------------------
# TLS listener
# ------------------------------------------------------------------
if mq sub -h "$(mqtt_host)" -p 8883 --cafile "$(mqtt_ca)" \
  -u testadmin -P "${ADMIN_PW}" -i trailmq-verify-probe \
  -t 'trailmq/#' -C 1 -W 8 >/dev/null 2>&1; then
  record_pass tls_listener "MQTT TLS listener accepts authenticated clients"
else
  record_fail tls_listener "MQTT TLS listener accepts authenticated clients" \
    "TLS connect or authentication failed on port 8883"
fi

# ------------------------------------------------------------------
# Authorized publish is delivered
# ------------------------------------------------------------------
sub_out="$(mktemp)"
trap 'rm -f "${sub_out}"' EXIT

mq sub -h "$(mqtt_host)" -p 8883 --cafile "$(mqtt_ca)" \
  -u testadmin -P "${ADMIN_PW}" \
  -i trailmq-verify-dashboard \
  -t 'public/#' -T 'trailmq/#' -C 1 -W 15 -v >"${sub_out}" 2>/dev/null &
sub_pid=$!
sleep 2

payload="{\"value\":21.4,\"unit\":\"degC\",\"verify\":\"$(date +%H:%M:%S)\"}"
mq pub -h "$(mqtt_host)" -p 8883 --cafile "$(mqtt_ca)" \
  -u testuser -P "${USER_PW}" \
  -i trailmq-verify-sensor \
  -t 'public/demo/temperature' -q 1 -m "${payload}" 2>/dev/null || true

wait "${sub_pid}" 2>/dev/null || true
if grep -qF "${payload}" "${sub_out}"; then
  record_pass allow "Authorized publish reached the subscriber   ${C_DIM}public/demo/temperature${C_RESET}"
else
  record_fail allow "Authorized publish reached the subscriber" \
    "Nothing arrived on public/demo/temperature"
fi

# ------------------------------------------------------------------
# Unauthorized publish is blocked
# ------------------------------------------------------------------
if mq pub -h "$(mqtt_host)" -p 8883 --cafile "$(mqtt_ca)" \
  -u testuser -P "${USER_PW}" \
  -i trailmq-verify-sensor \
  -t 'restricted/ops/config' -q 1 -m 'should-not-arrive' >/dev/null 2>&1; then
  record_fail deny "Unauthorized publish was blocked" \
    "restricted/ops/config accepted a publish from role 'publisher'"
else
  record_pass deny "Unauthorized publish was blocked            ${C_DIM}restricted/ops/config${C_RESET}"
fi

# ------------------------------------------------------------------
# The denial is an explicit, attributable decision
# ------------------------------------------------------------------
deny_line="$(docker logs trailmq-backend --since 2m 2>&1 |
  grep -F '[ACLMon] DENY' | grep -F 'restricted/ops/config' | tail -n 1 || true)"
if [ -n "${deny_line}" ]; then
  record_pass deny_recorded "Denial recorded with user, role, action and topic"
  emit_result deny_record "${deny_line#*] }"
  printf "       ${C_DIM}%s${C_RESET}\n" "${deny_line#*] }"
else
  record_fail deny_recorded "Denial recorded with user, role, action and topic" \
    "No [ACLMon] DENY entry found for restricted/ops/config"
fi

# ------------------------------------------------------------------
# Audit chain integrity
# ------------------------------------------------------------------
login_resp="$(docker exec trailmq-backend wget -qO- \
  --header='Content-Type: application/json' \
  --post-data="{\"username\":\"testadmin\",\"password\":\"${ADMIN_PW}\"}" \
  http://localhost:8443/api/v1/auth 2>/dev/null || true)"
token="$(printf '%s' "${login_resp}" | grep -o '"token":"[^"]*"' | head -n 1 | cut -d'"' -f4)"

if [ -n "${token}" ]; then
  record_pass api_auth "REST API authentication issues a token"
else
  record_fail api_auth "REST API authentication issues a token" "Login to /api/v1/auth failed"
fi

chain_resp=""
if [ -n "${token}" ]; then
  chain_resp="$(docker exec trailmq-backend wget -qO- \
    --header="Authorization: Bearer ${token}" \
    http://localhost:8443/api/v1/audit/validatechain 2>/dev/null || true)"
fi

if printf '%s' "${chain_resp}" | grep -q '"valid":true'; then
  entries="$(printf '%s' "${chain_resp}" | grep -o '"checkedEntries":[0-9]*' | cut -d: -f2)"
  record_pass audit_chain "System/action audit chain intact          ${C_DIM}${entries:-?} entries hash-checked${C_RESET}"
  emit_result audit_chain_entries "${entries:-}"
else
  record_fail audit_chain "System/action audit chain intact" \
    "${chain_resp:-no response from /api/v1/audit/validatechain}"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
version_resp="$(docker exec trailmq-backend wget -qO- \
  http://localhost:8443/api/v1/version 2>/dev/null || true)"
backend_version="$(printf '%s' "${version_resp}" | grep -o '"version":"[^"]*"' | head -n 1 | cut -d'"' -f4)"

cat <<EOF

${C_DIM}Backend    ${backend_version:-unknown}
Recipe     ${ACTIVE_RECIPE}
Checked    $(date -u +%Y-%m-%dT%H:%M:%SZ)${C_RESET}

${C_BOLD}That is the difference${C_RESET}
  The result is more than a running broker: TrailMQ applied the configured
  access rules, blocked the unauthorized action, and kept its decision record.

  See it in the UI: ${C_CYAN}$(trailmq_http_base_url)/trailmq/${C_RESET} → ${C_BOLD}Activity${C_RESET} → filter ${C_BOLD}Outcome: Denied${C_RESET}
  Login: ${C_BOLD}testadmin${C_RESET} (password: ./trailmq credentials)

${C_BOLD}Go deeper${C_RESET}
  docs/scenarios/00-why-not-just-a-broker.md   the same commands vs. a plain broker
  docs/scenarios/                              eight guided walkthroughs
  docs/connect-a-client.md                     connect your own MQTT client
EOF

finish
