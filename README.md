# 🔌 TrailMQ

[![Docker Backend](https://img.shields.io/docker/v/rainergewalt/trailmq-backend?label=Backend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-backend)
[![Docker Frontend](https://img.shields.io/docker/v/rainergewalt/trailmq-frontend?label=Frontend&logo=docker&logoColor=white)](https://hub.docker.com/r/rainergewalt/trailmq-frontend)
[![Go Version](https://img.shields.io/badge/Go-1.23-00ADD8?logo=go)](https://go.dev/)
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react)](https://react.dev/)
[![License](https://img.shields.io/badge/License-Proprietary-blue)](LICENSE)

**Secure, auditable MQTT broker with Web UI and REST API**

TrailMQ is a production-ready MQTT broker designed for **industrial and regulated environments**. It combines a secure Go-based broker, a comprehensive REST API, and a modern web interface for monitoring, policy management, and full audit trails.

🌐 **Website**: [trailmq.io](https://trailmq.io) · 🐳 **Docker Hub**: [Backend](https://hub.docker.com/r/rainergewalt/trailmq-backend) | [Frontend](https://hub.docker.com/r/rainergewalt/trailmq-frontend)

---

## ✨ Features

| Category | Features |
|----------|----------|
| 🔐 **Security** | TLS encryption, JWT authentication, rate limiting, RBAC |
| 🌐 **REST API** | Full broker and policy management, OpenAPI documented |
| 🖥️ **Web UI** | Real-time monitoring, user management, topic browser |
| 📨 **Messaging** | Message queuing, dead-letter handling, QoS support |
| 📝 **Compliance** | Full audit trail, GxP-ready, regulated environments |
| 🧩 **Policies** | Runtime validation, handshake system, topic rules |
| 🐳 **Deployment** | Docker-first, minimal dependencies |

---

## 🧭 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         CLIENTS                              │
│              PLCs • Services • Applications                  │
└─────────────────────────┬───────────────────────────────────┘
                          │ MQTT / TLS (8883)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                        BACKEND                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ MQTT Broker │  │  REST API   │  │   Policy Engine     │  │
│  │   (TLS)     │  │  (HTTP/S)   │  │ • Handshakes        │  │
│  └─────────────┘  └─────────────┘  │ • Topic Rules       │  │
│                                    │ • Runtime Validation│  │
│  ┌─────────────┐  ┌─────────────┐  └─────────────────────┘  │
│  │   SQLite    │  │ Audit Trail │                           │
│  │  Database   │  │   Logging   │                           │
│  └─────────────┘  └─────────────┘                           │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP (internal)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                       FRONTEND                               │
│              React + Vite + nginx                            │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  Dashboard  │  │   Users &   │  │   Topic Browser     │  │
│  │  Metrics    │  │   Roles     │  │   & Policies        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisites

- Docker 20.10+
- Docker Compose v2+

### Start TrailMQ

```bash
# Clone repository
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ

# Start all services
docker compose up -d

# Check status
docker compose ps
```

### Access Points

| Service | URL | Description |
|---------|-----|-------------|
| 🖥️ Web UI | http://localhost/trailmq/ | Management interface |
| 🔌 MQTT | `localhost:8883` | TLS-secured broker |
| 🌐 REST API | http://localhost/api | Programmatic access |

### Default Credentials

> ⚠️ **Security Warning**: Change credentials immediately in production!
>
> Default login is provided in the demo configuration. See `docker-compose.yaml` for initial setup.

---

## 🐳 Docker Images

Official images are available on Docker Hub:

```bash
# Pull latest images
docker pull rainergewalt/trailmq-backend:latest
docker pull rainergewalt/trailmq-frontend:latest
```

| Image | Description | Size |
|-------|-------------|------|
| [`rainergewalt/trailmq-backend`](https://hub.docker.com/r/rainergewalt/trailmq-backend) | MQTT Broker + REST API | ~30MB |
| [`rainergewalt/trailmq-frontend`](https://hub.docker.com/r/rainergewalt/trailmq-frontend) | React Web UI + nginx | ~25MB |

---

## ⚙️ Configuration

### Backend (`backend/config.yaml`)

```yaml
# Core settings
mqtt:
  port: 8883
  tls:
    enabled: true
    cert_file: ./certs/server.crt
    key_file: ./certs/server.key

rest:
  port: 8443
  cors_origins: ["http://localhost"]

# Authentication
auth:
  jwt_secret_file: ./secrets/jwtsecret.txt
  token_expiry: 24h

# Audit & Compliance
audit:
  enabled: true
  retention_days: 90
  archive_path: ./audit-archive

# Policy Engine
policies:
  enabled: true
  handshake_timeout: 30s
```

### Frontend (Environment Variables)

```env
VITE_API_BASE_URL=/api
VITE_MQTT_HOST=localhost
VITE_MQTT_PORT=8883
VITE_APP_TITLE=TrailMQ
```

---

## 🧠 Policy & Handshake System

TrailMQ includes a powerful runtime validation system for enterprise environments:

- **Topic-based Rules**: QoS requirements, payload size limits, sequencing
- **Client Handshakes**: Mandatory validation on connect
- **Real-time Enforcement**: Block or warn on policy violations
- **Full Audit Logging**: Every decision is logged

### Example Policy

```yaml
policies:
  - name: "production-sensors"
    topics:
      - "factory/+/sensors/#"
    rules:
      min_qos: 1
      max_payload_size: 1024
      require_handshake: true
```

📖 **Full Documentation**: [backend/POLICY_HANDSHAKE.md](backend/POLICY_HANDSHAKE.md)

---

## 🔒 Security

| Area | Recommendation |
|------|----------------|
| **TLS** | Always enable for production |
| **Certificates** | Rotate regularly (90 days recommended) |
| **Credentials** | Change defaults, use strong passwords |
| **Audit Logs** | Monitor and archive regularly |
| **Network** | Use firewall, limit MQTT port exposure |

### Reporting Vulnerabilities

Please report security issues privately via [GitHub Security Advisories](https://github.com/RainerGewalt/TrailMQ/security/advisories).

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [📘 DOCUMENTATION.md](DOCUMENTATION.md) | Full system overview |
| [⚙️ docs/guides/](docs/guides/) | Setup & deployment guides |
| [🔐 POLICY_HANDSHAKE.md](backend/POLICY_HANDSHAKE.md) | Policy system reference |
| [🌐 docs/API.md](docs/API.md) | REST API reference |

---

## 🗺️ Roadmap

- [ ] Cluster mode / High availability
- [ ] Prometheus metrics endpoint
- [ ] Grafana dashboard templates
- [ ] LDAP/Active Directory integration
- [ ] WebSocket MQTT support
- [ ] Message persistence options

---

## 📄 License

TrailMQ is distributed under a **proprietary freemium license**:

- ✅ **Free**: Docker images available for personal and evaluation use
- ✅ **Free**: Community support via GitHub Issues
- 💼 **Commercial**: Enterprise features and support require a license

The source code is **not open source**. Docker images are provided via Docker Hub.

For commercial licensing inquiries, please contact via GitHub.

---

## 👤 Author

**Florian (RainerGewalt)**

Industrial IIoT • Secure Messaging • Regulated Systems

[![GitHub](https://img.shields.io/badge/GitHub-RainerGewalt-181717?logo=github)](https://github.com/RainerGewalt)

---

<div align="center">

**[⬆ Back to Top](#-trailmq)**

Made with ❤️ for industrial IoT

</div>
