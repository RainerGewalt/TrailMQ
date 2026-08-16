#!/usr/bin/env bash
# TrailMQ — turn a checkout-shaped tree into evaluation-bundle content.
#
# This is the single definition of what a downloaded bundle contains and how it
# differs from the repository. The bundle builder calls it before archiving,
# and the distribution gate calls it on a throwaway copy so a pull request
# fails on a bundle defect rather than a release discovering it.
#
# Usage:
#   .github/scripts/stage-evaluation-bundle.sh <tree-dir> <version>
#   .github/scripts/stage-evaluation-bundle.sh --dev-only-paths
#
# The tree is modified in place.

set -uo pipefail

# Where a reader ends up when a link points at something the bundle does not
# ship. Pinned to the default branch on purpose: a bundle outlives the commit
# it was built from, and a blob URL to a deleted revision ages worse than a
# branch URL that tracks the current document.
CANONICAL_BASE="https://github.com/RainerGewalt/TrailMQ/blob/master"

# Paths that exist for people who develop TrailMQ, not for people who evaluate
# it. Shipping them makes the bundle look like a repository, which is the exact
# impression this asset exists to avoid.
DEV_ONLY=(
  .github
  CONTRIBUTING.md
  .gitignore
  # Registry page copy and packaging inputs maintain the public distribution.
  # They are not something an evaluator running the stack has any use for.
  distribution
)

if [ "${1:-}" = "--dev-only-paths" ]; then
  printf '%s\n' "${DEV_ONLY[@]}"
  exit 0
fi

ROOT="${1:-}"
VERSION="${2:-}"

if [ -z "${ROOT}" ] || [ ! -d "${ROOT}" ] || [ -z "${VERSION}" ]; then
  printf 'usage: %s <tree-dir> <version>\n' "$0" >&2
  exit 2
fi
ROOT="$(cd "${ROOT}" && pwd)"

command -v realpath >/dev/null 2>&1 || {
  printf 'Required tool missing: realpath\n' >&2
  exit 2
}

# ---------------------------------------------------------------------------
# 1. Remove what an evaluator has no use for.
# ---------------------------------------------------------------------------
for path in "${DEV_ONLY[@]}"; do
  rm -rf "${ROOT:?}/${path}"
done

# ---------------------------------------------------------------------------
# 2. Repoint the links that removal just broke.
#
# Only links whose target was removed above are rewritten, and they are
# rewritten to the canonical document on GitHub rather than deleted — a reader
# who wants the contribution scope or the gate definition should still be able
# to reach it. Anything else that dangles is a genuine defect and is left
# alone, so check-bundle-links.sh can report it.
# ---------------------------------------------------------------------------
rewritten=0
while IFS= read -r doc; do
  doc_dir="$(dirname "${doc}")"
  content="$(cat "${doc}")"
  changed=false

  while IFS= read -r target; do
    [ -z "${target}" ] && continue
    path="${target%%#*}"
    fragment="${target#"${path}"}"
    [ -z "${path}" ] && continue
    [ -e "${doc_dir}/${path}" ] && continue

    resolved="$(realpath -m --relative-to="${ROOT}" "${doc_dir}/${path}")"

    # Was this target removed by this script, rather than simply wrong?
    from_dev_only=false
    for dev in "${DEV_ONLY[@]}"; do
      if [ "${resolved}" = "${dev}" ] || [ "${resolved#"${dev}/"}" != "${resolved}" ]; then
        from_dev_only=true
        break
      fi
    done
    ${from_dev_only} || continue

    content="${content//"](${target})"/"](${CANONICAL_BASE}/${resolved}${fragment})"}"
    changed=true
    rewritten=$((rewritten + 1))
  done < <(grep -oE '\]\([^):]+\)' "${doc}" | sed -E 's/^\]\(//; s/\)$//' | grep -v '^#' | sort -u)

  if ${changed}; then
    printf '%s\n' "${content}" >"${doc}"
  fi
done < <(find "${ROOT}" -name '*.md' -type f | sort)

# ---------------------------------------------------------------------------
# 3. The one file that only exists in the bundle.
#
# Someone who downloaded a zip has not read the repository README and has no
# reason to. This is the whole orientation they get, so it states the
# requirement honestly — this bundle runs TrailMQ in Docker — and then gets out
# of the way.
# ---------------------------------------------------------------------------
cat >"${ROOT}/START-HERE.md" <<EOF
# TrailMQ ${VERSION} — evaluation bundle

An MQTT broker that decides whether an action is allowed, enforces that
decision, and keeps a reviewable record of it.

## What you need

- **Docker** 20.10 or newer, with **Docker Compose v2**
  (\`docker compose version\` must work)
- **Bash** — present on Linux and macOS; on Windows use WSL or Git Bash
- Internet access for the first image pull (about 1 GB)

This bundle runs TrailMQ in containers. It does not install anything on your
system, register a service, or write outside this folder.

## Start it

\`\`\`bash
./trailmq try
\`\`\`

That checks prerequisites, generates local credentials and demo certificates,
starts the stack, and then makes TrailMQ decide twice — one MQTT publish that
is allowed and one that is refused — before opening the Web UI.

## Then

\`\`\`bash
./trailmq connect   # everything your own MQTT client needs, on one screen
./trailmq verify    # the same proof as a reproducible PASS/FAIL run
./trailmq reset     # back to a clean evaluation
./trailmq help      # everything else
\`\`\`

## Remove it

\`\`\`bash
./trailmq purge     # stop containers and delete everything generated here
\`\`\`

Then delete this folder. Nothing remains outside it except the downloaded
container images, which \`docker image rm\` removes.

## Prefer to be shown?

A 20-minute technical walkthrough, no sales deck — write to
**contact@trailmq.com** with your broker, your use case, and the one thing you
want to understand.

Full documentation: \`README.md\` and \`docs/\`.
EOF

printf 'Staged bundle content (%s link(s) repointed to the canonical docs).\n' "${rewritten}"
