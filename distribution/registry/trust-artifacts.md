# Trust artifacts on the registries

How signatures, SBOMs and provenance are actually published, and how that was
established. Recorded because the plan for this area assumed a layout that does
not match what is on the registry, and because the first attempt to check it
asked the wrong question and drew the wrong conclusion.

Observed against the published `3.1.0` images on Docker Hub and GHCR.

## SBOM and provenance are OCI-native

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

## The signature is a referrer, not a tag

An earlier probe looked for the conventional cosign tag names
(`:sha256-<digest>.sig`), found nothing, and recorded the signature layout as
unconfirmed. **That probe tested the wrong thing.** Absent tags are not absent
signatures: cosign 3.x — the line this release's pipeline installs — publishes
signatures through the OCI 1.1 referrers API instead of the legacy tag scheme,
and the release workflow signs `repo@DIGEST` rather than a tag.

Asked the right way, both registries answer. Against the referrers API for the
published index digest:

```text
GET /v2/rainergewalt/trailmq-backend/referrers/sha256:f6b1df74…
  application/vnd.dev.sigstore.bundle.v0.3+json   sha256:b17c1460…

GET /v2/rainergewalt/trailmq-frontend/referrers/sha256:1886412c…
  application/vnd.dev.sigstore.bundle.v0.3+json   sha256:975ae8bd…
```

GHCR carries the same, and additionally exposes the OCI 1.1 fallback tag
(`:sha256-f6b1df74…`), which is why an inspect by tag name succeeds there and
not on Docker Hub. Both are correct; the difference is discovery, not content.

The bundle for the backend states what it covers:

```text
mediaType      application/vnd.dev.sigstore.bundle.v0.3+json
predicateType  https://sigstore.dev/cosign/sign/v1
subject        sha256:f6b1df74…            the published 3.1.0 index
cert SAN       https://github.com/RainerGewalt/MQTrail/.github/workflows/release.yml@refs/heads/master
issuer         https://token.actions.githubusercontent.com
build          .../actions/runs/31332524936/attempts/10
rekor          transparency-log entry with an inclusion proof
```

The certificate identity is the one the public documentation pins, reached over
`refs/heads/master` — which the documented regexp admits alongside tags.

**What this does not establish:** the above is a read of the published
artifacts. It shows that a cosign signature exists, that it names the release
workflow, and that its subject is exactly the digest the `3.1.0` tag resolves
to. It is not a cryptographic verification — the certificate chain to Fulcio,
the signature itself and the Rekor inclusion proof are checked by `cosign
verify` and by nothing here. The release pipeline runs that verification against
the digest it published, and the command in the README repeats it.

## Consequence

Publishing trust artifacts as OCI referrers was listed as an improvement to
make. For SBOM, provenance and signatures alike it is the state already, so
there is no migration to plan.

What did need fixing was the documentation: it told readers to verify a tag
without saying that the signature is only discoverable by a client that speaks
OCI 1.1 referrers. A reader on cosign 2.x would have run the documented command,
seen nothing, and concluded the published claim was false.

**When checking this again, ask the registry for referrers of the digest.**
Probing tag names tests a convention this pipeline does not use, and a negative
result means only that.

## The published image is single-platform

The 3.1.0 index carries `linux/amd64` only. This is fine for Docker Desktop on
Windows x64, which is the evaluation target. It does mean an Apple Silicon
evaluator runs under emulation, and it is worth stating deliberately rather
than discovering during a walkthrough.
