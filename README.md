# TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![License](https://img.shields.io/badge/License-Proprietary%20Evaluation-blue)](LICENSE)

> **Audit-first MQTT control plane.** TrailMQ runs MQTT traffic through policy
> enforcement and records a cryptographically chained, reviewable record of
> every broker decision — who connected, what was published, which policy
> applied, and whether the evidence is still intact.

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq quickstart        # → http://localhost/trailmq/
```

That one command picks the `Secure MQTT Core` stack, generates local demo
certificates and evaluation passwords, and starts everything with Docker.

---

## What this repository is

This is the **public, Docker-first evaluation package** for TrailMQ:

- a **CLI launcher** (`./trailmq`) that wraps Docker Compose,
- ready-to-run **recipes** (starter kits) under [`recipes/`](recipes/),
- the **configuration** and **documentation** you need to evaluate it.

The backend and frontend ship as **Docker images** — their source is not part
of this repo. You don't build anything; you run images and point them at config.

**Who it's for:** engineers evaluating secure, auditable MQTT for industrial,
regulated, or traceability-sensitive environments, and anyone who wants to see
how policy enforcement plus an audit chain behave in practice.

```text
MQTT message → TrailMQ Core (transport + auth)
            → Policy decision (who / what / how)
            → Audit evidence  (cryptographically chained record)
```

See [docs/architecture.md](docs/architecture.md) for the full model.

---

## Try it in 30 seconds

Requirements: **Docker 20.10+**, **Docker Compose v2+**, and **Bash** (Linux,
macOS, or WSL).

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq quickstart
```

Wait for Docker to pull the images, then open the Web UI. Default surfaces:

| Surface  | URL or address              |
| -------- | --------------------------- |
| Web UI   | `http://localhost/trailmq/` |
| REST API | `http://localhost/api/v1`   |
| MQTT TLS | `localhost:8883`            |
| MQTT WS  | `ws://localhost/mqtt`       |

Login passwords are generated on first launch and stored in
`recipes/secure-mqtt-core/secrets/`. Print them again any time with:

```bash
./trailmq credentials
```

New here? The [Quickstart](docs/quickstart.md) walks through the first run.

---

## Where do I change what?

Everything you can adjust lives in **two places**: the root `.env` (runtime
knobs like ports and image tags) and the recipe's `config.yaml` (product
behavior). This table maps intent to the exact place:

| I want to change…                  | Edit / run                                                                      |
| ---------------------------------- | ------------------------------------------------------------------------------- |
| Host ports (80, 8883)              | `.env` → `TRAILMQ_HTTP_PORT`, `TRAILMQ_MQTT_TLS_PORT`                            |
| Which images / image tags          | `.env` → `TRAILMQ_BACKEND_IMAGE`, `TRAILMQ_FRONTEND_IMAGE`                       |
| Users, roles, permissions          | `recipes/secure-mqtt-core/config.yaml` → `users:` / `roles:`                     |
| Evaluation passwords               | `recipes/secure-mqtt-core/secrets/*.pwd` (or `./trailmq credentials` to read)    |
| TLS certificates                   | drop into `recipes/secure-mqtt-core/certs/`, or run `./trailmq certs`            |
| Queue / dead-letter behavior       | `recipes/secure-mqtt-core/config.yaml` → `queue_advanced:`                       |
| Audit retention / export           | `recipes/secure-mqtt-core/config.yaml` → `audit_advanced:`, `audit_retention_days:` |
| CORS / WebSocket origins           | `recipes/secure-mqtt-core/config.yaml` → `cors:`, `mqtt_ws_allowed_origins:`     |
| Log verbosity                      | `recipes/secure-mqtt-core/config.yaml` → `log_level:`                            |
| Reverse-proxy routes               | `recipes/secure-mqtt-core/nginx.conf`                                            |

To set custom ports or pin image versions, start from the template:

```bash
cp .env.example .env      # edit, then:
./trailmq start
```

Runtime data, generated certificates, secrets, logs, and audit archives are
**gitignored** — the repository stays clean no matter what you run locally.

---

## What you can evaluate

- TLS-secured MQTT access
- role-based users and permissions
- controlled topic configuration
- policy resolution and validation
- queue and dead-letter review
- audit records and audit-chain validation
- evidence-oriented exports and product read models

> TrailMQ can support traceability and regulated engineering practices, but it
> does **not** certify a system as GMP, GxP, CSV, Annex 11, or 21 CFR Part 11
> compliant. Compliance depends on the validated system, procedures, users,
> infrastructure, and organizational controls around it.

---

## CLI reference

```bash
./trailmq            # prints the command menu
```

| Command                 | Purpose                                      |
| ----------------------- | -------------------------------------------- |
| `./trailmq quickstart`  | One-command local evaluation setup           |
| `./trailmq start`       | Start or repair the local evaluation setup   |
| `./trailmq launch`      | Guided first run (pick a starter kit)        |
| `./trailmq up`          | Start the active recipe                      |
| `./trailmq down`        | Stop the active recipe                       |
| `./trailmq status`      | Show services, ports, audit state, plugins   |
| `./trailmq open`        | Show local URLs for the active recipe        |
| `./trailmq credentials` | Show generated local evaluation login        |
| `./trailmq logs`        | Tail logs for the active recipe              |
| `./trailmq doctor`      | Check Docker, config, certs, secrets, ports  |
| `./trailmq certs`       | Generate local demo certificates             |
| `./trailmq reset`       | Stop stack and wipe runtime data             |
| `./trailmq purge`       | Remove runtime data, certs, secrets, state   |

---

## Starter kits

A recipe bundles a specific combination of features into a ready-to-run stack.
You don't "configure TrailMQ" from scratch — you pick a recipe that matches
your goal. They live under [`recipes/`](recipes/).

| Starter kit            | Status    | Purpose                                          |
| ---------------------- | --------- | ------------------------------------------------ |
| Secure MQTT Core       | Available | Policy enforcement, audit trail, evidence chain  |
| Explain Decisions      | Planned   | Decision traces for broker decisions             |
| Live vs Historical KPI | Planned   | Compare live MQTT values with historical context |

The available stack is [`recipes/secure-mqtt-core/`](recipes/secure-mqtt-core/).

---

## Repository map

```text
TrailMQ/
├── trailmq                     CLI launcher (start here)
├── .env.example                runtime overrides (ports, image tags)
├── recipes/                    self-contained Docker starter kits
│   ├── secure-mqtt-core/       available evaluation stack
│   │   ├── config.yaml         product behavior (users, queue, audit, …)
│   │   ├── docker-compose.yaml the stack definition
│   │   └── nginx.conf          reverse-proxy routes
│   └── coming-soon/            planned recipes
├── scripts/                    CLI subcommand implementations
├── plugins/catalog.yaml        planned plugin catalog
└── docs/                       quickstart, architecture, troubleshooting
```

---

## Documentation

| Document | Use it for |
| -------- | ---------- |
| [Quickstart](docs/quickstart.md) | Minimal first run |
| [Secure MQTT Core](recipes/secure-mqtt-core/README.md) | API walkthrough and recipe details |
| [Architecture](docs/architecture.md) | Product model and audit-chain concept |
| [Plugins](docs/plugins.md) | Planned extension model |
| [Troubleshooting](docs/troubleshooting.md) | Common first-run issues |
| [Contributing](CONTRIBUTING.md) | Public-repo contribution scope |
| [Security](SECURITY.md) | Vulnerability reporting |

---

## License

TrailMQ is distributed under a **proprietary evaluation license**. It is free
for personal learning, local demos, and non-production technical evaluation.
Production use, commercial use, managed hosting, redistribution, or use as a
customer-facing service requires a separate commercial agreement.

See [LICENSE](LICENSE). Commercial contact: https://trailmq.com
