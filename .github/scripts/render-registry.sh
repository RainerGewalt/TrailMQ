#!/usr/bin/env bash
# TrailMQ — render the canonical registry surfaces.
#
# The text on Docker Hub and GHCR, and the OCI labels stamped into the images,
# both come from this repository so that they cannot drift from the release
# contract. This script is what turns the stored source into the thing that
# gets published.
#
# Usage:
#   .github/scripts/render-registry.sh text   <backend|frontend>
#   .github/scripts/render-registry.sh labels <backend|frontend>
#
# 'text' resolves the {{...}} placeholders in distribution/registry/*.md from
# release.yaml. 'labels' emits `key=value` lines ready for `docker build
# --label`, combining the static labels in distribution/registry/oci-labels.yaml
# with the three that only exist at build time.
#
# Build-time labels resolve like this, most explicit first:
#   version    release.yaml (always)
#   revision   TRAILMQ_IMAGE_REVISION, GITHUB_SHA, then `git rev-parse HEAD`
#   created    SOURCE_DATE_EPOCH if set, otherwise now, always UTC RFC 3339
#
# Requires: bash, awk, date. No yq.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}" || exit 2

# shellcheck source=../../scripts/release-contract.sh
source "${REPO_ROOT}/scripts/release-contract.sh"

REGISTRY_DIR="distribution/registry"
LABELS_FILE="${REGISTRY_DIR}/oci-labels.yaml"
LABEL_PREFIX="org.opencontainers.image"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

component_valid() {
  case "$1" in
    backend | frontend) return 0 ;;
    *) return 1 ;;
  esac
}

# Every placeholder the registry text may use. The gate checks stored text
# against this same list, so an unknown placeholder is caught before it can be
# published as a literal '{{typo}}'.
placeholder_value() {
  case "$1" in
    version) release_contract_get version ;;
    backend_version) release_contract_get runtime.backend ;;
    frontend_version) release_contract_get runtime.frontend ;;
    *) return 1 ;;
  esac
}

render_text() {
  local component="$1"
  local source_file="${REGISTRY_DIR}/trailmq-${component}.md"
  [ -f "${source_file}" ] || die "no registry text for ${component}: ${source_file}"

  local body
  body="$(cat "${source_file}")"

  local name value
  for name in version backend_version frontend_version; do
    if ! value="$(placeholder_value "${name}")"; then
      die "could not resolve {{${name}}} from release.yaml"
    fi
    body="${body//\{\{${name}\}\}/${value}}"
  done

  # A leftover placeholder means the text used a name this renderer does not
  # know. Publishing that would put literal braces on a public page.
  if printf '%s' "${body}" | grep -q '{{'; then
    printf '%s\n' "${body}" | grep -n '{{' >&2
    die "unresolved placeholder in ${source_file}"
  fi

  printf '%s\n' "${body}"
}

render_labels() {
  local component="$1"
  [ -f "${LABELS_FILE}" ] || die "no label spec: ${LABELS_FILE}"

  local flat
  flat="$(release_contract_flatten "${LABELS_FILE}")" ||
    die "${LABELS_FILE} is not in the documented shape"

  # Per-component values win over common ones, so a component can override a
  # shared label without the spec needing to repeat every key.
  local keys=""
  local key value
  while IFS=$'\t' read -r path value; do
    [ -z "${path}" ] && continue
    case "${path}" in
      common.* | "${component}".*)
        key="${path#*.}"
        keys="${keys}${key}"$'\n'
        ;;
    esac
  done <<<"${flat}"

  local emitted=""
  while IFS= read -r key; do
    [ -z "${key}" ] && continue
    case " ${emitted} " in *" ${key} "*) continue ;; esac
    emitted="${emitted}${key} "

    value="$(printf '%s\n' "${flat}" |
      awk -F'\t' -v c="${component}.${key}" -v g="common.${key}" '
        $1 == c { specific = $2 }
        $1 == g { general = $2 }
        END { print (specific != "" ? specific : general) }')"
    printf '%s.%s=%s\n' "${LABEL_PREFIX}" "${key}" "${value}"
  done < <(printf '%s' "${keys}" | sort -u)

  # --- build-time labels ---
  local version
  version="$(release_contract_get version)" || die "could not read version from release.yaml"
  printf '%s.version=%s\n' "${LABEL_PREFIX}" "${version}"

  local revision="${TRAILMQ_IMAGE_REVISION:-${GITHUB_SHA:-}}"
  if [ -z "${revision}" ]; then
    revision="$(git rev-parse HEAD 2>/dev/null || true)"
  fi
  [ -n "${revision}" ] || die "could not determine the image revision"
  printf '%s.revision=%s\n' "${LABEL_PREFIX}" "${revision}"

  local created
  if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
    created="$(date -u -d "@${SOURCE_DATE_EPOCH}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  else
    created="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  [ -n "${created}" ] || die "could not determine the image creation timestamp"
  printf '%s.created=%s\n' "${LABEL_PREFIX}" "${created}"
}

mode="${1:-}"
component="${2:-}"

component_valid "${component}" ||
  die "usage: $0 {text|labels} <backend|frontend>"

case "${mode}" in
  text) render_text "${component}" ;;
  labels) render_labels "${component}" ;;
  *) die "usage: $0 {text|labels} <backend|frontend>" ;;
esac
