#!/usr/bin/env bash
# TrailMQ — reader for the release contract (release.yaml).
#
# The contract is the source of version truth for this repository, so every
# consumer has to read it the same way: the CLI, the distribution gate and the
# evaluation-bundle builder all come through here rather than each inventing
# its own regex over a YAML file.
#
# Usage:
#   scripts/release-contract.sh get <dotted.path>   print one value, or 'null'
#   scripts/release-contract.sh flatten             print path<TAB>value lines
#   scripts/release-contract.sh version             shorthand for 'get version'
#
# It can also be sourced as a library, which defines release_contract_get and
# release_contract_flatten and does nothing else:
#   source scripts/release-contract.sh
#
# Exit codes:
#   0  value printed
#   1  the path is not in the contract
#   3  the contract is missing or is not in the documented shape
#
# The 1/3 split matters to callers: a missing key is a contract that forgot
# something, an unreadable file is a contract nobody should trust at all.
#
# Requires: bash, awk. No yq, no Python — the file must stay readable on a
# machine that has only what an evaluator already needs.

set -uo pipefail

# Path to the contract. Overridable so a test can point at a mutated copy
# without rewriting the tree.
release_contract_file() {
  if [ -n "${TRAILMQ_RELEASE_CONTRACT:-}" ]; then
    printf '%s\n' "${TRAILMQ_RELEASE_CONTRACT}"
    return 0
  fi
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s/release.yaml\n' "${here}"
}

# Flatten the contract to `dotted.path<TAB>value`, one leaf per line.
#
# This reads a deliberately small YAML subset — nested maps of scalars, nothing
# else. Anything outside it is reported with a file and line number rather than
# skipped, because the failure mode being avoided is a typo that parses into
# silence and lets a release ship against a version nobody declared.
release_contract_flatten() {
  local file
  file="${1:-$(release_contract_file)}"

  if [ ! -f "${file}" ]; then
    printf 'release contract not found: %s\n' "${file}" >&2
    return 3
  fi

  awk -v file="${file}" '
    function die(msg) {
      printf("%s:%d: %s\n", file, NR, msg) > "/dev/stderr"
      bad = 1
      exit 3
    }

    /^[ \t]*$/ { next }
    /^[ \t]*#/ { next }

    {
      line = $0
      if (line ~ /\t/) die("tab indentation is not allowed")

      # A comment after a value. Values in this contract are versions, "null"
      # and single words, none of which can contain " #".
      sub(/[ ]+#.*$/, "", line)
      sub(/[ ]+$/, "", line)
      if (line == "") next

      match(line, /^ */)
      indent = RLENGTH
      if (indent % 2 != 0) die("indentation must be a multiple of two spaces")
      level = indent / 2
      if (level > depth) die("unexpected indentation — no parent key at this level")

      rest = substr(line, indent + 1)
      if (rest !~ /^[A-Za-z_][A-Za-z0-9_]*:/) die("expected \"key:\" or \"key: value\"")

      colon = index(rest, ":")
      key = substr(rest, 1, colon - 1)
      value = substr(rest, colon + 1)
      sub(/^ +/, "", value)

      path[level] = key

      if (value == "") {
        # A map opens one level of nesting.
        depth = level + 1
        next
      }

      gsub(/^"|"$/, "", value)

      out = path[0]
      for (i = 1; i <= level; i++) out = out "." path[i]
      printf("%s\t%s\n", out, value)

      # A leaf takes no children, so the next line may not indent past it.
      depth = level
    }

    END { if (bad) exit 3 }
  ' "${file}"
}

# Print the value at a dotted path.
release_contract_get() {
  local path="$1"
  local flat
  if ! flat="$(release_contract_flatten)"; then
    return 3
  fi
  printf '%s\n' "${flat}" |
    awk -F'\t' -v k="${path}" '$1 == k { print $2; found = 1; exit } END { exit !found }'
}

# Only act as a command when executed, not when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  cmd="${1:-}"
  case "${cmd}" in
    get)
      if [ "$#" -ne 2 ]; then
        printf 'usage: %s get <dotted.path>\n' "$0" >&2
        exit 2
      fi
      release_contract_get "$2"
      ;;
    version)
      release_contract_get version
      ;;
    flatten)
      release_contract_flatten
      ;;
    *)
      printf 'usage: %s {get <dotted.path>|version|flatten}\n' "$0" >&2
      exit 2
      ;;
  esac
fi
