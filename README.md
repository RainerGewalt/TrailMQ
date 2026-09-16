<p align="center"><img src="docs/media/trailmq-logo.png" width="440" alt="TrailMQ" /></p>

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![Release](https://img.shields.io/badge/published%20release-3.1.1-blue)](https://hub.docker.com/r/rainergewalt/trailmq-backend/tags)
[![Distribution gate](https://github.com/RainerGewalt/TrailMQ/actions/workflows/distribution-gate.yml/badge.svg?branch=master)](https://github.com/RainerGewalt/TrailMQ/actions/workflows/distribution-gate.yml)
[![License](https://img.shields.io/badge/License-Proprietary%20Evaluation-blue)](LICENSE)
[![Signed images](https://img.shields.io/badge/images-cosign%20signed-0e6e5b)](#release-quality-and-security)

# Know why MQTT access was allowed or denied

**Policy-controlled MQTT for industrial systems, with attributable and
reviewable access decisions.**

When an MQTT action is refused on a plant network, "it did not work" is not an
answer. Someone still has to say **who acted, under which role, on which topic,
and why the answer was no**. TrailMQ is a self-hosted MQTT broker that decides
that question where the traffic enters the system, enforces the decision, and
keeps it reviewable afterwards. Standard MQTT clients connect to it directly.

> Scope in one line: the built-in integrity verdict covers the hash-linked
> system/action audit chain; MQTT decision records are recorded and reviewed
> separately. [What the verdict does and does not prove](#trust-and-evidence-scope).

## One denied decision, end to end

This is a refusal from the evaluation stack — one publish, one decision:

```text
testuser
PUBLISH
restricted/ops/config

DENIED
reason=acl_role_not_in_topic_scope
```

TrailMQ did four things here, in a single pass:

1. **Decided** the action — the `publisher` role holds no rule that brings
   `restricted/ops/config` into scope for it.
2. **Enforced** the decision — the publish was refused at the broker, so the
   payload never reached a subscriber.
3. **Recorded** it with the principal, role, action, topic, outcome and reason:

   ```text
   DENY user="testuser" roles=[publisher] action=publish
        topic="restricted/ops/config" reason=acl_role_not_in_topic_scope
   ```

4. **Made it reviewable** — the same decision appears in **Activity** as a
   *Publish refused · Denied* row carrying the actor, the MQTT client id and the
   topic that was evaluated, with the reason in plain language: "No rule brings
   this topic into scope for any role this identity holds."

The same identity publishing to `public/demo/temperature` is allowed, and the
payload is observed arriving at a subscriber. Both outcomes come out of the same
two gates — see [How access is decided](#how-access-is-decided).

Both are reproducible from a clean clone — that is the next section.

## Run the proof yourself

Requirements: **Docker 20.10+**, **Docker Compose v2**, **Bash** (Linux, macOS,
or WSL), and internet access for the first image pull.

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ

./trailmq quickstart   # prepare and start the local evaluation stack
./trailmq verify       # the decision proof
```

`quickstart` creates local evaluation credentials and certificates, then starts
the Docker stack. `verify` exercises the product rather than just checking
container health:

```text
[PASS] Runtime ready
[PASS] MQTT TLS listener accepts authenticated clients
[PASS] Authorized publish reached the subscriber   public/demo/temperature
[PASS] Unauthorized publish was blocked            restricted/ops/config
[PASS] Denial recorded with user, role, action and topic
[PASS] REST API authentication issues a token
[PASS] System/action audit chain intact

7/7 checks passed
```

That third line is the one to read closely: the payload is observed **arriving at
a subscriber**, not merely acknowledged by the broker. Allowed and delivered are
different claims, and this proof makes the delivered one.

The run takes about 30 seconds once the images are available. No local MQTT
client is required; `verify` falls back to a temporary Docker client.

### From the proof to the decision

```bash
./trailmq open          # open the Web UI (prints every endpoint too)
./trailmq credentials   # print the generated local login
```

Sign in at **http://localhost/trailmq/** as `testadmin`, open **Activity**, and
filter **Outcome: Denied**. The refused publish from the section above is there
with its actor, client, topic and reason attached — the decision you just
triggered, as a reviewer would read it later.

### The same run, as one command

`./trailmq try` runs no proof of its own: it sequences the two commands above —
prerequisites, setup, start, readiness, proof — restates their result in
sentences, and opens the Web UI at the end.

```bash
./trailmq try
```

```text
✓ Authorized MQTT publish was delivered
  testuser → public/demo/temperature → reached the subscriber

✓ Restricted publish was refused
  testuser → restricted/ops/config → blocked
  because restricted/# is admin-only and testuser is not an admin

✓ The refusal was recorded as an attributable decision
  DENY user="testuser" roles=[publisher] action=publish
       topic="restricted/ops/config" reason=acl_role_not_in_topic_scope

✓ Evidence verified: system and action audit chain
  <n> entries hash-checked, chain intact
```

The output above is illustrative. The entry count depends on what your run
actually did — a first run on an empty database produces a small number, not a
large one.

```bash
./trailmq connect       # everything your own MQTT client needs, on one screen
```

Prefer to be shown rather than to install? A 20-minute technical walkthrough, no
sales deck — write to **contact@trailmq.com** with your broker, your use case,
and the one thing you want to understand.

If setup fails, run `./trailmq doctor` and see
[Troubleshooting](docs/troubleshooting.md).

## What TrailMQ brings together

TrailMQ brings access enforcement and decision review into one workflow. The
decision, the reason and the record come out of the same pass that allows or
refuses the action — they are not reassembled afterwards from separate systems.

| Step | What TrailMQ does |
| --- | --- |
| **Authenticate** | The client proves an identity over MQTT/TLS or MQTT over WebSocket. |
| **Authorize** | Two independent gates: the role's own permission, and the namespace/topic rule that scopes where it applies. Unknown namespaces stay denied until a rule grants them. |
| **Enforce** | The action is carried out or refused at the broker, before the payload travels further. |
| **Record** | User, role, client, action, topic, time, outcome — and, for a refusal, the reason. |
| **Review** | The record is readable in **Activity**, each row stating its outcome, whether it was written down, and whether the validated chain covers it. |

Two things travel separately, and the product keeps them separate on purpose:

```text
MQTT client
    │  standard MQTT over TLS or WebSocket
    ▼
TrailMQ Core
authenticate → authorize → enforce
                    │
                    ├── MQTT decision record ──→ reviewable in Activity
                    │
                    └── system/action audit ───→ hash-linked chain, verdict in Activity
```

In one sentence:

> TrailMQ decides, enforces, and records at the point where MQTT traffic enters
> the system.

Want to see that against a broker you already run? Scenario 0,
[Why not just use a broker?](docs/scenarios/00-why-not-just-a-broker.md), runs
the same three commands against `eclipse-mosquitto` in its default open
configuration and against TrailMQ, side by side, and prints both outcomes.

## Evaluation Preview

The public images ship a compact review UI with four surfaces. **Activity** is
where a decision is reviewed: it carries the recorded events, their reasons and
the integrity verdict together — there is no separate Evidence page.

| Understand | Control | Observe | Explain |
| --- | --- | --- | --- |
| **Overview** | **Access** | **Clients** | **Activity** |
| Is it running, and what needs attention? | Who may publish or subscribe where? | Which clients are connected right now? | What was allowed or denied, and why? |

| | |
| --- | --- |
| ![TrailMQ Overview showing broker and backend status, connected clients, and refused operations in the last 24 hours](docs/media/preview-overview.jpg) | ![TrailMQ Access view showing evaluation users with their roles and the topic rules that scope MQTT communication](docs/media/preview-access.jpg) |
| **Overview** — see at a glance that the broker is running, how many clients are connected, and that one operation was refused and is waiting to be reviewed. | **Access** — see and manage who exists, which role each identity holds, and which topic rules bring a topic into scope for those roles. |
| ![TrailMQ Clients view showing connected publishers and subscribers with their user, role and connection time](docs/media/preview-clients.jpg) | ![TrailMQ Activity view filtered to denied outcomes, showing an attributed refused publish and the integrity verdict scope panel](docs/media/preview-activity.jpg) |
| **Clients** — see which publishers and subscribers are connected right now, and which identity each one authenticated as. | **Activity** — inspect why an MQTT action was refused, and read exactly what the integrity verdict covers and what it does not. |

The core path — **decision → why → review** — is part of this evaluation
package. The record, the reason an action was refused and the stated scope of
the integrity verdict are all in the public images; none of it starts after a
purchase. What this UI does not carry is the wider operations workspace: it
manages evaluation users and topic rules, not day-to-day operations at scale.
That is what TrailMQ Pro is for; see [Editions](#editions).

## Trust and evidence scope

This is the part worth reading before you treat the Preview as a compliance
surface. The product states these limits in its own UI, next to the verdict.

**What the integrity verdict covers.** The hash-linked chain walks the system and
action store: sign-ins, administrative changes, identity and role changes, policy
and topic-rule changes. `./trailmq verify` validates that chain, and **Activity**
shows the same verdict with the number of entries checked.

**What it does not cover.** MQTT message evidence — including publish and
subscribe refusals — is recorded in its own store, which that verdict does not
walk. The product labels those records `Outside validated scope` and repeats the
limit beside the verdict. If your requirement is a tamper-checked record of every
individual MQTT decision, that is not what this check proves today. The chain is
also not externally anchored and not digitally signed, so it demonstrates
internal consistency rather than third-party custody.

### Intended purpose

TrailMQ Evaluation Preview is intended solely for local, non-production
technical evaluation. It is not intended for production operation,
safety-related functions, life-safety systems, emergency control, or use where
failure could directly result in injury, physical damage, or interruption of
critical operations. Production use requires a separately assessed TrailMQ
production offering and written agreement.

That paragraph is word for word
[section 2 of the license](LICENSE), and it is the one boundary a commercial
agreement about the Evaluation Preview does not lift: a safety-related
deployment would need a different product, separately assessed for that
purpose. Everything else on this page describes what the Preview does well
within that purpose.

Further evaluation boundaries:

- **Local, non-production evaluation only.** Demo certificates and generated
  users are not deployment-ready. Review the [license](LICENSE).
- **Config sync uses merge semantics.** Removing a user from `config.yaml` or
  deleting its password file does not revoke a user already persisted in the
  runtime database. Follow [Access management](docs/access-management.md) for
  safe offboarding.
- **Preview counters are not delivery proof.** Use `./trailmq verify`, an MQTT
  subscriber, and the recorded decision details when evaluating enforcement.
- **Compliance is a system property.** TrailMQ can support traceability and
  review workflows; it is not by itself a CRA conformity assessment, CE
  declaration, GMP/GxP validation, Annex 11 package, or 21 CFR Part 11 package.

These boundaries are intentional documentation, not hidden assumptions. They keep
the evaluation reproducible and every claim tied to observable evidence.

## Is TrailMQ a fit?

| Good evaluation fit | Probably not the right tool |
| --- | --- |
| MQTT actions must be attributable and reviewable | You only need basic message transport |
| Sensitive namespaces should fail closed | Anonymous/open-by-default access is intentional |
| Policy denials need an inspectable reason | Broker logs already satisfy the review requirement |
| Local integrity checks support an evidence workflow | You need externally notarized or WORM evidence out of the box |
| Existing standard MQTT clients must keep working | You need device provisioning, firmware management, or telemetry dashboards |

The public package answers technical-fit questions locally. Production and
commercial fit require the corresponding TrailMQ edition and agreement.

## Choose your evaluation path

| Your goal | Start here | Typical time |
| --- | --- | --- |
| See a decision for yourself | `./trailmq quickstart` → `./trailmq verify`, or `./trailmq try` | ~2 min plus first image pull |
| Be shown it instead | **contact@trailmq.com** — 20-minute technical walkthrough | 20 min |
| Compare it with a plain broker | [Scenario 0](docs/scenarios/00-why-not-just-a-broker.md) | ~5 min |
| Connect your own application | `./trailmq connect` → [Connect an MQTT client](docs/connect-a-client.md) | ~10 min |
| Test allow, deny, governance, and tamper detection | [Guided scenarios](docs/scenarios/README.md) | 10–30 min |
| Evaluate architecture or API fit | [Architecture](docs/architecture.md) → [Secure MQTT Core](recipes/secure-mqtt-core/README.md) | as needed |

The complete task-oriented documentation map is in
[docs/README.md](docs/README.md).

## What you can evaluate today

- **Secure MQTT transport:** authenticated MQTT over TLS and MQTT over
  WebSocket.
- **Fail-closed access:** role permissions plus namespace/topic policy; unknown
  namespaces stay closed until explicitly granted.
- **Reviewable denials:** blocked actions retain the user, role, client, action,
  topic, time, outcome, and reason needed for investigation.
- **Integrity checking:** system/action audit entries form a hash-linked chain
  that can be validated — and deliberately tampered with — in a local scenario.
- **Access management in the UI:** create evaluation users and topic rules from
  the **Access** surface, or drive the same operations through the REST API.
- **Scriptable control:** the REST API exposes topics, effective settings,
  policies, queues, and evidence-oriented functions.
- **Standard clients:** use `mosquitto`, Python `paho-mqtt`, Node.js `mqtt.js`,
  or a browser WebSocket client without a TrailMQ SDK.

### How access is decided

Every MQTT action must pass two independent gates:

1. The user's **role permission** allows the action and MQTT topic filter.
2. The **namespace/topic rule** allows that role on the requested path.

The default evaluation policy is deliberately easy to test:

| Namespace | Default behavior |
| --- | --- |
| `public/#` | Available to authenticated roles, subject to role permissions |
| `restricted/#` | Admin only |
| everything else | Denied until a topic rule explicitly grants roles |

This means a role with `publish:*` can still be denied by the second gate. See
[Connect an MQTT client](docs/connect-a-client.md#how-trailmq-decides-allow-or-deny)
for examples.

## Connect a client

TrailMQ is the broker. Point a standard MQTT client at the TLS listener and use
one of the generated evaluation identities.

| Setting | Default value |
| --- | --- |
| MQTT TLS | `mqtts://localhost:8883` |
| MQTT WebSocket | `ws://localhost/mqtt` |
| CA certificate | `recipes/secure-mqtt-core/certs/ca_cert.pem` |
| Publisher | `testuser` — password via `./trailmq credentials` |
| Administrator/subscriber | `testadmin` — password via `./trailmq credentials` |
| Immediately allowed test topic | `public/demo/temperature` |

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
PW=$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)

mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$PW" \
  -t 'public/demo/temperature' -q 1 \
  -m '{"value":21.4,"unit":"degC"}'
```

Complete CLI, Python, Node.js, and browser examples are in
[Connect an MQTT client](docs/connect-a-client.md).

## Configure the evaluation

There are two configuration surfaces:

- root `.env` — host ports and Docker image tags;
- `recipes/secure-mqtt-core/config.yaml` — product behavior.

Product configuration is read when the backend starts; restart it after direct
file changes unless a guided scenario says the API applies a change live.

| Change | Edit or run |
| --- | --- |
| Host ports or image tags | copy `.env.example` to `.env` |
| Users, roles, and permissions | `config.yaml` → `users:` / `roles:` |
| Evaluation passwords | `./trailmq credentials` or `secrets/*.pwd` |
| TLS certificates | `./trailmq certs` or `certs/` |
| Queue and dead-letter behavior | `config.yaml` → `queue_advanced:` |
| Audit retention and export | `config.yaml` → `audit_advanced:` / `audit_retention_days:` |
| Browser origins | `config.yaml` → `cors:` / `mqtt_ws_allowed_origins:` |

For a port conflict:

```bash
cp .env.example .env
# Set TRAILMQ_HTTP_PORT=8080 and/or TRAILMQ_MQTT_TLS_PORT=8884
./trailmq start
```

Generated certificates, credentials, logs, databases, and audit archives are
gitignored.

## What is in this repository

This is the public, Docker-first evaluation package for TrailMQ.

**What you get today is `3.1.1`** — that is what the recipe pulls and what is
published on Docker Hub and GHCR. `3.0.0` remains available if you need to pin
the previous release; see [.env.example](.env.example). The product reports its
own build in `./trailmq verify`, so you can always tell which one you are running.

This package contains:

- the `./trailmq` launcher and diagnostics;
- the ready-to-run `secure-mqtt-core` Docker recipe;
- [`release.yaml`](release.yaml), the release contract naming every component
  version that belongs to this release;
- configuration examples and guided scenarios;
- the documentation needed to evaluate and connect TrailMQ.

`release.yaml` is the reason the version above can be trusted. The Compose
defaults, the recipe metadata, the badge at the top of this file, the evaluation
bundle and `./trailmq version` are all checked against it, so there is exactly
one place a release version is decided rather than five places that have to be
remembered. It states composition only — no image digests, no checksums, no
signature status, because none of those are knowable until after the release is
built and published.

The backend and frontend are delivered as signed Docker images. Their source is
not included in this repository, and the evaluation license does not permit
production or commercial use.

Every change to this package is gated: pull requests must pass the
[distribution gate](.github/workflows/distribution-gate.yml), which checks the
release contract, Compose validity, image and port consistency, the hardened
container defaults, the launcher scripts, and that the documented first run is
still reachable from a fresh clone.

## Release quality and security

Published releases are built by an automated pipeline and signed keyless with
cosign. The source project gates releases with backend and frontend tests, live
MQTT/REST allow-deny checks, dependency and static analysis, secret and
filesystem scanning, and Dockerfile linting.

Treat test counts, signatures, image digests, SBOMs, and attestations as evidence
for the specific release tag you evaluate. Security reports follow
[SECURITY.md](SECURITY.md).

Published images carry an SBOM, `mode=max` provenance and a keyless cosign
signature, all attached to the published index rather than to extra tags. The
signature is a Sigstore bundle reachable through the OCI 1.1 referrers API, so
verifying it needs **cosign 3.x**: there is no `:sha256-….sig` tag to look for,
and its absence is not evidence of an unsigned image. The release pipeline
verifies the signature in the same run that produces it, against a certificate
identity pinned to the release workflow, and you can repeat that check against
whichever tag you evaluate:

```bash
# The tag is a pointer; the signature covers the index it currently resolves
# to. A manifest is content-addressed, so hashing it *is* reading its digest —
# and this works on every buildx version, unlike --format.
digest="sha256:$(docker buildx imagetools inspect --raw \
  rainergewalt/trailmq-backend:3.1.1 | sha256sum | cut -d' ' -f1)"

cosign verify \
  --certificate-identity-regexp '^https://github.com/RainerGewalt/MQTrail/\.github/workflows/release\.yml@refs/(tags|heads)/.+$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "rainergewalt/trailmq-backend@${digest}"
```

What that signature covers, and what reading the published artifacts does and
does not establish on its own, is recorded in
[distribution/registry/trust-artifacts.md](distribution/registry/trust-artifacts.md).
That document is a dated observation of the `3.1.0` images, digests and all. It
is kept as it was written rather than renumbered to each new release, because a
record of what was observed stops being one the moment it is edited to match
something else.

**TrailMQ 3.1.0 was published on a documented release-owner decision after the
automated runtime gate refused the candidate** over unresolved validation and
test-harness findings. The raw gate result was preserved rather than
reclassified, the audit-immutability contract executed and passed in that same
run, and no required audit evidence was lost. The
[v3.1.0 release record](https://github.com/RainerGewalt/TrailMQ/releases/tag/v3.1.0)
holds the exact evidence, image digests, and validation detail.

Stating this is the same standard this product asks of its own evidence: a gate
that refused is reported as having refused.

## Editions

| | Evaluation Preview (this repository) | TrailMQ Pro |
| --- | --- | --- |
| UI | Overview, Access, Clients and Activity — the decision record, its reason and the integrity verdict included, plus evaluation user and topic-rule management | The same decision review, with an advanced operations workspace on top |
| Backend | Same broker, published as the evaluation image | Same broker, licensed for production and commercial use |
| Intended use | Local, non-production technical evaluation | Production and commercial use |
| Availability | Public Docker images | On request |

The difference between the two columns is licensing and what is offered with it,
not a technically limited binary. Nothing in the evaluation image is disabled by
a licence key, an activation check or a trial timer, because no such mechanism
exists. What governs production use is the [LICENSE](LICENSE), not the software.

That includes the part worth evaluating: **decision → why → review** is in the
public images. If the explanation of a refusal only showed up after a purchase,
there would be nothing left to evaluate.

For production or commercial evaluation, contact **contact@trailmq.com** or visit
[trailmq.com](https://trailmq.com).

Evaluating TrailMQ with a real MQTT use case? Share your setup experience or
request direct onboarding support at **contact@trailmq.com**.

TrailMQ sends nothing to us. There is no TrailMQ telemetry, analytics or
call-home. By default, the evaluation stack does not export your topics,
payloads, identities or operational metadata. Operator-configured features such
as audit export, replication and OCSP may make outbound connections.

## CLI essentials

| Command | Purpose |
| --- | --- |
| `./trailmq try` | Guided first run: set up, start, prove, open the Web UI |
| `./trailmq connect` | Endpoint, credentials, CA and test topics for your own client |
| `./trailmq quickstart` | Prepare and start the local evaluation stack |
| `./trailmq verify` | Run the seven-check decision proof |
| `./trailmq open` | Open the Web UI and print local endpoints |
| `./trailmq credentials` | Print generated evaluation credentials |
| `./trailmq status` | Show runtime and audit status |
| `./trailmq doctor` | Diagnose Docker, config, certificates, credentials, and ports |
| `./trailmq down` | Stop the stack and keep local data |
| `./trailmq reset` | Stop the stack and remove runtime data. Generated certificates, credentials and the active recipe are kept |
| `./trailmq purge` | Remove the recipe runtime, including the generated certificates and credentials |

Run `./trailmq help` for the complete command list.

## Documentation

| Document | Use it for |
| --- | --- |
| [Documentation home](docs/README.md) | Choose the shortest path for your task |
| [Quickstart](docs/quickstart.md) | First successful proof and login |
| [Connect a client](docs/connect-a-client.md) | CLI, Python, Node.js, WebSocket, and access rules |
| [Guided scenarios](docs/scenarios/README.md) | Allow, deny, govern, queue, QoS, and tamper exercises |
| [Access management](docs/access-management.md) | Add, rotate, and safely revoke evaluation users |
| [Architecture](docs/architecture.md) | Trust model, layers, and evidence scope |
| [Secure MQTT Core](recipes/secure-mqtt-core/README.md) | Recipe and REST API reference |
| [Troubleshooting](docs/troubleshooting.md) | Common setup and runtime issues |
| [Contributing](CONTRIBUTING.md) | Public-repository contribution scope |

## License

TrailMQ is distributed under a proprietary evaluation license. It is free for
personal learning, local demos, and non-production technical evaluation.
Production, commercial, managed-hosting, redistribution, and customer-facing use
require a separate agreement.

See [LICENSE](LICENSE). Commercial contact: **contact@trailmq.com** ·
[trailmq.com](https://trailmq.com)
