# Architecture

TrailMQ separates three concerns that most MQTT products conflate:

1. **Transport** — moving messages between clients
2. **Enforcement** — deciding which messages are allowed, by whom, under which constraints
3. **Evidence** — recording an immutable, verifiable record of every decision

Most brokers do (1) well and treat (2) and (3) as bolt-ons. TrailMQ is built
from the evidence layer outwards.

## The flow

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

Each layer has one job, writes an audit entry when it runs, and hands off to
the next. A policy denial is not a log line — it is an evidence block linked
to the previous block.

## What's in the box today

The `secure-mqtt-core` recipe contains the first three layers:

- **Transport**: TLS MQTT broker (port 8883), WebSocket MQTT (via nginx at `/mqtt`)
- **Enforcement**: role-based access control, topic permissions, rate limits
- **Evidence**: cryptographic audit chain, archival on disk, export endpoints

The fourth layer — **Plugins** — is the extension path. See
[`plugins/catalog.yaml`](../plugins/catalog.yaml) for planned plugins.

## Why recipes?

A recipe bundles a specific combination of Core features and Plugins into a
ready-to-run stack. You don't "configure TrailMQ" — you pick a recipe that
matches your goal.

```text
recipes/
├── secure-mqtt-core/            baseline — what you run for secure, audited MQTT
├── coming-soon/                 placeholders for planned recipes
```

Each recipe is self-contained: its own Docker Compose file, its own config,
its own certs and data directories. Running two recipes side-by-side will
not work out of the box (they compete for ports and container names) —
that's deliberate, because recipes are meant to be the whole deployment
unit, not components you mix.

## Why the audit chain matters

Regulated environments don't ask "is the broker running?" They ask:

- *At 14:03 last Tuesday, who published to that topic, and who authorized it?*
- *Prove that this sequence of messages was delivered in order.*
- *Show me the decision record for every denied connection in the last 30 days.*

TrailMQ answers these by producing an append-only chain where each entry
references the hash of the previous one. You don't "search the logs" —
you verify the chain and export the relevant slice.

## What TrailMQ is not

- **Not a dashboard.** No real-time gauges, no Grafana-style panels. The Web
  UI is a read-focused evidence viewer.
- **Not a payload inspector.** TrailMQ records *that* a message was published,
  by whom, under which policy — not the payload contents.
- **Not a generic IoT platform.** No device provisioning, firmware updates,
  or tenant management.

These are deliberate omissions. Every feature TrailMQ adds must fit the
audit-first model; otherwise it lives outside the product.
