# Plugins

Plugins extend TrailMQ Core with additional capabilities that stay linked to
the audit chain. They are the extension path between the baseline stack and
the specialized recipes.

> **Status, honestly:** the plugin system is planned. The entries below
> describe the shape it will take. None of these plugins ship today — see
> [`plugins/catalog.yaml`](../plugins/catalog.yaml) for the source of truth.

## The model

```text
Core runs today.
Plugins are the extension path.
Everything stays audit linked.
```

Plugins never bypass the audit chain. If a plugin produces a value, emits a
decision, or accepts external input, the operation is recorded as an audit
event with a reference back to the plugin that produced it.

## Planned plugins

### Decision Trace
Explains why a broker decision was made. Every accept, deny, or rate-limit
event produces a trace linked to the audit chain. Makes the policy layer
inspectable instead of opaque.

### Historical Context Feed
Accepts historical comparison values through REST and makes them available
to other plugins (typically KPI Lite) for deviation checks.

### KPI Lite
Compares live MQTT values with stored historical context. Emits a deviation
metric that is recorded in the audit chain.

### Domain Context Lite
Extracts machine, batch or metric context from topic patterns and payload
headers. Attaches the context to audit events so evidence queries can filter
by domain concepts instead of raw topic strings.

## How plugins will ship

- **Embedded** for the initial plugins — they are part of the backend
  binary and are enabled per recipe via config.
- **External** (separate containers talking over a stable interface) is on
  the roadmap for later plugins that don't need to run inside the broker.

## How they map to recipes

| Recipe                     | Plugins enabled                                                                |
| -------------------------- | ------------------------------------------------------------------------------ |
| `secure-mqtt-core`         | none                                                                           |
| `explain-decisions` *(planned)* | decision-trace                                                            |
| `live-vs-historical-kpi` *(planned)* | decision-trace, historical-context-feed, kpi-lite, domain-context-lite |

Recipes are the unit of deployment. Plugins are the unit of capability.
