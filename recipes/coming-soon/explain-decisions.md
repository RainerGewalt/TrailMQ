# Explain Decisions *(planned)*

Secure MQTT Core plus the **Decision Trace** plugin.

Every broker decision — accept, deny, rate-limit, policy hit — produces a
trace linked to the audit chain that answers: *why did that happen?*

## Status
Planned. Tracked alongside the Decision Trace plugin. See
[`plugins/catalog.yaml`](../../plugins/catalog.yaml).

## What the recipe will add
- `decision-trace` plugin enabled in config
- New UI views under `/trailmq/decisions/`
- REST endpoints under `/api/v1/decisions/`
- Audit events enriched with the matching trace ID
