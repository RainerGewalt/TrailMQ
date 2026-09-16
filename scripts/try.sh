#!/usr/bin/env bash
# TrailMQ — the guided first run.
# Invoked by: ./trailmq try
#
# This is the product entry point. It owns no proof of its own: the setup is
# scripts/launch.sh and the evidence is scripts/verify.sh, exactly as the
# reproducible commands './trailmq quickstart' and './trailmq verify' run them.
# What this script adds is sequencing and language — it waits for readiness,
# reads the proof's machine-readable result, and states the outcome as a
# product claim rather than a checklist.
#
# Deliberate constraint: every line printed at the end is backed by a check
# that actually ran. If a check did not pass, the line says so. A guided run
# that overstates what was verified is worse than no guided run at all.
#
# Exit codes — distinct on purpose, so a wrapper or CI job can tell "this
# machine is not ready" apart from "TrailMQ started but decided wrongly",
# which are different problems with different owners:
#   0  everything ran and every check passed
#   1  preflight failed — Docker, Compose, OpenSSL or a port
#   2  setup failed — the stack did not come up
#   3  the decision proof could not run at all
#   4  the proof ran and at least one check failed

set -uo pipefail

readonly EX_PREFLIGHT=1
readonly EX_SETUP=2
readonly EX_PROOF_UNAVAILABLE=3
readonly EX_PROOF_FAILED=4

TRAILMQ_ROOT="${TRAILMQ_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TRAILMQ_ROOT
# shellcheck source=common.sh
source "${TRAILMQ_ROOT}/scripts/common.sh"

RECIPE="secure-mqtt-core"
WORK_DIR="$(mktemp -d)"
SETUP_LOG="${WORK_DIR}/setup.log"
PROOF_LOG="${WORK_DIR}/proof.log"
RESULT_FILE="${WORK_DIR}/proof.tsv"
trap 'rm -rf "${WORK_DIR}"' EXIT

# Read one key from the proof's result file.
result() {
  [ -f "${RESULT_FILE}" ] || return 1
  awk -F'\t' -v k="$1" '$1 == k { print $2; found = 1 } END { exit !found }' "${RESULT_FILE}"
}

# True when a named check passed.
passed() {
  [ "$(result "$1" 2>/dev/null)" = "pass" ]
}

cat <<EOF

${C_BOLD}TrailMQ${C_RESET} — an MQTT broker that decides, enforces and records

${C_DIM}This starts a local evaluation, then proves the difference to a plain
broker by doing it: one publish that is allowed, one that is refused.${C_RESET}

${C_BOLD}1/4  Checking prerequisites${C_RESET}
EOF

# ------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------
# The goal here is to fail before Docker does, in the user's language. Docker's
# own errors for these cases ("bind: address already in use") are accurate but
# arrive after a partial start and read like a TrailMQ defect.
preflight_failed=false

if command -v docker >/dev/null 2>&1; then
  log_ok "Docker            ${C_DIM}$(docker --version 2>/dev/null | sed -E 's/^Docker version //; s/,.*//')${C_RESET}"
else
  log_err "Docker            not found"
  preflight_failed=true
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  log_ok "Docker Compose    ${C_DIM}$(docker compose version --short 2>/dev/null)${C_RESET}"
else
  log_err "Docker Compose    v2 not found ('docker compose version' failed)"
  preflight_failed=true
fi

# The daemon can be installed but not running — a distinct failure with a
# distinct fix, so it gets its own line.
if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then
  log_err "Docker daemon     not reachable — is Docker running?"
  preflight_failed=true
fi

if command -v openssl >/dev/null 2>&1; then
  log_ok "OpenSSL           ${C_DIM}$(openssl version 2>/dev/null | cut -d' ' -f1-2)${C_RESET}"
else
  log_err "OpenSSL           not found — needed for demo certificates and credentials"
  preflight_failed=true
fi

# A port already held by TrailMQ itself is not a conflict; it means the user is
# running 'try' again, which is supported.
own_stack_up=false
if docker container inspect trailmq-reverse-proxy >/dev/null 2>&1 &&
  [ "$(docker container inspect -f '{{.State.Running}}' trailmq-reverse-proxy 2>/dev/null)" = "true" ]; then
  own_stack_up=true
fi

check_port() {
  local port="$1" label="$2" var="$3" suggestion="$4"
  if ! port_in_use "${port}"; then
    log_ok "Port ${port}$(printf '%*s' $((10 - ${#port})) '')${label}"
    return 0
  fi
  if $own_stack_up; then
    log_ok "Port ${port}$(printf '%*s' $((10 - ${#port})) '')${label} ${C_DIM}(already TrailMQ's — re-running)${C_RESET}"
    return 0
  fi
  log_err "Port ${port} is already in use — ${label} cannot bind"
  echo
  log_info "  Another program holds it. Pick a different host port:"
  log_info "    echo '${var}=${suggestion}' >> .env"
  log_info "    ./trailmq try"
  echo
  log_info "  ${C_DIM}${suggestion} is already allowed as a browser origin in the recipe"
  log_info "  config, so the Web UI keeps working without further edits.${C_RESET}"
  return 1
}

check_port "${TRAILMQ_HTTP_PORT}" "Web UI / REST API" "TRAILMQ_HTTP_PORT" "8080" || preflight_failed=true
check_port "${TRAILMQ_MQTT_TLS_PORT}" "MQTT over TLS" "TRAILMQ_MQTT_TLS_PORT" "8884" || preflight_failed=true

avail_kb="$(df -Pk "${TRAILMQ_ROOT}" 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "${avail_kb}" ] && [ "${avail_kb}" -lt 2097152 ]; then
  log_warn "Disk              $((avail_kb / 1024)) MB free — the images need about 1 GB"
else
  log_ok "Disk              ${C_DIM}enough free space for the images${C_RESET}"
fi

log_ok "Architecture      ${C_DIM}$(uname -m 2>/dev/null || echo unknown)${C_RESET}"

if $preflight_failed; then
  echo
  log_err "Cannot start yet. Fix the items above and run './trailmq try' again."
  echo
  log_info "Docker missing entirely? TrailMQ needs it for this evaluation path."
  log_info "Install it from https://docs.docker.com/get-docker/ — or write to"
  log_info "contact@trailmq.com for a 20-minute technical walkthrough instead."
  exit "${EX_PREFLIGHT}"
fi

# ------------------------------------------------------------------
# Setup + start
# ------------------------------------------------------------------
cat <<EOF

${C_BOLD}2/4  Preparing the evaluation and starting TrailMQ${C_RESET}
${C_DIM}First run pulls three container images — that part takes the longest.${C_RESET}

EOF

# Output stays visible on purpose. The first run is dominated by image pulls,
# and a silent multi-minute wait reads as a hang. The epilogue is suppressed
# because this script prints a better one below.
if ! "${TRAILMQ_ROOT}/scripts/launch.sh" --quickstart --no-epilogue 2>&1 | tee "${SETUP_LOG}"; then
  echo
  log_err "Setup did not complete."
  log_info "Run './trailmq doctor' for a component-by-component check."
  exit "${EX_SETUP}"
fi

# tee masks the launcher's exit status, so failure is detected from the marker
# the launcher prints only after the stack is actually up.
if ! grep -q 'Stack is up.' "${SETUP_LOG}"; then
  echo
  log_err "Setup did not reach a running stack."
  log_info "Run './trailmq doctor', then './trailmq logs backend'."
  exit "${EX_SETUP}"
fi

# ------------------------------------------------------------------
# The proof — verify.sh, presented differently
# ------------------------------------------------------------------
cat <<EOF

${C_BOLD}3/4  Making TrailMQ decide${C_RESET}
${C_DIM}Publishing as 'testuser' to a topic that is allowed, then to one that is
not. Waiting for the broker to be ready first — up to 30 seconds.${C_RESET}

EOF

"${TRAILMQ_ROOT}/scripts/verify.sh" --result-file "${RESULT_FILE}" >"${PROOF_LOG}" 2>&1
proof_status=$?

if [ ! -s "${RESULT_FILE}" ]; then
  log_err "The decision proof could not run."
  echo
  sed -n '1,40p' "${PROOF_LOG}"
  echo
  log_info "Run './trailmq verify' to see the full output, then './trailmq doctor'."
  exit "${EX_PROOF_UNAVAILABLE}"
fi

# ------------------------------------------------------------------
# Result, in product language
# ------------------------------------------------------------------
echo
echo "${C_BOLD}4/4  What just happened${C_RESET}"
echo

if passed allow; then
  printf "${C_GREEN}✓${C_RESET} %s\n" "Authorized MQTT publish was delivered"
  printf "  ${C_DIM}%s${C_RESET}\n" "testuser → public/demo/temperature → reached the subscriber"
else
  printf "${C_RED}✗${C_RESET} %s\n" "Authorized MQTT publish did NOT reach the subscriber"
fi
echo

if passed deny; then
  printf "${C_GREEN}✓${C_RESET} %s\n" "Restricted publish was refused"
  printf "  ${C_DIM}%s${C_RESET}\n" "testuser → restricted/ops/config → blocked"
  printf "  ${C_DIM}%s${C_RESET}\n" "because restricted/# is admin-only and testuser is not an admin"
else
  printf "${C_RED}✗${C_RESET} %s\n" "Restricted publish was NOT refused"
fi
echo

if passed deny_recorded; then
  printf "${C_GREEN}✓${C_RESET} %s\n" "The refusal was recorded as an attributable decision"
  deny_record="$(result deny_record 2>/dev/null || true)"
  if [ -n "${deny_record}" ]; then
    printf "  ${C_DIM}%s${C_RESET}\n" "${deny_record}"
  fi
else
  printf "${C_RED}✗${C_RESET} %s\n" "No decision record was found for the refusal"
fi
echo

# Scope matters more than the checkmark here. This check validates the system
# and action audit chain — logins, policy and topic-rule changes, access
# decisions. Per-message payload evidence is a separate chain that this
# release does not expose through the API, so it is not claimed.
if passed audit_chain; then
  entries="$(result audit_chain_entries 2>/dev/null || true)"
  printf "${C_GREEN}✓${C_RESET} %s\n" "Evidence verified: system and action audit chain"
  printf "  ${C_DIM}%s${C_RESET}\n" "${entries:-?} entries hash-checked, chain intact"
  printf "  ${C_DIM}%s${C_RESET}\n" "scope: access decisions, logins, policy and topic-rule changes"
else
  printf "${C_RED}✗${C_RESET} %s\n" "Audit chain did not validate"
fi

passed_count="$(result checks_passed 2>/dev/null || echo '?')"
total_count="$(result checks_total 2>/dev/null || echo '?')"

if [ "${proof_status}" -ne 0 ]; then
  echo
  log_warn "${passed_count}/${total_count} checks passed — see the detail below."
  echo
  grep -E '^\[(PASS|FAIL)\]|^ ' "${PROOF_LOG}" | sed -n '1,40p'
  echo
  log_info "Run './trailmq doctor' and './trailmq logs backend'."
fi

# ------------------------------------------------------------------
# Where to go next
# ------------------------------------------------------------------
ACTIVE_RECIPE="${RECIPE}"
export ACTIVE_RECIPE
ui_url="$(trailmq_http_base_url)/trailmq/"

cat <<EOF

${C_BOLD}Open TrailMQ${C_RESET}
  ${C_CYAN}${ui_url}${C_RESET}
EOF

print_evaluation_credentials "${RECIPE}"

cat <<EOF

  ${C_DIM}Log in as testadmin. Activity → filter Outcome: Denied shows the
  refusal you just triggered, with who, what, where and why.${C_RESET}

${C_BOLD}Next${C_RESET}
  ${C_GREEN}./trailmq connect${C_RESET}   Connect your own MQTT client
  ${C_GREEN}./trailmq verify${C_RESET}    The same proof as a reproducible PASS/FAIL run
  ${C_GREEN}./trailmq reset${C_RESET}     Back to a clean evaluation

${C_DIM}Want it shown instead? A 20-minute technical walkthrough, no sales deck:
contact@trailmq.com${C_RESET}

EOF

if [ "${TRAILMQ_NO_BROWSER:-}" != "1" ] && open_url "${ui_url}"; then
  log_info "${C_DIM}Opening ${ui_url} in your browser…${C_RESET}"
  echo
fi

# The stack is up either way, so the browser still opened above — but the
# status has to carry the proof's verdict, not the launcher's.
if [ "${proof_status}" -ne 0 ]; then
  exit "${EX_PROOF_FAILED}"
fi
exit 0
