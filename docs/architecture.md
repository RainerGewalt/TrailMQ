# Architecture and trust model

TrailMQ combines three concerns at the MQTT boundary:

1. **Transport** — accept standard MQTT clients and move allowed messages.
2. **Enforcement** — authenticate identities and apply role plus namespace
   policy before an action proceeds.
3. **Evidence** — preserve attributable system actions and decisions in a
   hash-linked record that can be checked later.

The product is useful when all three must be evaluated together. If you only
need message transport, a conventional broker is usually the simpler choice.

## Request flow

```text
MQTT client
    │
    │ TLS / WebSocket, username + password
    ▼
Transport and authentication
    │ known identity and roles
    ▼
Role permission check
    │ publish/subscribe + MQTT topic filter
    ▼
Namespace/topic ACL check
    │ allowed role on this path
    ├── allow ──▶ broker action proceeds
    └── deny  ──▶ action is blocked
                    │
                    ▼
             decision evidence
```

Both authorization checks must allow the action. This distinction matters: a
role with `publish:*` still cannot publish into an unknown namespace until a
topic ACL grants that role.

The evaluation defaults are:

- `public/#` — open to known roles, still subject to their action permissions;
- `restricted/#` — admin only;
- all other namespaces — denied until explicitly governed.

## Components in the current recipe

The `secure-mqtt-core` recipe contains:

| Component | Responsibility |
| --- | --- |
| Backend | MQTT over TLS, MQTT WebSocket, REST API, authentication, policy enforcement, persistence, audit functions |
| Frontend | Review-oriented Evaluation Preview |
| nginx | Local reverse proxy for the Web UI, REST API, and MQTT WebSocket |
| `config.yaml` | Roles, configured users, TLS, origins, queue, and audit settings |
| SQLite runtime state | Persisted users, topics, policies, queues, and audit data |

Clients do not need a TrailMQ SDK, proxy, or sidecar. They connect to the
backend with standard MQTT libraries.

## What the evidence chain proves

The system/action audit chain links each entry to the hash of its predecessor.
If an existing linked entry is edited without rebuilding the subsequent chain,
validation detects the mismatch.

This provides **local tamper evidence**. It does not make the database
physically immutable and is not, by itself:

- an external timestamp, signature, or notarization service;
- WORM storage;
- proof that every MQTT payload is included;
- proof of completeness outside the configured capture paths;
- a compliance certification.

`./trailmq verify` and `/api/v1/audit/validatechain` validate the
**system/action audit chain**. Topic-level message auditing is a separate
capture path; do not infer that the same endpoint validates or exposes every
message payload. The [tamper-evidence scenario](scenarios/04-tamper-evidence.md)
demonstrates the exact scope of the public check.

## Why decisions are first-class records

Operational and review questions are usually about decisions, not just
connections:

- Who tried to publish to a sensitive namespace?
- Which role and action were evaluated?
- Was the attempt allowed or blocked?
- Which effective topic settings applied?
- Has the recorded system/action history changed afterwards?

TrailMQ keeps identity, authority, requested action, topic, and outcome close to
the enforcement point so an evaluator does not have to reconstruct the basic
decision from unrelated files and broker logs.

## Configuration state and runtime state

The recipe uses files for declared configuration and a database for runtime
state. They are related but not interchangeable.

```text
.env                         host ports and image selection
config.yaml                  declared product configuration
runtime database             persisted operational and identity state
certs/ and secrets/          local TLS and credential material
```

In particular, `authsyncmode: "merge"` merges configured users into runtime
state at startup. Omitting a previously created user from `config.yaml` does
not delete that runtime identity. See [Access management](access-management.md)
for the safe revocation procedure.

## Why recipes are deployment units

A recipe bundles a working combination of configuration, services, and
capabilities:

```text
recipes/
├── secure-mqtt-core/   available evaluation stack
└── coming-soon/        documented product direction, not runnable releases
```

Each recipe owns its Compose definition, configuration, certificates, secrets,
data, logs, and audit archive. The launcher tracks one active recipe. Running
multiple recipes side by side requires manual port, container-name, and state
isolation and is not the default evaluation path.

## Deliberate product boundaries

TrailMQ is not intended to replace:

- an IoT device-provisioning or firmware-management platform;
- a Grafana-style telemetry dashboard;
- a general-purpose payload data lake;
- organizational identity governance and approval processes;
- compliance validation for the complete deployed system.

The Evaluation Preview is also not the full operations workspace. It focuses on
reviewing status, records, decisions, users, and roles. Operational changes use
the REST API and configuration in the public evaluation package.

## Continue evaluating

- [Quickstart](quickstart.md) — start and verify the stack.
- [Connect an MQTT client](connect-a-client.md) — apply the two-gate access
  model from real clients.
- [Guided scenarios](scenarios/README.md) — exercise governance, queues, QoS,
  denials, and tamper detection.
- [Secure MQTT Core reference](../recipes/secure-mqtt-core/README.md) — inspect
  the recipe and REST API.
