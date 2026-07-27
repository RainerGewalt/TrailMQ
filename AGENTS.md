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

The TrailMQ MCP server is an **internal diagnostic tool**: read-only, unregistered, and not
advertised as a public product feature. It must never be presented here as something a
public user installs or depends on, and it must never be the reason a public path is
considered working.
