#!/usr/bin/env bash
# TrailMQ — verify a bundle's documentation is self-contained.
#
# The rule this enforces:
#
#     Everything linked relatively inside the bundle must exist inside the
#     bundle.
#
# A downloaded evaluation package is not a checkout. It ships without the
# development and CI paths, so a relative link that resolves fine in the
# repository can land a reader on nothing at all — which is exactly what
# happened to the Contributing and distribution-gate links before this check
# existed.
#
# Absolute links are accepted without being fetched. A release must not depend
# on the network, or on GitHub being reachable from a build runner, to decide
# whether it is publishable.
#
# Usage:
#   .github/scripts/check-bundle-links.sh <bundle-root>

set -uo pipefail

ROOT="${1:-}"
if [ -z "${ROOT}" ] || [ ! -d "${ROOT}" ]; then
  printf 'usage: %s <bundle-root>\n' "$0" >&2
  exit 2
fi

ROOT="$(cd "${ROOT}" && pwd)"
broken=0
checked=0

while IFS= read -r doc; do
  doc_dir="$(dirname "${doc}")"

  # The character class excludes ':', which is what separates a relative path
  # from an absolute URL. mailto: and https:// are filtered out by the same
  # rule rather than by a scheme list that would need maintaining.
  while IFS= read -r target; do
    [ -z "${target}" ] && continue
    target="${target%%#*}"
    [ -z "${target}" ] && continue

    checked=$((checked + 1))
    if [ ! -e "${doc_dir}/${target}" ]; then
      rel="${doc#"${ROOT}"/}"
      printf '  %s → %s\n' "${rel}" "${target}"
      broken=$((broken + 1))
    fi
  done < <(grep -oE '\]\([^):]+\)' "${doc}" | sed -E 's/^\]\(//; s/\)$//' | grep -v '^#' | sort -u)
done < <(find "${ROOT}" -name '*.md' -type f | sort)

if [ "${broken}" -gt 0 ]; then
  printf '%s relative link(s) do not resolve inside the bundle\n' "${broken}" >&2
  exit 1
fi

printf '%s relative link(s) resolve inside the bundle\n' "${checked}"
