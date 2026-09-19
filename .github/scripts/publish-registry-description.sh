#!/usr/bin/env bash
# TrailMQ — publish the canonical registry text to Docker Hub.
#
# distribution/registry/*.md is already the single source for the Docker Hub and
# GHCR pages, and render-registry.sh already turns it into the thing a stranger
# reads. The one step that was still manual is the upload, which is exactly how
# those pages drifted: on 2026-09-19 they carried wording from a different
# release, an invented refusal reason, and no version at all, while this
# repository held the correct text the whole time.
#
# This script closes that gap. It publishes what render-registry.sh renders and
# nothing else — it never composes text of its own, so the repository stays the
# only place the registry wording is written.
#
# Usage:
#   .github/scripts/publish-registry-description.sh <backend|frontend|all>
#
# Environment:
#   DOCKERHUB_USERNAME  account that owns the repositories
#   DOCKERHUB_TOKEN     personal access token with write scope
#   DOCKERHUB_NAMESPACE optional, defaults to DOCKERHUB_USERNAME
#   DRY_RUN=1           render and report, contact nothing
#
# Requires: bash, curl, jq.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}" || exit 2

RENDER=".github/scripts/render-registry.sh"
API="https://hub.docker.com/v2"
LABEL_PREFIX="org.opencontainers.image"

die() { printf 'publish-registry-description: %s\n' "$*" >&2; exit 1; }

component_repo() {
  case "$1" in
    backend) printf 'trailmq-backend' ;;
    frontend) printf 'trailmq-frontend' ;;
    *) return 1 ;;
  esac
}

# The short description under the repository name is the OCI image description,
# so the label file stays the only place it is written.
short_description() {
  "${RENDER}" labels "$1" | sed -n "s|^${LABEL_PREFIX}\.description=||p"
}

login() {
  local body
  body="$(jq -nc --arg u "${DOCKERHUB_USERNAME}" --arg p "${DOCKERHUB_TOKEN}" \
    '{username: $u, password: $p}')"
  curl -sS --fail-with-body -X POST "${API}/users/login/" \
    -H 'Content-Type: application/json' -d "${body}" |
    jq -re '.token' 2>/dev/null
}

publish_one() {
  local component="$1" token="$2" repo full short payload namespace
  repo="$(component_repo "${component}")" || die "unknown component: ${component}"
  namespace="${DOCKERHUB_NAMESPACE:-${DOCKERHUB_USERNAME:-}}"

  full="$("${RENDER}" text "${component}")" ||
    die "${component}: registry text does not render"
  short="$(short_description "${component}")"
  [ -n "${full}" ] || die "${component}: rendered text is empty"
  [ -n "${short}" ] || die "${component}: no image description label"

  # A leftover placeholder would be published as a literal, which is the drift
  # this whole folder exists to prevent.
  case "${full}" in
    *'{{'*) die "${component}: rendered text still contains a placeholder" ;;
  esac

  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '[DRY-RUN] %s/%s\n  short: %s\n  full:  %s lines\n' \
      "${namespace:-<namespace>}" "${repo}" "${short}" \
      "$(printf '%s\n' "${full}" | wc -l)"
    return 0
  fi

  payload="$(jq -nc --arg d "${short}" --arg f "${full}" \
    '{description: $d, full_description: $f}')"

  if curl -sS --fail-with-body -X PATCH "${API}/repositories/${namespace}/${repo}/" \
    -H "Authorization: JWT ${token}" \
    -H 'Content-Type: application/json' \
    -d "${payload}" >/dev/null; then
    printf '[OK]   %s/%s description published\n' "${namespace}" "${repo}"
  else
    printf '[FAIL] %s/%s description not published\n' "${namespace}" "${repo}" >&2
    return 1
  fi
}

main() {
  local target="${1:-all}" token="" failed=0
  case "${target}" in
    backend | frontend | all) ;;
    *) die "usage: $0 <backend|frontend|all>" ;;
  esac

  command -v jq >/dev/null || die "jq is required"

  if [ "${DRY_RUN:-0}" != "1" ]; then
    : "${DOCKERHUB_USERNAME:?DOCKERHUB_USERNAME is not set}"
    : "${DOCKERHUB_TOKEN:?DOCKERHUB_TOKEN is not set}"
    token="$(login)" || die "Docker Hub login failed"
    [ -n "${token}" ] || die "Docker Hub login returned no token"
  fi

  for component in backend frontend; do
    [ "${target}" = "all" ] || [ "${target}" = "${component}" ] || continue
    publish_one "${component}" "${token}" || failed=$((failed + 1))
  done

  [ "${failed}" -eq 0 ] || exit 1
}

main "$@"
