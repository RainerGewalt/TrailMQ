# 🔌 TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![License](https://img.shields.io/badge/License-Proprietary%20Evaluation-blue)](LICENSE)

**Audit-first MQTT control plane.**

TrailMQ controls MQTT messages, enforces policies, and preserves verifiable
audit evidence.

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq launch
```

---

## Choose your Starter Kit

| Starter Kit                |    Status | Purpose                                                             |
| -------------------------- | --------: | ------------------------------------------------------------------- |
| **Secure MQTT Core**       | Available | Run TrailMQ with policy enforcement, audit trail and evidence chain |
| **Explain Decisions**      |   Planned | Add decision traces for broker decisions                            |
| **Live vs Historical KPI** |   Planned | Compare live MQTT values with external historical context           |

Each Starter Kit is a self-contained recipe under [`recipes/`](./recipes/).

---

## What `./trailmq launch` looks like

```text
🚀 TrailMQ Launcher

Available now

  [1] Secure MQTT Core         — policies, audit trail, evidence chain

Preview  (planned for a future release)

  [ ] Explain Decisions        planned
  [ ] Live vs Historical KPI   planned
  [ ] Audit Evidence Demo      planned

Choose a Starter Kit › 1

→ Recipe selected:  secure-mqtt-core
✓ Runtime folders prepared.
✓ Config ready: recipes/secure-mqtt-core/config.yaml

! No TLS certificates found.

  [1] Generate local demo certificates  (self-signed, local use only)
  [2] Use my own certificates
  [3] Continue without certificates

Choose › 1

! Generating LOCAL DEMO certificates. Do not use for production.
→ Creating root CA…
✓ Root CA created.
→ Creating server key and CSR…
→ Signing server certificate with local CA…
✓ Server certificate signed.
✓ JWT secret generated.
✓ Evaluation credentials generated.
✓ Active recipe set.

→ Starting stack…
✓ Stack is up.

Open TrailMQ
  Web UI    http://localhost/trailmq/
  REST API  http://localhost/api/v1
  MQTT TLS  localhost:8883
  MQTT WS   ws://localhost/mqtt
```

---

## What `./trailmq status` looks like

```text
TrailMQ Status
Recipe: Secure MQTT Core (secure-mqtt-core)

Core
✓ Backend            running
✓ Frontend           running
✓ Reverse Proxy      running

Audit
✓ Audit              enabled
✓ Evidence chain     enabled
○ Archived files     0

Plugins
○ Decision Trace             planned
○ Historical Context Feed    planned
○ KPI Lite                   planned
○ Domain Context Lite        planned

Open
  Web UI       http://localhost/trailmq/
  REST API     http://localhost/api/v1
  MQTT TLS     localhost:8883
  MQTT WS      ws://localhost/mqtt
```

---

## REST API and Review Surface

TrailMQ is not only controlled through the Web UI. The same product surface is
available through the REST API.

Default local API endpoint:

```text
http://localhost/api/v1
```

Use it to:

- check health, readiness and metrics
- log in with the generated evaluation users
- inspect controlled MQTT topics
- resolve and validate policies
- review queue and dead-letter state
- read audit entries and validate the audit chain
- export evidence-oriented records for review

This makes TrailMQ scriptable for local evaluation, demos, monitoring and
integration checks.

For the full API walkthrough, see
[`recipes/secure-mqtt-core/README.md`](recipes/secure-mqtt-core/README.md).

---

## Control MQTT. Keep the Evidence.

```text
MQTT Message
    ↓
TrailMQ Core            transport + authentication
    ↓
Policy Decision         enforcement (who, what, how)
    ↓
Audit Evidence          cryptographically chained record
    ↓
Plugins add context     decision trace, historical context, KPIs
```

TrailMQ does not rely only on inspecting logs afterwards. It applies rules at
runtime and records audit evidence around the resulting broker decisions.

See [`docs/architecture.md`](docs/architecture.md) for the longer story.

---

## Internal Verification

TrailMQ is developed with an internal scenario-based verification approach.

The internal verification suite is not part of the public evaluation package,
but it is used during development to exercise TrailMQ through its real product
surfaces:

- MQTT over TLS
- REST authentication
- topic control
- policy resolution
- queue and dead-letter behavior
- audit recording
- audit-chain validation
- health, readiness and metrics endpoints
- negative and security behavior

The goal is not only to check whether MQTT messages can be transported.

The goal is to check whether TrailMQ remains controllable, inspectable and
reviewable under realistic conditions.

This keeps the product promise grounded:

> TrailMQ should not only move MQTT messages. It should help explain what
> happened around them.

---

## 🧭 CLI

| Command              | What it does                                      |
| -------------------- | ------------------------------------------------- |
| `./trailmq launch`   | Guided Starter Kit selection and first run        |
| `./trailmq up`       | Start the active recipe                           |
| `./trailmq down`     | Stop the active recipe                            |
| `./trailmq status`   | Show services, ports, audit status                |
| `./trailmq logs`     | Tail logs for the active recipe                   |
| `./trailmq doctor`   | Check Docker, ports, certs, config                |
| `./trailmq certs`    | Generate local demo certificates                  |
| `./trailmq reset`    | Stop stack and wipe runtime data                  |
| `./trailmq purge`    | Remove stack, runtime data, certs, secrets, state |

Running `./trailmq` with no arguments shows the menu.

---

## 🧱 What's in this repo

```text
TrailMQ/
├── trailmq                     CLI launcher
├── recipes/                    Starter Kits — self-contained stacks
│   ├── secure-mqtt-core/       ✅ available today
│   └── coming-soon/            🔜 planned recipes
├── scripts/                    CLI subcommand implementations
├── plugins/catalog.yaml        Plugin catalog (with planned status)
└── docs/                       Concept docs
```

---

## 🔒 What TrailMQ is — and is not

**TrailMQ is:** an audit-first control plane for MQTT, built for teams operating
in regulated or audit-sensitive environments, focused on controlled messaging,
reviewability and evidence-oriented behavior.

TrailMQ can support regulated engineering practices by exposing audit records,
policy decisions, queue state and evidence-oriented exports.

TrailMQ itself does not certify a system as GMP, GxP, CSV, Annex 11 or
21 CFR Part 11 compliant. Compliance depends on the full validated system,
configuration, operating procedures, user management, infrastructure and
organizational controls.

**TrailMQ is not:** a payload inspector, a real-time monitoring dashboard,
or a generic IoT cloud broker.

---

## 🚨 Requirements

- Docker 20.10+
- Docker Compose v2+
- Bash (Linux / macOS / WSL on Windows)

---

## 📄 License

Proprietary evaluation license — see [`LICENSE`](LICENSE). Free for personal
learning, non-production evaluation, and demos. Commercial use requires a
separate agreement: https://trailmq.com

---

## 👤 Author

Florian Przybylak (RainerGewalt) · Industrial IIoT · Secure Messaging · Regulated Systems