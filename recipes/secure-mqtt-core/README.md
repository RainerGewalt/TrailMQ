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

If the subnet collides with another Docker network, change the subnet, its
`ip_range`, nginx's `ipv4_address` and `security.trusted_proxies` together.
Docker assigns addresses to the other containers only from `ip_range`
(`172.30.200.128/25`), so none of them can take nginx's address.

nginx limits MQTT-over-WebSocket connection attempts on `/mqtt` per client
address (30 per minute, burst 20, then 429). Behind Docker Desktop or rootless
Docker port publishing, every client reaches nginx from the same gateway
address, so all of them share that one limit. A busy test rig or many browser
tabs on such a host can reach it together; on Linux with the default rootful
Docker, clients keep their own addresses.

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

The root `.env` also carries one backend setting, which only 3.2 images read:

| Variable | Values | Effect |
| --- | --- | --- |
| `MQTT_CLIENT_ID_UNDECLARED` | unset (default), `refuse`, `first_holder` | Decides a client ID no binding covers. Unset, `config.yaml` decides, and without a value there the 3.2 default `refuse` applies. A value set here overrides `config.yaml`. `first_holder` is a compatibility mode only; see [Upgrading to 3.2: client IDs](#upgrading-to-32-client-ids). |

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
| `GET` | `/api/v1/metrics/prometheus` | Prometheus metrics for a scraper; needs no sign-in (see [Evaluation boundaries](#evaluation-boundaries)) |

The backend also serves `/metrics` at its own root, but the recipe's nginx does
not forward that path.

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
- `/api/v1/metrics/prometheus` answers without sign-in, because it is meant for
  a metrics scraper. It describes the running system: memory, database and
  audit pipeline state, and from 3.2 counts from the MQTT decision trace. The
  recipe's nginx forwards every path under `/api/`, so the endpoint is
  reachable on the published HTTP port (`TRAILMQ_HTTP_PORT`), which Docker
  publishes on every host interface by default. Do not expose that port to
  untrusted networks. If you need to, block the path in `nginx.conf` and let
  the scraper reach the backend on `trailmq-net`. The 3.2 Web UI does not read
  this endpoint.
- Hash linking provides local tamper evidence, not external notarization or
  physically immutable storage.
- The broker admits at most **500 concurrent MQTT sessions**, across the TLS
  and WebSocket listeners together. The limit is fixed in the backend and
  cannot be configured. The 501st CONNECT is refused with reason
  `session_limit_reached`, and the client is told that its credentials are bad.
  A plant with hundreds of PLCs can reach it; see
  [Troubleshooting](../../docs/troubleshooting.md#connections-are-refused-once-500-clients-are-connected).
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

## Upgrading to 3.2: client IDs

3.2 has not been published yet. This section prepares the upgrade, and the
changes it describes take effect only once 3.2 images run.

From 3.2, the backend **refuses MQTT client IDs that are not bound to an
account**. This setting is `mqtt_client_id_undeclared: refuse`, and it applies
whenever neither `config.yaml` nor `MQTT_CLIENT_ID_UNDECLARED` sets a value. A
connection is admitted only with a client ID bound to its account, or with an
empty client ID, for which the server assigns one. A refused device sees an
answer that looks like a wrong password (MQTT 3.1.1 return code 5, MQTT 5
`0x87`), and the refusal is recorded with the reason `client_id_undeclared`.
3.1.2 has no client-ID bindings, so every device that sets its own client ID
is affected until that ID is bound.

The 3.2 Web UI connects with a server-assigned client ID and is not affected.
Backend and frontend ship as one release: switch both images together.

### 1. Run the preflight before you switch images

The preflight ships in the 3.2 backend image. Run it from that image against
your existing `config.yaml` and `data/`, while your 3.1.2 stack keeps running
or after `./trailmq down`. Replace `<version>` with the published 3.2 release:

```bash
cd recipes/secure-mqtt-core
TRAILMQ_BACKEND_IMAGE=rainergewalt/trailmq-backend:<version> \
  docker compose run --rm --no-deps -T backend \
    preflight client-ids --config /app/config.yaml
```

Add `--json` after `/app/config.yaml` for machine-readable output. The command
starts a one-off backend container that runs only the check. It opens the
database read-only, writes no file, and never starts the broker.
`docker compose run` exits with the preflight's own exit status:

| Exit | Result line | Meaning |
| --- | --- | --- |
| `0` | `NO IMPACT` | No counted client ID observed within audit retention would be refused. |
| `1` | `IMPACT` | At least one observed client ID would be refused. |
| `2` | `INCOMPLETE`, or an error | A source could not be read, or the check could not run. Never read this as no impact. |

How to read the report:

- **It sees only what the audit records hold.** This recipe keeps them for
  `audit_retention_days: 90`, and connection records are written on a
  best-effort basis. A device that has not connected within that window, or
  whose connection record is missing, is not in the report. A clean result
  means that nothing was observed, not that nothing will be refused.
- **Affected principals** lists, for each user or device, the client IDs that
  would be refused and what to do about them.
- **`mqttjs_` IDs** are listed but not counted. Most are sessions of the 3.1.2
  Web UI, which 3.2 no longer creates: do not bind them. An mqtt.js device that
  sets no client ID gets the same form of ID, so check each one.
- **Exit `2` with a database that was not shut down cleanly.** If the last
  backend stopped without a clean shutdown, the preflight refuses to open the
  database. Start the stack once, stop it with `./trailmq down`, and run the
  preflight again.

### 2. Bind the client IDs it lists

Bindings exist only from 3.2, so you create them after the switch:

1. **If any field device connects with a fixed client ID, start 3.2 in
   compatibility mode for the transition, whatever the preflight reported.**
   Exit `0` means only that nothing was observed within the 90-day retention.
   A device that stayed connected throughout, as PLCs often do for months,
   left no connection record in that window and is not in the report. Set
   `MQTT_CLIENT_ID_UNDECLARED=first_holder` in the root `.env`, or uncomment
   `mqtt_client_id_undeclared` in `config.yaml` and write `"first_holder"`.
   The backend's startup log names the effective mode and where it came from.
   After the restart, use the **Clients** page and
   `GET /api/v1/clients/binding-proposals` as the inventory of what connects.
   Switch straight to `refuse` only when no client uses a fixed ID, for example
   an evaluation that only uses the Web UI and this recipe's own commands.
2. Switch to the 3.2 images and start the stack.
3. Bind each listed client ID to its account as an administrator, either on
   the **Clients** page of the Web UI or through the API:

   ```bash
   curl -sS -X POST http://localhost/api/v1/clients/bindings \
     -H "Authorization: Bearer ${TOKEN}" \
     -H 'Content-Type: application/json' \
     -d '{"pattern": "line-1-sensor", "match": "exact", "username": "testuser"}' | jq
   ```

   `match` is `exact` or `prefix`. Creating a binding disconnects any other
   user's session that holds a matching client ID.
   `GET /api/v1/clients/binding-proposals` lists candidates from observed
   connections. A proposal never becomes a binding on its own.
4. A client that cannot be bound must connect with an empty client ID. This
   applies to configuration-file users without an account and to anonymous
   clients. The recipe's own users are merged into the runtime database, so
   they are accounts and can be bound.
5. Check again on the running 3.2 backend until the preflight exits `0`:

   ```bash
   docker compose exec -T backend \
     /app/mqtrail preflight client-ids --config /app/config.yaml
   ```

6. Remove `first_holder` and restart with `./trailmq down` and then
   `./trailmq start`. `refuse` then applies.

### When `first_holder` is acceptable

`first_holder` is a compatibility mode, not an alternative default. It admits
an undeclared client ID for whichever user holds it first. Another user can
then take a device's ID first and lock the device out until an administrator
binds the ID. Use it only for a bounded transition, while devices that cannot
yet be bound or moved to server-assigned IDs are migrated. Then remove it.

### Rolling back to 3.1.2

Back up `data/` before you switch. To return to 3.1.2, use the 3.1.2 images and
remove `mqtt_client_id_undeclared` from `config.yaml`: 3.1.2 does not know the
key and refuses to start with it. 3.1.2 does not read
`MQTT_CLIENT_ID_UNDECLARED`. If 3.1.2 does not start on the database that 3.2
used, restore the backup. Anything recorded since the switch is then lost.

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
