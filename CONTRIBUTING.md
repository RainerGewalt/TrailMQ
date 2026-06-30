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

Run these checks from the repository root when your change touches scripts or
Compose files:

```bash
bash -n trailmq scripts/*.sh
docker compose -f recipes/secure-mqtt-core/docker-compose.yaml config >/dev/null
```

If Docker is not available, mention that in the pull request or issue.

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
