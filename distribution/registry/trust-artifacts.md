# Trust artifacts on the registries

Notes on how signatures, SBOMs and provenance are actually published today.
Recorded because the plan for this area assumed a layout that turns out not to
match what is on the registry, and a migration should not be started from an
assumption.

Observed against `rainergewalt/trailmq-backend:3.1.0` on Docker Hub.

## SBOM and provenance are already OCI-native

They are in-index attestation manifests, which is the modern layout — not
separate tags:

```text
rainergewalt/trailmq-backend:3.1.0
└── index (sha256:f6b1df74…)
    ├── linux/amd64            the image
    └── unknown/unknown        attestation-manifest
        └── vnd.docker.reference.type: attestation-manifest
            vnd.docker.reference.digest: sha256:edf694aa…
```

The `unknown/unknown` platform entry is how buildx carries attestations inside
the index. Tooling that does not understand it ignores it; `docker buildx
imagetools inspect` and cosign do.

## No `.sig` tags were found

The concern that cosign artifacts clutter the human-facing tag list did not
reproduce. Probing the conventional cosign tag names against the index digest
returned nothing:

```text
:sha256-f6b1df74….sig    absent
:sha256-f6b1df74….sbom   absent
:sha256-f6b1df74….att    absent
```

That is one probe against one tag, not a full audit. Cosign may attach to the
per-platform digest rather than the index digest, or the release pipeline may
already publish signatures as referrers. **Before any migration work is
planned, confirm against the release pipeline in the source project** — the
answer lives there, not here.

## The published image is single-platform

The 3.1.0 index carries `linux/amd64` only. This is fine for Docker Desktop on
Windows x64, which is the evaluation target. It does mean an Apple Silicon
evaluator runs under emulation, and it is worth stating deliberately rather
than discovering during a walkthrough.

## Consequence for the plan

Publishing trust artifacts as OCI referrers was listed as an improvement to
make. For SBOM and provenance it appears to be the state already. What remains
open is only the signature layout, and that question is answered in the release
pipeline rather than on the registry page.
