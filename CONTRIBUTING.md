# Contributing to TrailMQ

This public repository contains the Docker-first evaluation package for
TrailMQ: launcher scripts, starter-kit recipes, configuration examples, and
documentation.

The proprietary backend and frontend source code are not part of this
repository. Contributions here should therefore focus on the public evaluation
surface.

## Useful contribution areas

- README and docs improvements
- clearer quickstart and troubleshooting guidance
- recipe configuration improvements
- safer local defaults
- shell script fixes for the public CLI
- examples that make local evaluation easier
- issue reports with reproducible first-run failures

## Before opening a change

Every pull request against `master` runs the public distribution gate. Run it
yourself first, from the repository root:

```bash
.github/scripts/check-distribution.sh
```

It takes well under a minute and checks what this repository publishes: that the
Compose stack parses and still honours the documented port overrides, that the
launcher scripts are sound, that `recipe.yaml`, `nginx.conf`, `config.yaml` and
Compose still agree about images and ports, that the hardened defaults are still
declared, and that the documented first run is still reachable from a fresh
clone.

It needs Docker Compose v2 and `jq`. Nothing is started, built or published, and
no image other than the pinned `shellcheck` linter is pulled.

If your change touches the gate itself, also run its negative controls, which
re-break the distribution one regression at a time and confirm each is caught:

```bash
.github/scripts/negative-controls.sh
```

If Docker is not available to you, say so in the pull request — CI will run the
gate either way.

## Pull request scope

Keep changes small and reviewable. A good public-repo change should explain:

- what user-facing problem it solves
- which files changed
- how it was verified
- whether it changes evaluation behavior, ports, credentials, or data paths

Do not commit generated runtime data, certificates, secrets, logs, local
database files, or audit archives.

## Licensing

By submitting a contribution, you agree that it can be used under the TrailMQ
license terms described in [LICENSE](LICENSE).
