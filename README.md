<p align="center"><img src="docs/media/trailmq-logo.png" width="440" alt="TrailMQ" /></p>

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![Release](https://img.shields.io/badge/published%20release-3.0.0-blue)](https://hub.docker.com/r/rainergewalt/trailmq-backend/tags)
[![License](https://img.shields.io/badge/License-Proprietary%20Evaluation-blue)](LICENSE)
[![Signed images](https://img.shields.io/badge/images-cosign%20signed-0e6e5b)](#release-quality-and-security)

# Govern MQTT access — and keep an attributable decision record

**TrailMQ is a self-hosted MQTT broker with policy enforcement and an
attributable decision record built in.** Clients connect directly using standard
MQTT. TrailMQ authenticates them, decides whether each action is allowed,
enforces that decision, and preserves the outcome for later review.

**What "tamper-evident" covers, precisely.** The hash-linked chain walks the
system and action store: sign-ins, administrative changes, identity and role
changes, policy and topic-rule changes. MQTT message evidence — including
publish and subscribe refusals — is recorded in its own store, which that
verdict does **not** walk. The product states this per record, as
`Outside validated scope`, and states it again beside the verdict. If your
requirement is a tamper-checked record of individual MQTT decisions, that is not
what this check proves today.

It is designed for industrial, regulated, and traceability-sensitive systems
where “the message was sent” is not enough. You also need to know **who acted,
under which role, on which topic, and whether the action was allowed**.

## Prove the core claim locally

Requirements: **Docker 20.10+**, **Docker Compose v2**, **Bash** (Linux, macOS,
or WSL), and internet access for the first image pull.

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq quickstart
./trailmq verify
```

`quickstart` creates local evaluation credentials and certificates, then starts
the Docker stack. `verify` exercises the product rather than just checking
container health:

```text
[PASS] Runtime ready
[PASS] MQTT TLS listener accepts authenticated clients
[PASS] Authorized publish reached the subscriber   public/demo/temperature
[PASS] Unauthorized publish was blocked            restricted/ops/config
[PASS] Denial recorded with user, role, action and topic
[PASS] REST API authentication issues a token
[PASS] System/action audit chain intact

7/7 checks passed
```

The proof takes about 30 seconds after the images are available. No local MQTT
client is required; `verify` falls back to a temporary Docker client.

```bash
./trailmq credentials   # print the generated local login
./trailmq open          # print Web UI, REST, MQTT TLS and WebSocket endpoints
```

Open **http://localhost/trailmq/**, sign in as `testadmin`, then open
**Activity** and filter for **Outcome: Denied**.

If setup fails, run `./trailmq doctor` and see
[Troubleshooting](docs/troubleshooting.md).

## The product difference

A conventional MQTT broker can also be secured with TLS, identities, and ACLs.
TrailMQ's differentiator is that enforcement and review are one product path,
not separate broker configuration and log-analysis tasks.

| Question | Conventional broker setup | TrailMQ evaluation |
| --- | --- | --- |
| May this identity publish here? | Usually decided by broker ACLs | Role permission **and** namespace policy must allow it |
| What happens to unknown namespaces? | Depends on the deployed ACL configuration | Denied by default |
| How do I inspect a denial later? | Correlate configuration and logs | Review an attributed decision: user, role, action, topic, outcome |
| Can I detect edits to the recorded history? | Requires an external evidence pipeline | Validate the hash-linked system/action record — MQTT message evidence is a separate store and is not covered by that check |
| Do clients need a proxy or sidecar? | Product-dependent | No — they connect to TrailMQ as the broker |

```text
MQTT client
    │ standard MQTT over TLS or WebSocket
    ▼
TrailMQ Core ── authenticate ── authorize ── enforce
                                      │
                                      ▼
                              hash-linked evidence
```

In one sentence:

> TrailMQ decides, enforces, and preserves the evidence at the point where MQTT
> traffic enters the system.

For the command-by-command comparison, run
[Why not just use a broker?](docs/scenarios/00-why-not-just-a-broker.md).

## Choose your evaluation path

| Your goal | Start here | Typical time |
| --- | --- | --- |
| See the differentiator | `./trailmq quickstart` → `./trailmq verify` | ~5 min plus first image pull |
| Compare it with a plain broker | [Scenario 0](docs/scenarios/00-why-not-just-a-broker.md) | ~5 min |
| Connect your own application | [Connect an MQTT client](docs/connect-a-client.md) | ~10 min |
| Test allow, deny, governance, and tamper detection | [Guided scenarios](docs/scenarios/README.md) | 10–30 min |
| Evaluate architecture or API fit | [Architecture](docs/architecture.md) → [Secure MQTT Core](recipes/secure-mqtt-core/README.md) | as needed |
| Understand scope before investing time | [Evaluation boundaries](#evaluation-boundaries) | 2 min |

The complete task-oriented documentation map is in
[docs/README.md](docs/README.md).

## Is TrailMQ a fit?

| Good evaluation fit | Probably not the right tool |
| --- | --- |
| MQTT actions must be attributable and reviewable | You only need basic message transport |
| Sensitive namespaces should fail closed | Anonymous/open-by-default access is intentional |
| Policy denials need an inspectable reason | Broker logs already satisfy the review requirement |
| Local integrity checks support an evidence workflow | You need externally notarized or WORM evidence out of the box |
| Existing standard MQTT clients must keep working | You need device provisioning, firmware management, or telemetry dashboards |

The public package answers technical-fit questions locally. Production and
commercial fit require the corresponding TrailMQ edition and agreement.

## What is in this repository

This is the public, Docker-first evaluation package for TrailMQ.

**What you get today is `3.0.0`.** That is what the recipe pulls, and it is what is
published on Docker Hub. Everything below describes that version.

A **3.1.0 Technical Preview** exists. It is built and verified, and it is **not
publicly obtainable** — the images are not on Docker Hub, and this repository does not
contain the source to build them. There is no tag you can pin that will produce it. If
you want to evaluate it before it is published, ask for guided access:
**contact@trailmq.com**.

The product reports its own build on the **Access** page and in `./trailmq verify`, so
you can always tell which one you are looking at.

This package contains:

- the `./trailmq` launcher and diagnostics;
- the ready-to-run `secure-mqtt-core` Docker recipe;
- configuration examples and guided scenarios;
- the documentation needed to evaluate and connect TrailMQ.

The backend and frontend are delivered as signed Docker images. Their source is
not included in this repository, and the evaluation license does not permit
production or commercial use.

## What you can evaluate today

- **Secure MQTT transport:** authenticated MQTT over TLS and MQTT over
  WebSocket.
- **Fail-closed access:** role permissions plus namespace/topic policy; unknown
  namespaces are closed until explicitly granted.
- **Reviewable denials:** blocked actions retain the user, role, action, topic,
  time, and outcome needed for investigation.
- **Integrity checking:** system/action audit entries form a hash-linked chain
  that can be validated and deliberately tampered with in a local scenario.
- **Scriptable control:** the REST API exposes topics, effective settings,
  policies, queues, and evidence-oriented functions.
- **Standard clients:** use `mosquitto`, Python `paho-mqtt`, Node.js `mqtt.js`,
  or a browser WebSocket client without a TrailMQ SDK.

### How access is decided

Every MQTT action must pass two independent gates:

1. The user's **role permission** allows the action and MQTT topic filter.
2. The **namespace/topic ACL** allows that role on the requested path.

The default evaluation policy is deliberately easy to test:

| Namespace | Default behavior |
| --- | --- |
| `public/#` | Available to authenticated roles, subject to role permissions |
| `restricted/#` | Admin only |
| everything else | Denied until a topic explicitly grants roles |

This means a role with `publish:*` can still be denied by the second gate. See
[Connect an MQTT client](docs/connect-a-client.md#how-trailmq-decides-allow-or-deny)
for examples.

## Evaluation Preview

The public images include a compact, review-oriented UI with four surfaces:

| Surface | Answers |
| --- | --- |
| **Overview** | Is it running, and what needs attention next? |
| **Access** | Who may publish and subscribe on which topics? |
| **Clients** | Which publishers and subscribers are connected right now? |
| **Activity** | What was allowed or denied, why, and what is recorded about it? |

Recorded events and the evidence chain live on **Activity** — there is no separate
Evidence page.

<p align="center">
  <img src="docs/media/preview-signin.jpg" width="90%" alt="TrailMQ sign-in for the local evaluation workspace" />
</p>

| Integration records | System/action evidence | Runtime and access overview |
| --- | --- | --- |
| ![Integrations](docs/media/preview-integrations.jpg) | ![Evidence](docs/media/preview-evidence.jpg) | ![Admin](docs/media/preview-admin.jpg) |
| Search and review integration records available to the Preview. | Filter and inspect recorded system and decision events. | Inspect health, runtime information, users, and roles. |

The Preview is primarily a **read and review surface**. Use the REST API and
`config.yaml` for operational changes such as creating governed topics or
changing roles. The advanced operations workspace is part of TrailMQ Pro; see
[Editions](#editions).

## Connect a client

TrailMQ is the broker. Point a standard MQTT client at the TLS listener and use
one of the generated evaluation identities.

| Setting | Default value |
| --- | --- |
| MQTT TLS | `mqtts://localhost:8883` |
| MQTT WebSocket | `ws://localhost/mqtt` |
| CA certificate | `recipes/secure-mqtt-core/certs/ca_cert.pem` |
| Publisher | `testuser` — password via `./trailmq credentials` |
| Administrator/subscriber | `testadmin` — password via `./trailmq credentials` |
| Immediately allowed test topic | `public/demo/temperature` |

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
PW=$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)

mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$PW" \
  -t 'public/demo/temperature' -q 1 \
  -m '{"value":21.4,"unit":"degC"}'
```

Complete CLI, Python, Node.js, and browser examples are in
[Connect an MQTT client](docs/connect-a-client.md).

## Configure the evaluation

There are two configuration surfaces:

- root `.env` — host ports and Docker image tags;
- `recipes/secure-mqtt-core/config.yaml` — product behavior.

Product configuration is read when the backend starts; restart it after direct
file changes unless a guided scenario says the API applies a change live.

| Change | Edit or run |
| --- | --- |
| Host ports or image tags | copy `.env.example` to `.env` |
| Users, roles, and permissions | `config.yaml` → `users:` / `roles:` |
| Evaluation passwords | `./trailmq credentials` or `secrets/*.pwd` |
| TLS certificates | `./trailmq certs` or `certs/` |
| Queue and dead-letter behavior | `config.yaml` → `queue_advanced:` |
| Audit retention and export | `config.yaml` → `audit_advanced:` / `audit_retention_days:` |
| Browser origins | `config.yaml` → `cors:` / `mqtt_ws_allowed_origins:` |

For a port conflict:

```bash
cp .env.example .env
# Set TRAILMQ_HTTP_PORT=8080 and/or TRAILMQ_MQTT_TLS_PORT=8884
./trailmq start
```

Generated certificates, credentials, logs, databases, and audit archives are
gitignored.

## Evaluation boundaries

Read these before treating the Preview as a production-management or compliance
surface:

- **Local, non-production evaluation only.** Demo certificates and generated
  users are not deployment-ready. Review the [license](LICENSE).
- **The UI is review-first.** Topic creation, policy changes, and user lifecycle
  operations currently use the REST API and/or configuration files.
- **Config sync uses merge semantics.** Removing a user from `config.yaml` or
  deleting its password file does not revoke a user already persisted in the
  runtime database. Follow [Access management](docs/access-management.md) for
  safe offboarding.
- **The chain check has a defined scope.** `./trailmq verify` validates the
  system/action audit chain. It does not claim that every MQTT payload is
  exposed in the Preview or covered by that same check.
- **Preview counters are not delivery proof.** Use `./trailmq verify`, an MQTT
  subscriber, and the recorded decision details when evaluating enforcement.
- **Compliance is a system property.** TrailMQ can support traceability and
  review workflows; it is not by itself a CRA conformity assessment, CE
  declaration, GMP/GxP validation, Annex 11 package, or 21 CFR Part 11 package.

These boundaries are intentional documentation, not hidden assumptions. They
make the evaluation reproducible and keep product claims tied to observable
evidence.

## Release quality and security

Published releases are built by an automated pipeline and use keyless cosign
signing. The source project gates releases with backend and frontend tests,
live MQTT/REST allow-deny checks, dependency and static analysis, secret and
filesystem scanning, and Dockerfile linting.

Treat test counts, signatures, image digests, SBOMs, and attestations as
evidence for the specific release tag you evaluate. Security reports follow
[SECURITY.md](SECURITY.md).

That paragraph describes `3.0.0`, the release you can obtain. It does **not** yet
describe the 3.1.0 Technical Preview: the automated pipeline is currently unavailable
to this project, so the preview candidate has been verified locally and has no
pipeline-produced signature, digest or attestation. It is not published, and it will
not be published until it can go through the same gate as every release before it.
Saying so is the same standard this product asks of its own evidence.

## Editions

| | Evaluation Preview (this repository) | TrailMQ Pro |
| --- | --- | --- |
| UI | Compact Overview, Access, Clients and Activity review surfaces | Advanced operations workspace, deeper governance and decision explanations |
| Backend | Hardened evaluation image | Production/commercial backend |
| Intended use | Local, non-production technical evaluation | Production and commercial use |
| Availability | Public Docker images | On request |

For production or commercial evaluation, contact **contact@trailmq.com** or
visit [trailmq.com](https://trailmq.com).

Evaluating TrailMQ with a real MQTT use case? Share your setup experience or request
direct onboarding support at **contact@trailmq.com**. TrailMQ sends no telemetry: no
topics, payloads, identities or operational metadata leave your machine.

## CLI essentials

| Command | Purpose |
| --- | --- |
| `./trailmq quickstart` | Prepare and start the local evaluation stack |
| `./trailmq verify` | Run the seven-check decision proof |
| `./trailmq open` | Print local endpoints |
| `./trailmq credentials` | Print generated evaluation credentials |
| `./trailmq status` | Show runtime and audit status |
| `./trailmq doctor` | Diagnose Docker, config, certificates, credentials, and ports |
| `./trailmq down` | Stop the stack and keep local data |
| `./trailmq reset` | Stop the stack and remove runtime data |

Run `./trailmq help` for the complete command list.

## Documentation

| Document | Use it for |
| --- | --- |
| [Documentation home](docs/README.md) | Choose the shortest path for your task |
| [Quickstart](docs/quickstart.md) | First successful proof and login |
| [Connect a client](docs/connect-a-client.md) | CLI, Python, Node.js, WebSocket, and access rules |
| [Guided scenarios](docs/scenarios/README.md) | Allow, deny, govern, queue, QoS, and tamper exercises |
| [Access management](docs/access-management.md) | Add, rotate, and safely revoke evaluation users |
| [Architecture](docs/architecture.md) | Trust model, layers, and evidence scope |
| [Secure MQTT Core](recipes/secure-mqtt-core/README.md) | Recipe and REST API reference |
| [Troubleshooting](docs/troubleshooting.md) | Common setup and runtime issues |
| [Contributing](CONTRIBUTING.md) | Public-repository contribution scope |

## License

TrailMQ is distributed under a proprietary evaluation license. It is free for
personal learning, local demos, and non-production technical evaluation.
Production, commercial, managed-hosting, redistribution, and customer-facing
use require a separate agreement.

See [LICENSE](LICENSE). Commercial contact: **contact@trailmq.com** ·
[trailmq.com](https://trailmq.com)
