# TrailMQ — Public Repository Instructions

This repository is the **public TrailMQ product entry point and Docker distribution**.

Its README, Compose files, environment templates, Quickstart, examples, troubleshooting,
screenshots and release documentation are **part of the shipped product contract**, not
supporting material.

## The contract this repository owes a public user

A visitor must be able to get from arriving at this repository to a running Docker product,
real MQTT publish/subscribe, and an understandable Activity result — **without consulting
the internal MQTrail repository**.

If that path cannot be completed from what is published here, that is a defect in this
repository, whatever the implementation does.

## Public instructions may never depend on

- internal source paths;
- private configuration files;
- undocumented image tags;
- internal bootstrap commands;
- hidden REST endpoints;
- unpublished scripts;
- developer-only credentials;
- implementation-specific knowledge.

Each of these turns a public instruction into one that only an insider can follow.

## Repository split

```
MQTrail   internal implementation: backend, frontend, runtime, policy, REST,
          Evidence and Chain, the internal MCP server, implementation tests.

TrailMQ   this repository: everything a public user reads, runs and copies.
```

Implementation defects belong in MQTrail. Documentation, Compose, environment, example,
screenshot and troubleshooting defects belong here — and are not closed by changing an
internal MQTrail guide.

## The release candidate is a pair of revisions

This repository is not the release on its own, and neither is MQTrail:

```
MQTrail SHA   the implementation intended to become 3.1.0
TrailMQ SHA   this repository — must start and explain exactly that implementation
```

The implementation always comes from MQTrail. What this repository owes is that a public
user can actually reach it:

```
this README / Quickstart
→ the environment and Compose infrastructure published here
→ backend and frontend built from or matching the selected MQTrail SHA
→ the running current MQTrail product
```

When something published here does not support the current implementation — a missing
environment variable, a wrong image tag or port, a missing service, an obsolete command,
old navigation in a screenshot, an undocumented credential flow, or no configuration for a
newly shipped capability — that is a **release finding owned here**, not a test obstacle to
be worked around with internal commands.

## First-user and release-readiness testing

Any public-user, accessibility or release-readiness test **starts here**: this README, the
public setup documentation it links to, the published Compose and environment templates,
and the documented Docker startup.

A test that begins from internal MQTrail documentation is invalid:

```
TEST SETUP INVALIDATED
Reason: internal implementation documentation was used instead of the public
distribution contract.
```

Preserve any observations still worth keeping, then restart the journey from this
repository.

## MCP

Whether MCP ships publicly is an explicit release decision, and a capability existing in
MQTrail source does not make it part of this distribution.

**Currently internal for 3.1.0:** read-only, unregistered, not required by any Compose file
here, and not advertised as a public feature. Every public workflow must complete without
it, and it must never be the reason a public path counts as working.

**If it becomes public**, this repository must carry the startup and Compose integration,
environment configuration, authentication and authorization requirements, read-only
guarantees, security limitations, tool documentation, troubleshooting and version
compatibility — before it may be described as available.
