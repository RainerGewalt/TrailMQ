# Secure MQTT Core

`secure-mqtt-core` is the runnable TrailMQ 3.1.0 evaluation recipe. It combines
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
| backend | `rainergewalt/trailmq-backend:3.1.0` | MQTT, REST API, policy enforcement, persistence, audit |
| frontend | `rainergewalt/trailmq-frontend:3.1.0` | Evaluation Preview |
| nginx | `nginx:stable-alpine` | Local reverse proxy |

| Surface | Default address | Override |
| --- | --- | --- |
| Web UI | `http://localhost/trailmq/` | `TRAILMQ_HTTP_PORT` |
| REST API | `http://localhost/api/v1` | `TRAILMQ_HTTP_PORT` |
| MQTT over TLS | `mqtts://localhost:8883` | `TRAILMQ_MQTT_TLS_PORT` |
| MQTT WebSocket | `ws://localhost/mqtt` | `TRAILMQ_HTTP_PORT` |

The backend's REST and WebSocket ports are internal to the Compose network;
nginx exposes the public local routes shown above.

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
TRAILMQ_BACKEND_IMAGE=rainergewalt/trailmq-backend:3.1.0
TRAILMQ_FRONTEND_IMAGE=rainergewalt/trailmq-frontend:3.1.0
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

The Evaluation Preview is optimized for reading and reviewing Overview,
Integrations, Evidence, Admin, users, and roles. It is not the full operations
workspace. Use the API or `config.yaml` for topic creation, policy changes, and
identity lifecycle operations.

For delivery or enforcement proof, prefer:

1. `./trailmq verify`;
2. a real MQTT subscriber;
3. decision details under Evidence or in `ACLMon`/`AuthMon` logs.

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

See the repository [evaluation boundaries](../../README.md#evaluation-boundaries)
and [license](../../LICENSE).

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
