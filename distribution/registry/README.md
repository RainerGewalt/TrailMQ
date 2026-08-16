# Registry surfaces

Docker Hub and GHCR are the first TrailMQ page many people ever see. For a
closed-source product they are also a trust surface: someone deciding whether to
pull an image reads the registry page, not this repository.

This folder holds the canonical text for those pages, so they stop being
independently maintained copy that drifts away from the product.

## The rules

**One source per component, both registries.** `trailmq-backend.md` and
`trailmq-frontend.md` are the text for Docker Hub *and* for the GHCR package
description. There is deliberately no per-registry variant — two files would
mean two truths within a release.

**No literal version numbers.** Registry text may not contain a release version
as a literal. It uses placeholders that are substituted from
[`release.yaml`](../../release.yaml) at publication time:

| Placeholder | Resolves to |
| --- | --- |
| `{{version}}` | the release version |
| `{{backend_version}}` | `runtime.backend` |
| `{{frontend_version}}` | `runtime.frontend` |

A version typed into a registry page is a version nobody updates. The
distribution gate rejects one.

**Short.** The registry page is not a second README. It answers what the image
is, whether this is the thing to start, which release it belongs to, how to
verify it, and what the evidence actually covers. Everything else belongs in the
repository.

**No stale surfaces.** The frontend text names the review surfaces the current
Preview actually ships. When a surface is added or removed, this text changes in
the same release.

## Rendering

```bash
.github/scripts/render-registry.sh text backend     # the page, placeholders resolved
.github/scripts/render-registry.sh labels backend   # OCI labels as key=value
```

`labels` emits the static labels from [`oci-labels.yaml`](oci-labels.yaml) plus
the three that only exist at build time: `version` comes from the release
contract, `revision` and `created` from the build environment.

## What is not here

Image digests, SBOM references, signature status and attestation results. Those
describe a build that has already happened, and belong to the release record
rather than to text that is written before the build runs.
