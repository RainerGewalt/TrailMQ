
# TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![Go Version](https://img.shields.io/badge/Go-1.23-00ADD8?logo=go)](https://go.dev/)
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react)](https://react.dev/)
[![License](https://img.shields.io/badge/License-Proprietary-blue)](LICENSE)

**Make MQTT reviewable**

TrailMQ helps regulated teams control access, enforce policies and keep reviewable audit evidence on top of MQTT systems.

It is not just a broker with logging added on top.  
It is a control and evidence layer for message based systems in regulated environments.

🌐 **Website**: https://trailmq.com  
🐳 **Docker Hub**: [Backend](https://hub.docker.com/r/rainergewalt/trailmq-backend) | [Frontend](https://hub.docker.com/r/rainergewalt/trailmq-frontend)

---

## Why TrailMQ

Standard brokers move messages.  
TrailMQ helps you prove what happened.

Teams often need to answer questions later:

- Who changed what
- Which policy was active
- Why was something allowed or blocked
- How can this be reviewed months later

TrailMQ is built for exactly that.

---

## What TrailMQ is

- A control and evidence layer for MQTT based systems
- Built for regulated and industrial environments
- Focused on traceability, policy enforcement and reviewable evidence
- Designed for teams that need answers later

## What TrailMQ is not

- A payload inspection tool
- A real time monitoring dashboard
- A generic IoT platform
- A message viewer

---

## Capabilities

| Area | Description |
|-----|-------------|
| Audit and Evidence | Cryptographic audit chain, system history, exportable evidence |
| Policy Enforcement | Runtime decisions, topic bindings, handshake validation |
| Access Control | Identity, network and rate limits with traceable enforcement |
| Behavior Insights | Aggregated system behavior without payload inspection |
| Evidence UI | Read only interface for operators, reviewers and auditors |
| Deployment | Docker first setup with deterministic builds |

---

## Architecture Overview

TrailMQ separates message transport from policy enforcement and audit evidence.

```text
Clients → Transport Layer → Policy Enforcement → Audit and Evidence Chain
                       ↘ Evidence UI / REST API
````

It does not try to explain behavior afterwards by parsing logs.
It enforces rules at runtime and records evidence that those rules were applied.

---

## Quick Start

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
It enforces behavior at runtime and records evidence for every decision.

Policies define:

* Who may publish or subscribe
* Which topics are allowed
* Which constraints apply

Bindings define where policies apply.

Decisions are:

* Enforced
* Recorded
* Verifiable
* Immutable

---

## Security Model

* TLS and mTLS for transport security
* Identity based access decisions
* Network boundary enforcement
* Rate limiting with audit evidence

Security is enforced, not inferred.

---

## License

TrailMQ is distributed under a proprietary freemium license.

* Free Docker images for evaluation
* Commercial licenses available for enterprise use
* Source code is not open source

---

## Author

Florian Przybylak
Industrial IIoT • Secure Messaging • Regulated Systems

```

