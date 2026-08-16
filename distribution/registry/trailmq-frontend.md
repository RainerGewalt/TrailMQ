# TrailMQ Frontend

Review and administration UI for the TrailMQ Evaluation Preview.

**Overview · Access · Clients · Activity**

> **This is a runtime image.** It serves the UI for a matching TrailMQ backend
> and does nothing on its own. To evaluate TrailMQ, use the TrailMQ Evaluation
> Package below.

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq try
```

## Current release

| | |
| --- | --- |
| Version | `{{version}}` |
| Companion backend | `rainergewalt/trailmq-backend:{{backend_version}}` |
| Evaluation package | https://github.com/RainerGewalt/TrailMQ |
| Documentation | https://github.com/RainerGewalt/TrailMQ#readme |
| Website | https://trailmq.com |
| Intended use | Local, non-production technical evaluation |
| License | Proprietary evaluation license |
| Security reports | https://github.com/RainerGewalt/TrailMQ/blob/master/SECURITY.md |

Also published to GHCR as `ghcr.io/rainergewalt/trailmq-frontend`.

## The four surfaces

| Surface | Answers |
| --- | --- |
| **Overview** | Is it running, and what needs attention? |
| **Access** | Who may publish or subscribe where? |
| **Clients** | Which clients are connected right now? |
| **Activity** | What was allowed or denied, and why? |

Recorded events and the integrity verdict both live on **Activity**; there is no
separate evidence page. Evaluation users and topic rules can be created from
**Access**, or through the REST API.

Operations beyond that — deeper governance and decision explanations — belong to
the advanced workspace in TrailMQ Pro, not to this image.

## Verification

Built by the same automated pipeline as the backend and signed keyless with
cosign, with an SBOM and `mode=max` provenance attached.

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/RainerGewalt/MQTrail/\.github/workflows/release\.yml@refs/(tags|heads)/.+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  rainergewalt/trailmq-frontend:{{version}}
```

## Scope

This is the evaluation and review interface for the matching TrailMQ release. It
is a local, non-production technical evaluation surface; production or
commercial use requires a separate agreement.

Commercial and technical contact: **contact@trailmq.com**
