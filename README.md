# 🔌 MQTrail

[![CI](https://github.com/RainerGewalt/MQTrail/actions/workflows/ci.yml/badge.svg)](https://github.com/RainerGewalt/MQTrail/actions/workflows/ci.yml)
[![Docker](https://github.com/RainerGewalt/MQTrail/actions/workflows/docker.yml/badge.svg)](https://github.com/RainerGewalt/MQTrail/actions/workflows/docker.yml)
[![Go Version](https://img.shields.io/badge/Go-1.23-00ADD8?logo=go)](https://go.dev/)
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react)](https://react.dev/)
[![License](https://img.shields.io/badge/License-TBD-yellow)](LICENSE)

**Secure, auditable MQTT broker with Web UI and REST API**

MQTrail is a production-ready MQTT broker designed for **industrial and regulated environments**. It combines a secure Go-based broker, a comprehensive REST API, and a modern web interface for monitoring, policy management, and full audit trails.

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
| 🐳 **Deployment** | Docker-first, single binary, minimal dependencies |

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

### Start MQTrail

```bash
# Clone repository
git clone https://github.com/RainerGewalt/MQTrail.git
cd MQTrail

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

```
Username: testadmin
Password: PubAdmin!2025X
```

> ⚠️ **Security Warning**: Change these credentials immediately in production environments!

---

## 🐳 Docker Images

Official images are available on Docker Hub:

```bash
# Pull latest images
docker pull rainergewalt/trailmq-backend:latest
docker pull rainergewalt/trailmq-frontend:latest

# Pull specific version
docker pull rainergewalt/trailmq-backend:2.1.0
docker pull rainergewalt/trailmq-frontend:2.1.0
```

| Image | Description | Size |
|-------|-------------|------|
| `rainergewalt/trailmq-backend` | MQTT Broker + REST API | ~30MB |
| `rainergewalt/trailmq-frontend` | React Web UI + nginx | ~25MB |

### Alternative: GitHub Container Registry

```bash
docker pull ghcr.io/rainergewalt/mqtrail-backend:latest
docker pull ghcr.io/rainergewalt/mqtrail-frontend:latest
```

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
VITE_APP_TITLE=MQTrail
```

---

## 🧠 Policy & Handshake System

MQTrail includes a powerful runtime validation system for enterprise environments:

### Features

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

## 🛠️ Development

### Backend (Go)

```bash
cd backend

# Install dependencies
go mod download

# Run with hot reload
go run main.go

# Run tests
go test -v ./...

# Build binary
go build -o mqtrail .
```

### Frontend (React + Vite)

```bash
cd frontend

# Install dependencies
npm install

# Development server
npm run dev

# Production build
npm run build

# Lint
npm run lint
```

### Full Stack (Docker Compose)

```bash
# Development mode with hot reload
docker compose -f docker-compose.dev.yaml up

# Production mode
docker compose up -d

# View logs
docker compose logs -f backend
docker compose logs -f frontend

# Rebuild after changes
docker compose up -d --build
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [📘 DOCUMENTATION.md](DOCUMENTATION.md) | Full system overview |
| [⚙️ docs/guides/](docs/guides/) | Setup & development guides |
| [🔐 POLICY_HANDSHAKE.md](backend/POLICY_HANDSHAKE.md) | Policy system reference |
| [🌐 docs/API.md](docs/API.md) | REST API reference |
| [🚀 DEPLOYMENT.md](DEPLOYMENT.md) | CI/CD & deployment |

---

## 🔒 Security

### Recommendations

| Area | Recommendation |
|------|----------------|
| **TLS** | Always enable for production |
| **Certificates** | Rotate regularly (90 days recommended) |
| **Credentials** | Change defaults, use strong passwords |
| **Audit Logs** | Monitor and archive regularly |
| **Network** | Use firewall, limit MQTT port exposure |

### Reporting Vulnerabilities

Please report security issues privately via GitHub Security Advisories or email.

---

## 🗺️ Roadmap

- [ ] Cluster mode / High availability
- [ ] Prometheus metrics endpoint
- [ ] Grafana dashboard templates
- [ ] LDAP/Active Directory integration
- [ ] WebSocket MQTT support
- [ ] Message persistence options

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/MQTrail.git

# Create feature branch
git checkout -b feature/amazing-feature

# Make changes and test
go test ./...
npm run lint

# Commit and push
git commit -m "feat: add amazing feature"
git push origin feature/amazing-feature

# Open Pull Request
```

---

## 📄 License

TBD - License information coming soon.

---

## 👤 Author

**Florian (RainerGewalt)**

Industrial IIoT • Secure Messaging • Regulated Systems

[![GitHub](https://img.shields.io/badge/GitHub-RainerGewalt-181717?logo=github)](https://github.com/RainerGewalt)

---

<div align="center">

**[⬆ Back to Top](#-mqtrail)**

Made with ❤️ for industrial IoT

</div>