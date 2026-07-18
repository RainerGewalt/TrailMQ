# TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![License](https://img.shields.io/badge/License-Proprietary%20Evaluation-blue)](LICENSE)

TrailMQ 3.0.0 Evaluation Preview is an audit-first MQTT control plane for
machine integrations. It runs MQTT traffic through authentication, topic policy,
queue handling, and broker decision capture, then exposes the result as
reviewable evidence.

The public repository is a Docker-first evaluation package: CLI launcher,
recipes, configuration, documentation, and local demo material. Backend and
frontend source are not published here; the runtime is shipped as Docker images.

The intended evaluator journey is intentionally small:

```text
Unknown MQTT connection -> adopt it as an integration -> inspect observed
communication and effective access -> review recorded evidence
```

## Evaluation Preview

The included web UI is the compact TrailMQ Evaluation Preview. It exposes four
public surfaces and keeps the richer product workspace out of the public runtime:

| Surface | What it is for |
| --- | --- |
| Overview | Backend/broker status, fixed KPI summary, integration lifecycle, unknown connections, attention counts, live-topic visibility, and recent activity. |
| Integrations | Adopt unknown live connections and review known integrations by state, observed topics, effective access, latest evidence, and next action. |
| Evidence | Filter and replay the recorded evidence timeline. Rows are labelled by provenance such as Recorded, Reconstructed, Simulated, Sample, or Unavailable. |
| Admin | Read-only runtime health, readiness, build/system information, integration/topic summary, and basic users/roles. |

`#/dashboard` is a legacy alias for Overview in the public Preview. Specialist
routes, plugin administration, raw topic tooling, simulation, configurable
dashboards, and advanced governance workbenches are not exposed by this public
package.

TrailMQ Pro is a separate private preview with the broader interface and more
specialist workflows. It is not included in this repository and is not generally
available from this package. For private-preview interest, contact
`contact@trailmq.com`; do not send credentials, certificates, logs, or production
payloads by email.

## Start Locally

Requirements:

- Docker 20.10+
- Docker Compose v2+
- Bash on Linux, macOS, or WSL

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq quickstart
```

`quickstart` selects the `Secure MQTT Core` recipe, generates local demo
certificates and random evaluation passwords, then starts Docker Compose.

Default local surfaces:

| Surface | URL or address |
| --- | --- |
| Web UI | `http://localhost/trailmq/` |
| REST API | `http://localhost/api/v1` |
| Health | `http://localhost/health` |
| Readiness | `http://localhost/ready` |
| MQTT TLS | `localhost:8883` |
| MQTT WS | `ws://localhost/mqtt` |

Print generated local credentials at any time:

```bash
./trailmq credentials
```

Generated evaluation passwords are stored in:

```text
recipes/secure-mqtt-core/secrets/testadmin.pwd
recipes/secure-mqtt-core/secrets/testuser.pwd
```

These credentials and the generated certificates are for local evaluation only.
Replace or remove them before any non-local deployment.

## Connect An MQTT Client

For a local MQTT client, configure:

| Setting | Local value |
| --- | --- |
| Host | `localhost` |
| Port | `8883` |
| CA file | `recipes/secure-mqtt-core/certs/ca_cert.pem` |
| Client ID | A stable unique ID, for example `line1-sensor-01` |
| Publisher user | `testuser` with password from `secrets/testuser.pwd` |
| Admin user | `testadmin` with password from `secrets/testadmin.pwd` |

Publish a sample reading:

```bash
MQTT_PASS="$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)"

mosquitto_pub -h localhost -p 8883 \
  --cafile recipes/secure-mqtt-core/certs/ca_cert.pem \
  -i line1-sensor-01 \
  -u testuser \
  -P "${MQTT_PASS}" \
  -t "public/line1/temperature" \
  -m '{"value":23.4,"unit":"C"}'
```

If you add a subscribe-capable user in
[`recipes/secure-mqtt-core/config.yaml`](recipes/secure-mqtt-core/config.yaml),
the subscriber shape is:

```bash
mosquitto_sub -h localhost -p 8883 \
  --cafile recipes/secure-mqtt-core/certs/ca_cert.pem \
  -i line1-viewer \
  -u <subscriber-user> \
  -P '<password>' \
  -t 'public/line1/#'
```

After publishing, open the UI:

- Overview shows runtime status, lifecycle counts, live-topic visibility, and
  recent activity.
- Integrations lets you adopt the detected client and inspect its access state.
- Evidence shows recorded events and replayable proof where the backend recorded
  enough detail.

## What You Can Evaluate

- TLS-secured MQTT access.
- Role-based users and permissions.
- Controlled topic configuration.
- Policy resolution and validation.
- Queue and dead-letter review.
- Audit records and audit-chain validation.
- Evidence-oriented exports and product read models.
- A compact, honest Preview UI that separates recorded, reconstructed,
  simulated, sample, and unavailable states.

## CLI

| Command | Purpose |
| --- | --- |
| `./trailmq quickstart` | One-command local evaluation setup |
| `./trailmq start` | Start or repair the local evaluation setup |
| `./trailmq launch` | Guided first run |
| `./trailmq up` | Start the active recipe |
| `./trailmq down` | Stop the active recipe |
| `./trailmq status` | Show services, ports, audit state, plugins |
| `./trailmq open` | Show local URLs for the active recipe |
| `./trailmq credentials` | Show generated local evaluation login |
| `./trailmq logs` | Tail logs for the active recipe |
| `./trailmq doctor` | Check Docker, config, certs, secrets, ports |
| `./trailmq certs` | Generate local demo certificates |
| `./trailmq reset` | Stop stack and wipe runtime data |
| `./trailmq purge` | Remove runtime data, certs, secrets, state |

Running `./trailmq` without arguments prints the command menu.

## Starter Kits

| Starter kit | Status | Purpose |
| --- | --- | --- |
| Secure MQTT Core | Available | Policy enforcement, audit trail, evidence chain |
| Explain Decisions | Planned | Decision traces for broker decisions |
| Live vs Historical KPI | Planned | Compare live MQTT values with historical context |

Starter kits live under [`recipes/`](recipes/). The available stack is
[`recipes/secure-mqtt-core/`](recipes/secure-mqtt-core/).

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

Pin `TRAILMQ_BACKEND_IMAGE` and `TRAILMQ_FRONTEND_IMAGE` to immutable release
tags once the corresponding release images are published.

Then run:

```bash
./trailmq start
```

## Verification And Release Evidence

The source project defines automated gates for backend Go tests, frontend
type/unit/build checks, Preview bundle verification, Docker image builds,
security scanning, SBOM/provenance, checksums, and cosign signing.

Treat exact test counts, workflow URLs, image digests, SBOMs, attestations, and
signatures as evidence for the specific release tag being evaluated. Do not
treat screenshots, demo records, or local generated data as production evidence.

## CRA And GMP/GxP Boundary

TrailMQ can support security, traceability, evidence review, release identity,
SBOM/provenance, and operational documentation activities that are relevant to
CRA-readiness and regulated environments.

TrailMQ is not a CRA conformity declaration, CE marking, GMP/GxP/CSV validation,
EU GMP Annex 11 compliance package, or 21 CFR Part 11 compliance package by
itself. Validation, intended-use assessment, procedural controls, risk
management, and legal/regulatory determinations remain the deployer's
responsibility.

## Repository Map

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

## Useful Docs

| Document | Use it for |
| --- | --- |
| [Quickstart](docs/quickstart.md) | Minimal first run |
| [Secure MQTT Core](recipes/secure-mqtt-core/README.md) | API walkthrough and recipe details |
| [Architecture](docs/architecture.md) | Product model and audit-chain concept |
| [Plugins](docs/plugins.md) | Planned extension model |
| [Troubleshooting](docs/troubleshooting.md) | Common first-run issues |
| [Contributing](CONTRIBUTING.md) | Public repo contribution scope |
| [Security](SECURITY.md) | Vulnerability reporting |

## License

TrailMQ is distributed under a proprietary evaluation license. It is free for
personal learning, local demos, and non-production technical evaluation.
Production use, commercial use, managed hosting, redistribution, or use as a
customer-facing service requires a separate commercial agreement.

See [LICENSE](LICENSE). Commercial contact: `contact@trailmq.com`.
