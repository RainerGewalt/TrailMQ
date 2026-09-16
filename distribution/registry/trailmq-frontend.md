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

The decision, the reason it was refused and the stated scope of the integrity
verdict are all in this image; none of it starts after a purchase. What this
image does not carry is the wider operations workspace — day-to-day operations
at scale belong to TrailMQ Pro.

## Verification

Built by the same automated pipeline as the backend and signed keyless with
cosign, with an SBOM and `mode=max` provenance attached. All three hang off the
published index as OCI referrers and attestations rather than as extra tags, so
verification needs **cosign 3.x** — there is no `.sig` tag, and not finding one
says nothing about whether the image is signed.

```bash
cosign verify \
  --certificate-identity-regexp '^https://github.com/RainerGewalt/MQTrail/\.github/workflows/release\.yml@refs/(tags|heads)/.+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  rainergewalt/trailmq-frontend:{{version}}
```

## Intended purpose

This is the evaluation and review interface for the matching TrailMQ release.

TrailMQ Evaluation Preview is intended solely for local, non-production
technical evaluation. It is not intended for production operation,
safety-related functions, life-safety systems, emergency control, or use where
failure could directly result in injury, physical damage, or interruption of
critical operations. Production use requires a separately assessed TrailMQ
production offering and written agreement.

The safety-related exclusion is the one boundary a commercial agreement about
the Evaluation Preview does not lift.

Full statement:
[Intended purpose](https://github.com/RainerGewalt/TrailMQ#intended-purpose) ·
[License](https://github.com/RainerGewalt/TrailMQ/blob/master/LICENSE)

Commercial and technical contact: **contact@trailmq.com**
