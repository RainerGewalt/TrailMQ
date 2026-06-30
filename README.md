# TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![License](https://img.shields.io/badge/License-Proprietary%20Evaluation-blue)](LICENSE)

TrailMQ is an audit-first MQTT control plane. It runs MQTT traffic through
policy enforcement and records reviewable evidence around broker decisions,
queue behavior, authentication, and audit-chain integrity.

The public repository is a Docker-first evaluation package: CLI launcher,
recipes, configuration, and documentation. The backend and frontend are shipped
as Docker images.

## Start locally

Requirements:

- Docker 20.10+
- Docker Compose v2+
- Bash on Linux, macOS, or WSL

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq quickstart
```

That selects `Secure MQTT Core`, generates local demo certificates and
evaluation passwords, and starts the stack. Use `./trailmq launch` only if you
want the guided menu.

Default local surfaces:

| Surface  | URL or address                |
| -------- | ----------------------------- |
| Web UI   | `http://localhost/trailmq/`   |
| REST API | `http://localhost/api/v1`     |
| MQTT TLS | `localhost:8883`              |
| MQTT WS  | `ws://localhost/mqtt`         |

Evaluation passwords are generated on first launch and stored in:

```text
recipes/secure-mqtt-core/secrets/testadmin.pwd
recipes/secure-mqtt-core/secrets/testuser.pwd
```

You can print them again with:

```bash
./trailmq credentials
```

## What you can evaluate

- TLS-secured MQTT access
- role-based users and permissions
- controlled topic configuration
- policy resolution and validation
- queue and dead-letter review
- audit records and audit-chain validation
- evidence-oriented exports and product read models

TrailMQ can support traceability and regulated engineering practices, but it
does not certify a system as GMP, GxP, CSV, Annex 11, or 21 CFR Part 11
compliant. Compliance depends on the validated system, procedures, users,
infrastructure, and organizational controls around it.

## CLI

| Command            | Purpose                                      |
| ------------------ | -------------------------------------------- |
| `./trailmq quickstart` | One-command local evaluation setup       |
| `./trailmq start`  | Start or repair the local evaluation setup   |
| `./trailmq launch` | Guided first run                             |
| `./trailmq up`     | Start the active recipe                      |
| `./trailmq down`   | Stop the active recipe                       |
| `./trailmq status` | Show services, ports, audit state, plugins   |
| `./trailmq open`   | Show local URLs for the active recipe        |
| `./trailmq credentials` | Show generated local evaluation login  |
| `./trailmq logs`   | Tail logs for the active recipe              |
| `./trailmq doctor` | Check Docker, config, certs, secrets, ports  |
| `./trailmq certs`  | Generate local demo certificates             |
| `./trailmq reset`  | Stop stack and wipe runtime data             |
| `./trailmq purge`  | Remove runtime data, certs, secrets, state   |

Running `./trailmq` without arguments prints the command menu.

## Starter kits

| Starter kit                | Status    | Purpose                                            |
| -------------------------- | --------- | -------------------------------------------------- |
| Secure MQTT Core           | Available | Policy enforcement, audit trail, evidence chain    |
| Explain Decisions          | Planned   | Decision traces for broker decisions              |
| Live vs Historical KPI     | Planned   | Compare live MQTT values with historical context   |

Starter kits live under [`recipes/`](recipes/). The available stack is
[`recipes/secure-mqtt-core/`](recipes/secure-mqtt-core/).

## Repository map

```text
TrailMQ/
├── trailmq                     CLI launcher
├── recipes/                    self-contained Docker starter kits
│   ├── secure-mqtt-core/       available evaluation stack
│   └── coming-soon/            planned recipes
├── scripts/                    CLI subcommand implementations
├── plugins/catalog.yaml        planned plugin catalog
└── docs/                       quickstart, architecture, troubleshooting
```

Runtime data, generated certificates, generated secrets, logs, and audit
archives are ignored by git.

## Useful docs

| Document | Use it for |
| -------- | ---------- |
| [Quickstart](docs/quickstart.md) | Minimal first run |
| [Secure MQTT Core](recipes/secure-mqtt-core/README.md) | API walkthrough and recipe details |
| [Architecture](docs/architecture.md) | Product model and audit-chain concept |
| [Plugins](docs/plugins.md) | Planned extension model |
| [Troubleshooting](docs/troubleshooting.md) | Common first-run issues |
| [Contributing](CONTRIBUTING.md) | Public repo contribution scope |
| [Security](SECURITY.md) | Vulnerability reporting |

## Configuration

Copy `.env.example` to `.env` when you need to pin images or avoid local port
conflicts:

```bash
cp .env.example .env
```

Common overrides:

```env
TRAILMQ_HTTP_PORT=8080
TRAILMQ_MQTT_TLS_PORT=8884
TRAILMQ_BACKEND_IMAGE=rainergewalt/trailmq-backend:latest
TRAILMQ_FRONTEND_IMAGE=rainergewalt/trailmq-frontend:latest
```

Then run:

```bash
./trailmq start
```

## License

TrailMQ is distributed under a proprietary evaluation license. It is free for
personal learning, local demos, and non-production technical evaluation.
Production use, commercial use, managed hosting, redistribution, or use as a
customer-facing service requires a separate commercial agreement.

See [LICENSE](LICENSE). Commercial contact: https://trailmq.com
