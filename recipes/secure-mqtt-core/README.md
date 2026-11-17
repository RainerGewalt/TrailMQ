# Secure MQTT Core

`secure-mqtt-core` is the runnable TrailMQ 3.1.2 evaluation recipe. It combines
standard MQTT transport, two-stage authorization, queue/policy controls, a
review-oriented UI, and a hash-linked system/action audit record.

Use it to answer four practical questions:

1. Can existing MQTT clients connect without a TrailMQ-specific SDK?
2. Are unauthorized actions blocked at the broker boundary?
3. Can an operator inspect the effective rule and recorded outcome?
4. Does the system/action evidence chain reveal later changes?

## Start from the repository root

```bash
./trailmq quickstart
./trailmq verify
```

The launcher creates local certificates and evaluation credentials, starts the
stack, and prints its access points. `verify` then runs the canonical
allow/deny/evidence proof.

## Stack and endpoints

| Service | Default image | Responsibility |
| --- | --- | --- |
| backend | `rainergewalt/trailmq-backend:3.1.2` | MQTT, REST API, policy enforcement, persistence, audit |
| frontend | `rainergewalt/trailmq-frontend:3.1.2` | Evaluation Preview |
| nginx | `nginxinc/nginx-unprivileged:1.30-alpine` (digest-pinned) | Local reverse proxy |

All three containers run as a non-root user with every Linux capability dropped,
`no-new-privileges` set and a read-only root filesystem. The only writable paths
are `/tmp` and, for the backend, the bind mounts listed under
[Configuration and state](#configuration-and-state).

| Surface | Default address | Override |
| --- | --- | --- |
| Web UI | `http://localhost/trailmq/` | `TRAILMQ_HTTP_PORT` |
| REST API | `http://localhost/api/v1` | `TRAILMQ_HTTP_PORT` |
| MQTT over TLS | `mqtts://localhost:8883` | `TRAILMQ_MQTT_TLS_PORT` |
| MQTT WebSocket | `ws://localhost/mqtt` | `TRAILMQ_HTTP_PORT` |

The backend's REST and WebSocket ports are internal to the Compose network;
nginx exposes the public local routes shown above.

### Client address behind the proxy

Sign-in limits, the IP allow-list and audit records use the client's address.
Behind nginx the backend sees only nginx, so nginx states the client's address
in `X-Forwarded-For`, and the backend believes that header only from a proxy
it was told to trust (`security.trusted_proxies` in `config.yaml`).

- `trailmq-net` has a fixed subnet (`172.30.200.0/24`) and nginx a fixed address
  (`172.30.200.10`) in `docker-compose.yaml`.
- nginx overwrites `X-Forwarded-For` and `X-Real-IP` with the address it
  accepted the connection from, and drops `Forwarded`, `X-Forwarded-Host` and
  `X-Forwarded-Port`, so whatever a client sends in those headers never reaches
  the backend.
- Trust exactly the nginx address, never the subnet. Docker routes published
  ports through the network's gateway, which with this `ip_range` is
  `172.30.200.128` (`docker network inspect` shows it). A trusted subnet
  includes that gateway, and then any client can choose its own address.

If the subnet collides with another Docker network, change the subnet,
nginx's `ipv4_address` and `security.trusted_proxies` together.

## Configuration and state

| Path | What it controls |
| --- | --- |
| root `.env` | host ports and Docker image overrides |
| `config.yaml` | TLS, roles, configured users, origins, queue, and audit settings |
| `certs/` | local CA and server certificate |
| `secrets/` | JWT secret and evaluation password files |
| `data/` | persisted runtime state |
| `logs/` | backend logs |
| `audit-archive/` | archived audit material |

Generated directories are gitignored. The launcher mounts `config.yaml`,
certificates, and secrets read-only into the backend container.

To change ports or pin images:

```bash
cp .env.example .env
```

```env
TRAILMQ_HTTP_PORT=8080
TRAILMQ_MQTT_TLS_PORT=8884
TRAILMQ_BACKEND_IMAGE=rainergewalt/trailmq-backend:3.1.2
TRAILMQ_FRONTEND_IMAGE=rainergewalt/trailmq-frontend:3.1.2
```

Restart with `./trailmq down` followed by `./trailmq start`.

## Evaluation identities

| User | Role | Intended use |
| --- | --- | --- |
| `testadmin` | `admin` | Preview login, REST control, subscriber |
| `testuser` | `publisher` | MQTT publisher |

```bash
./trailmq credentials
```

The launcher generates the password files once and leaves them in `secrets/`.
They are for local evaluation only.

### Important merge behavior

The recipe uses `authsyncmode: "merge"`. Configured users are merged into the
runtime database at backend startup. Removing a user from `config.yaml` or
deleting a password file does **not** revoke an identity already persisted in
that database.

Use [Access management](../../docs/access-management.md) to add, rotate, or
safely delete an evaluation user.

## REST API authentication

Most control and review endpoints require an admin token. From the repository
root:

```bash
ADMIN_PW=$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)

TOKEN=$(
  curl -sS -X POST http://localhost/api/v1/auth \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"testadmin\",\"password\":\"${ADMIN_PW}\"}" \
  | jq -r '.token'
)

curl -sS http://localhost/api/v1/auth/me \
  -H "Authorization: Bearer ${TOKEN}" | jq
```

If `TOKEN` is empty or `null`, check `./trailmq credentials`, then run
`./trailmq doctor` and `./trailmq logs backend`.

## Documented evaluation API

The table below intentionally focuses on endpoints exercised by the public
launcher and guided scenarios. It is a task-oriented evaluation surface, not a
claim that every internal or future read model is present in every image.

### Runtime checks

| Method | Endpoint | Use |
| --- | --- | --- |
| `GET` | `/health` | HTTP service is reachable |
| `GET` | `/live` | process is alive |
| `GET` | `/ready` | backend is ready for work |
| `GET` | `/api/v1/version` | running build/version identity |
| `GET` | `/api/v1/metrics` | evaluation metrics |
| `GET` | `/metrics` | Prometheus-style metrics |

```bash
curl -sS http://localhost/ready | jq
curl -sS http://localhost/api/v1/version | jq
```

### Topic governance

| Method | Endpoint | Use |
| --- | --- | --- |
| `GET` | `/api/v1/topics` | list governed topics |
| `POST` | `/api/v1/topics` | create a governed topic |
| `GET` | `/api/v1/topics/tree` | inspect the topic hierarchy |
| `GET` | `/api/v1/topics/by-name/{path}` | read a topic by MQTT path |
| `GET` | `/api/v1/topics/by-name/{path}/effective` | inspect effective settings |
| `DELETE` | `/api/v1/topics/by-name/{path}` | delete stored topic configuration |

Create a deny-by-default namespace grant:

```bash
curl -sS -X POST http://localhost/api/v1/topics \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "factory/line-1/temperature",
    "qosLevel": 1,
    "isActive": true,
    "queueEnabled": true,
    "queueSize": 1000,
    "auditTrail": true,
    "accessControl": "role",
    "allowedRoles": ["publisher", "viewer"]
  }' | jq
```

Then inspect what the backend applies:

```bash
curl -sS \
  http://localhost/api/v1/topics/by-name/factory/line-1/temperature/effective \
  -H "Authorization: Bearer ${TOKEN}" | jq '.effective'
```

Topic creation and deletion both update the broker ACL immediately. An access grant
removed through `DELETE /api/v1/topics/...` is revoked on the next MQTT action, with no
restart: a publish that succeeded while the rule was in place is refused straight after
its deletion. Scenario 3 walks through it, and you can watch it happen on your own
stack rather than take this on trust.

### Message policies

| Method | Endpoint | Use |
| --- | --- | --- |
| `GET` / `POST` | `/api/v1/policies` | list or create policies |
| `DELETE` | `/api/v1/policies/{id}` | remove a policy |
| `GET` | `/api/v1/policies/violations` | review policy violations |
| `POST` | `/api/v1/policies/resolve` | resolve the policy for a topic |
| `GET` / `POST` | `/api/v1/policies/bindings` | list or create topic bindings |

[Scenario 7](../../docs/scenarios/07-message-policy-qos.md) creates a minimum
QoS policy, binds it to a topic, and proves why client-side success is not the
same as delivery.

### Queue and dead-letter review

For topic path parameters, URL-encode `/` as `%2F`.

| Method | Endpoint | Use |
| --- | --- | --- |
| `GET` | `/api/v1/queue/status` | global queue status |
| `GET` | `/api/v1/queue/deadletter` | dead-lettered messages |
| `GET` | `/api/v1/queues/{topic}/stats` | per-topic counters |
| `POST` | `/api/v1/queues/{topic}/enqueue` | enqueue an evaluation message |
| `POST` | `/api/v1/queues/{topic}/dispatch` | dispatch to a consumer group |
| `POST` | `/api/v1/queues/{topic}/ack` | acknowledge processing |
| `POST` | `/api/v1/queues/{topic}/nack` | reject/retry or dead-letter |

[Scenario 6](../../docs/scenarios/06-queue-and-dead-letters.md) exercises the
entire enqueue, dispatch, ACK, NACK, and dead-letter path.

### System/action audit and decisions

| Method | Endpoint | Use |
| --- | --- | --- |
| `GET` | `/api/v1/audit` | list exposed system/action audit entries |
| `GET` | `/api/v1/audit/auth` | authentication audit events (REST sign-ins) |
| `GET` | `/api/v1/audit/messages` | **MQTT decisions** — allowed operations and refusals |
| `GET` | `/api/v1/audit/validatechain` | validate the system/action chain |
| `GET` | `/api/v1/audit/validatechain/details` | the same verdict with its scope |

### Where MQTT decisions live

`/api/v1/audit` carries system and administrative actions. It does **not** carry publish and
subscribe decisions — those are a separate store, and `/api/v1/audit/messages` is how you
read them:

```bash
curl -sS "http://localhost/api/v1/audit/messages?limit=20&refusals=true" \
  -H "Authorization: Bearer $TOKEN" | jq '.items[] | {action, clientId, user, deniedAction, deniedTopic, reason}'
```

A refusal carries both identities and a canonical machine-readable reason:

```json
{
  "action": "mqtt.publish.denied",
  "clientId": "plantops-lf12-probe9182",
  "user": "testuser",
  "deniedAction": "publish",
  "deniedTopic": "restricted/ops/config",
  "reason": "acl_role_not_in_topic_scope"
}
```

The reason distinguishes the two causes an integration needs to tell apart:

| `reason` | Meaning |
| --- | --- |
| `acl_role_not_in_topic_scope` | no rule brings this topic into scope for any role the identity holds |
| `acl_role_action_not_permitted` | a rule covers the topic for the identity's role, and that role may not perform this operation |
| `acl_insufficient_permissions` | the identity holds no role this build recognises |
| `acl_unauthenticated` | the connection was not authenticated |
| `acl_anonymous_restricted_topic` | anonymous connections may only use the public namespace |
| `acl_policy_denied` | the topic policy refused the operation |

This store is deliberately **not** covered by the chain verdict above — see
`chain.excluded` in its response.

```bash
curl -sS http://localhost/api/v1/audit/validatechain/details \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq '{valid, checkedEntries, chain}'
```

This chain check has a deliberate, documented scope: it validates the
system/action audit store. Topic-level message capture is separate, so do not
interpret `valid: true` as proof that every MQTT payload is exposed or checked
by this endpoint. See [Architecture](../../docs/architecture.md#what-the-evidence-chain-proves).

### Runtime user lifecycle

| Method | Endpoint | Use |
| --- | --- | --- |
| `GET` | `/api/v1/users` | list persisted users and IDs |
| `DELETE` | `/api/v1/users/{id}` | revoke/delete a persisted evaluation user |

Always remove a config-managed declaration before deleting the persisted user,
or merge sync may recreate it on restart. Follow the complete
[offboarding procedure](../../docs/access-management.md#revoke-an-evaluation-user).

## UI and API responsibilities

The Evaluation Preview has four surfaces — Overview, Access, Clients and
Activity. **Access** covers evaluation users and topic rules; everything else is
read and review. It is not the full operations workspace, so use the API or
`config.yaml` for the remaining policy and lifecycle operations.

For delivery or enforcement proof, prefer:

1. `./trailmq verify`;
2. a real MQTT subscriber;
3. decision details under Activity or in `ACLMon`/`AuthMon` logs.

Do not treat a Preview counter alone as proof that a publish was delivered.

## Evaluation boundaries

- The recipe is licensed for local, non-production evaluation only.
- Generated CA material and credentials are local demo assets.
- Browser-origin examples are intentionally convenient for local development
  and must be restricted for a real deployment.
- Hash linking provides local tamper evidence, not external notarization or
  physically immutable storage.
- TrailMQ can support traceability and regulated engineering work, but does not
  certify the complete deployed system as CRA-, GMP/GxP-, Annex 11-, or 21 CFR
  Part 11-compliant.

See the repository [evaluation boundaries](../../README.md#trust-and-evidence-scope)
and [license](../../LICENSE).

## Upgrading an existing 3.1.1 recipe to 3.1.2

3.1.2 is a security patch. Before you start it on data from 3.1.1:

- **Everyone signs in again once.** Sessions issued by 3.1.1 end with the upgrade.
- **Rules that 3.1.1 switched off stay off until you save them again.** Check rules under `public/` first:
  while such a rule is off, the built-in `public/#` rule decides for that area.
- **Devices must be allowed to publish to the topic of their Last Will.** A device whose Will topic its role
  may not publish to is refused at every connection after the upgrade, with an answer that looks like a wrong
  password (MQTT 3.1.1 return code 5, MQTT 5 `0x87`).
- **Accounts need the role for what they change.** Changing topic rules needs `policy_admin`, operating queues
  `operator` or `queue_admin` (purging a queue or changing its configuration `queue_admin`), and an Edge Sync
  node's account `replication_admin` with a token issued after that grant.
- **Repeated failed MQTT connections are bounded.** After 20 refused attempts for one account from one address
  within 15 minutes, that account is refused from that address until the window ends. New WebSocket connections
  through this recipe's proxy are limited per client address; beyond the limit the proxy answers `429`. Behind
  Docker Desktop or rootless Docker, published ports often reach the proxy from one internal address, so that
  `/mqtt` limit is then a single shared bucket for every browser on the host rather than per client.
- **Rolling back to 3.1.1** needs the 3.1.1 recipe files: 3.1.1 does not know `security.trusted_proxies` and
  refuses to start with it in `config.yaml`.

The release notes of 3.1.2 list every change.

## Operate the local recipe

```bash
./trailmq status
./trailmq logs
./trailmq down
./trailmq start
./trailmq reset
```

Run `./trailmq help` for the complete command list and
`./trailmq doctor` when the stack does not behave as expected.

You can run Compose directly:

```bash
cd recipes/secure-mqtt-core
docker compose up -d
```

The root launcher is preferred because it loads root `.env`, creates required
folders and local secrets, checks certificates, and tracks the active recipe.
