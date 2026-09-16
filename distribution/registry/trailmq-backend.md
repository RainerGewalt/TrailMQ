# TrailMQ Backend

Policy-controlled MQTT runtime for industrial and regulated systems.

> **This is a runtime image.** It expects configuration, certificates and a
> companion frontend. To evaluate TrailMQ, use the TrailMQ Evaluation Package
> below rather than starting this image on its own.

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq try
```

One command: it checks prerequisites, generates local credentials and demo
certificates, starts the stack, then makes TrailMQ decide twice — once where the
client is allowed and once where it is not — and opens the Web UI.

## Current release

| | |
| --- | --- |
| Version | `{{version}}` |
| Companion frontend | `rainergewalt/trailmq-frontend:{{frontend_version}}` |
| Evaluation package | https://github.com/RainerGewalt/TrailMQ |
| Documentation | https://github.com/RainerGewalt/TrailMQ#readme |
| Website | https://trailmq.com |
| Intended use | Local, non-production technical evaluation |
| License | Proprietary evaluation license |
| Security reports | https://github.com/RainerGewalt/TrailMQ/blob/master/SECURITY.md |

Also published to GHCR as `ghcr.io/rainergewalt/trailmq-backend`.

## What the runtime does

TrailMQ is the broker. Standard MQTT clients connect to it directly — no proxy,
no sidecar, no SDK.

- Terminates authenticated MQTT over TLS and MQTT over WebSocket.
- Decides every publish and subscribe against two independent gates: the role's
  permission, and the namespace/topic rule.
- Fails closed — a namespace with no explicit topic rule stays denied.
- Records a refusal with the user, role, client, action, topic, time and reason
  needed to investigate it later.
- Maintains a hash-linked system/action audit chain that can be validated inside
  the product.
- Serves a REST API for topics, effective settings, policies, queues and
  evidence-oriented functions.

## Verification

Images are built by an automated pipeline and signed keyless with cosign, with
an SBOM and `mode=max` provenance attached. All three hang off the published
index as OCI referrers and attestations rather than as extra tags, so
verification needs **cosign 3.x** — there is no `.sig` tag, and not finding one
says nothing about whether the image is signed.

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/RainerGewalt/MQTrail/\.github/workflows/release\.yml@refs/(tags|heads)/.+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  rainergewalt/trailmq-backend:{{version}}
```

Treat signatures, digests, SBOMs and attestations as evidence for the specific
tag you evaluate.

## Trust and evidence scope

Worth reading before treating this image as a compliance surface. The product
states these same limits in its own UI.

**Covered by the integrity verdict:** the hash-linked system and action store —
sign-ins, administrative changes, identity and role changes, policy and
topic-rule changes.

**Not covered:** MQTT message evidence, including publish and subscribe
refusals, is recorded in a separate store that the verdict does not walk. The
product labels those records `Outside validated scope`. The chain is also
neither externally anchored nor digitally signed, so it demonstrates internal
consistency rather than third-party custody.

## Intended purpose

TrailMQ Evaluation Preview is intended solely for local, non-production
technical evaluation. It is not intended for production operation,
safety-related functions, life-safety systems, emergency control, or use where
failure could directly result in injury, physical damage, or interruption of
critical operations. Production use requires a separately assessed TrailMQ
production offering and written agreement.

The generated users and demo certificates are not deployment-ready. The
safety-related exclusion is the one boundary a commercial agreement about the
Evaluation Preview does not lift.

Full statement:
[Intended purpose](https://github.com/RainerGewalt/TrailMQ#intended-purpose) ·
[License](https://github.com/RainerGewalt/TrailMQ/blob/master/LICENSE)

Commercial and technical contact: **contact@trailmq.com**
