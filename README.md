# 🔌 TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![Go Version](https://img.shields.io/badge/Go-1.23-00ADD8?logo=go)](https://go.dev/)
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react)](https://react.dev/)
[![License](https://img.shields.io/badge/License-Proprietary-blue)](LICENSE)

**Audit-first messaging system for regulated and industrial environments**

TrailMQ is not a classic MQTT dashboard or monitoring tool.  
It is designed to **prove that message-based systems behaved correctly** –  
cryptographically verifiable, policy-driven, and audit-ready by design.

🌐 **Website**: https://trailmq.com  
🐳 **Docker Hub**: Backend | Frontend

---

## What TrailMQ is – and is not

**TrailMQ is:**
- An audit-first control plane for MQTT-based systems
- Built for regulated environments (GxP, MedTech, Industrial AI)
- Focused on evidence, traceability, and enforced behavior
- Designed to explain system behavior under scrutiny

**TrailMQ is not:**
- A payload inspection or message viewer
- A real-time monitoring dashboard
- A generic IoT platform or cloud broker

---

## ✨ Capabilities

| Area | Description |
|-----|-------------|
| 🧾 **Audit & Evidence** | Cryptographic audit chain, system history, exportable proofs |
| 🧠 **Policy Enforcement** | Runtime decisions, topic bindings, handshake validation |
| 🔐 **Access Boundaries** | Identity, network and rate limits – enforced and traceable |
| 📊 **Behavior Insights** | Aggregated message behavior (no payload inspection) |
| 🖥️ **Evidence UI** | Calm, read-only focused interface for auditors and operators |
| 🐳 **Deployment** | Docker-first, deterministic builds |

---

## 🧭 Architecture Overview

TrailMQ separates **message transport** from **decision enforcement** and **audit evidence**.

```
Clients → Transport Layer → Policy Enforcement → Audit & Evidence Chain
                       ↘ Evidence UI / REST API
```

The system does not explain behavior by inspecting messages afterwards.  
It enforces rules at runtime and records cryptographic proof that those rules were applied.

---

## 🚀 Quick Start

### Prerequisites
- Docker 20.10+
- Docker Compose v2+

### Start TrailMQ

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
docker compose up -d
```

### Access Points

| Service | URL |
|-------|-----|
| Web Interface | http://localhost/trailmq/ |
| MQTT Broker | localhost:8883 (TLS) |
| REST API | http://localhost/api |

---

## 🧠 Policy & Decision Model

TrailMQ does not log messages to explain behavior later.  
It **enforces behavior at runtime** and records cryptographic evidence of every decision.

Policies define:
- Who may publish or subscribe
- Which topics are allowed
- Which constraints apply (QoS, sequencing, handshakes)

Bindings define where policies apply.

All decisions are:
- Enforced
- Recorded
- Verifiable
- Immutable

---

## 🔒 Security Model

- TLS and mTLS for transport security
- Identity-based access decisions
- Network boundary enforcement
- Rate limiting with audit evidence

Security is enforced, not inferred.

---

## 🗺️ Roadmap (Evidence-first)

- Audit narrative timeline improvements
- Extended decision trace views
- Evidence export formats for regulated audits
- Regulated AI pipeline integration

Monitoring dashboards and payload inspection are explicitly **out of scope**.

---

## 📄 License

TrailMQ is distributed under a **proprietary freemium license**.

- Free Docker images for evaluation
- Commercial licenses available for enterprise use
- Source code is not open source

---

## 👤 Author

Florian (RainerGewalt)  
Industrial IIoT • Secure Messaging • Regulated Systems
