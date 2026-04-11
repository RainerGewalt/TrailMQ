# TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![Deployment](https://img.shields.io/badge/Deployment-Docker%20Compose-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![License](https://img.shields.io/badge/License-Proprietary-blue)](LICENSE)

**Make MQTT reviewable**

TrailMQ helps regulated and industrial teams control message flow, enforce runtime policies, and keep reviewable audit evidence on top of MQTT-based systems.

It is not just a broker with logging added afterwards.  
It is a control and evidence layer for message-driven systems that need traceability, explainability, and operational resilience under load.

TrailMQ is delivered as official Docker images.  
This repository contains the Docker Compose setup used to run the platform.  
The application source code is private and is not included here.

🌐 **Website**: https://trailmq.com  
🐳 **Docker Hub**: [Backend](https://hub.docker.com/r/rainergewalt/trailmq-backend) | [Frontend](https://hub.docker.com/r/rainergewalt/trailmq-frontend)

---

## Why TrailMQ

Standard brokers move messages.  
TrailMQ helps you prove what happened and keep control when systems are under stress.

Teams often need answers later:

- Who published or changed something
- Which policy was active at that moment
- Why something was allowed, queued, delayed, or blocked
- Whether critical message handling remained within contract
- How behavior can still be reviewed months later

TrailMQ is built for exactly that.

---

## What TrailMQ is

- A control and evidence layer for MQTT-based systems
- Built for regulated and industrial environments
- Focused on traceability, policy enforcement, and reviewable evidence
- Designed to keep message handling understandable under load
- Built to support controlled degradation instead of silent failure

## What TrailMQ is not

- Not just a plain MQTT broker
- Not a payload inspection platform
- Not a generic IoT dashboard
- Not only a log viewer
- Not a broker replacement in the narrow sense

---

## Core Capabilities

| Area | Description |
|------|-------------|
| Policy Enforcement | Runtime decisions for publish, subscribe, connect, and system behavior |
| Audit and Evidence | Reviewable audit trail, chain validation, exportable evidence, system history |
| Intelligent Queues | Controlled queuing, backpressure, DLQ handling, and priority-aware behavior under load |
| Access Control | Identity, topic permissions, network boundaries, and rate limiting with traceable enforcement |
| Explainability | Evidence for why behavior happened, not just that it happened |
| Evidence UI | Read-only interface for operators, reviewers, and auditors |
| Deployment | Official Docker images with Compose-based deployment |

---

## Intelligent Queue Handling

TrailMQ is designed to do more than accept or reject traffic.

Under load, systems often need controlled behavior:

- what may wait
- what should be processed first
- what must never disappear silently
- what must be rejected explicitly
- what must go to a dead letter path
- when the system should signal that an evidence contract is at risk

TrailMQ adds structured queueing and evidence-aware handling so that overload does not become operational ambiguity.

This helps teams move from uncontrolled failure toward controlled, reviewable degradation.

---

## Architecture Overview

TrailMQ separates transport, enforcement, queue behavior, and evidence handling.

```text
Clients
  → Transport Layer
  → Policy Enforcement
  → Queue and Flow Control
  → Audit and Evidence Chain
                    ↘ Evidence UI / REST API
````

It does not try to reconstruct behavior afterwards from scattered logs alone.
It applies rules at runtime and records reviewable evidence for what the system decided and why.

---

## Quick Start

This repository provides the Docker Compose setup for running TrailMQ with the official published images.

### Prerequisites

* Docker 20.10+
* Docker Compose v2+

### Start TrailMQ

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
docker compose up -d
```

### Access Points

| Service       | URL                                                    |
| ------------- | ------------------------------------------------------ |
| Web Interface | [http://localhost/trailmq/](http://localhost/trailmq/) |
| MQTT Broker   | localhost:8883                                         |
| REST API      | [http://localhost/api](http://localhost/api)           |

---

## Policy and Decision Model

TrailMQ does not rely on plain logs to explain behavior later.

It enforces behavior at runtime and records evidence for decisions around:

* identity
* topic access
* policy application
* queue behavior
* blocked or delayed processing
* system reactions under load

Policies define:

* who may publish or subscribe
* which topics are allowed
* which constraints apply
* how message handling should behave in specific situations

Bindings define where policies apply.

Decisions are intended to be:

* enforced
* recorded
* reviewable
* verifiable
* consistent over time

---

## Security Model

TrailMQ supports a security model built around enforcement and evidence:

* TLS and mTLS for transport security
* identity-based access decisions
* network boundary enforcement
* rate limiting with traceable behavior
* reviewable control decisions instead of implicit trust

Security is enforced, not inferred afterwards.

---

## Typical Use Cases

TrailMQ is suited for teams that need more than message transport, for example:

* regulated manufacturing environments
* pharma and life sciences integrations
* controlled MQTT message flows in industrial systems
* evidence-oriented operation reviews
* systems that must remain understandable under load and failure conditions

---

## Distribution Model

TrailMQ is distributed through official Docker images.

This public repository contains:

* Docker Compose setup
* deployment assets
* configuration and runtime wiring for published images

This public repository does not contain:

* the TrailMQ application source code
* the private build pipeline
* internal implementation details of the product

Official backend and frontend images are built from the maintained product branch and published via Docker Hub.

---

## License

TrailMQ is distributed under a proprietary license.

* Official Docker images are provided for evaluation and deployment
* Commercial usage may require a separate agreement
* The application source code is private
* This repository contains deployment assets only

See the LICENSE file for details.

---

## Author

Florian Przybylak
Industrial IIoT • Secure Messaging • Regulated Systems

`
