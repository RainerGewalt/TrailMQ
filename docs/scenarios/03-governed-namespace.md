# Scenario 3 — Govern a namespace

**Goal:** open up a deny-by-default namespace (`factory/#`) the governed way:
create a topic that grants specific roles, prove the grant works, inspect the
effective configuration, and verify the audit chain.

**What you learn:** outside `public/#` and `restricted/#`, nothing moves
until an admin explicitly says so — and the governance action and access
decisions remain reviewable.

Requires `curl` and `jq` in addition to the mosquitto clients.

## 1. Prove the namespace is closed

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
USER_PW=$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)

mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$USER_PW" \
  -t 'factory/line-1/temperature' -q 1 -m '{"value":42.0}'
```

```text
Error: A network protocol error occurred when communicating with the broker.
```

Denied — `factory/#` has no grant yet (deny by default).

## 2. Log in to the REST API as admin

```bash
ADMIN_PW=$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)

TOKEN="$(
  curl -sS -X POST "http://localhost/api/v1/auth" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"testadmin\",\"password\":\"${ADMIN_PW}\"}" \
  | jq -r '.token'
)"
```

## 3. Create the governed topic

The topic grants the roles `publisher` and `viewer` access to this path:

```bash
curl -sS -X POST "http://localhost/api/v1/topics" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "factory/line-1/temperature",
    "description": "Line 1 temperature (governed)",
    "qosLevel": 1,
    "isActive": true,
    "queueEnabled": true,
    "queueSize": 1000,
    "auditTrail": true,
    "accessControl": "role",
    "allowedRoles": ["publisher", "viewer"]
  }' | jq '{id, name, accessControl, allowedRoles, qosLevel, auditTrail}'
```

Topic creation reloads the broker ACL immediately — no restart needed.

## 4. Publish again — now it flows

Terminal 1 (dashboard):

```bash
mosquitto_sub -h localhost -p 8883 --cafile "$CA" \
  -u testadmin -P "$ADMIN_PW" \
  -t 'factory/#' -T 'trailmq/#' -v
```

Terminal 2 (sensor — same command that was denied in step 1):

```bash
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$USER_PW" \
  -t 'factory/line-1/temperature' -q 1 -m '{"value":42.0}'
```

Terminal 1 prints:

```text
factory/line-1/temperature {"value":42.0}
```

## 5. Inspect what actually applies

```bash
curl -sS "http://localhost/api/v1/topics/by-name/factory/line-1/temperature/effective" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.effective'
```

```json
{
  "accessControl": "role",
  "allowedRoles": ["publisher", "viewer"],
  "auditTrail": true,
  "qosLevel": 1,
  "queueEnabled": true,
  ...
}
```

This is the *effective* runtime configuration — what the broker actually
enforces on this path, not just what was requested.

## 6. Verify the system/action audit chain

The topic creation and related system/action events are recorded as hash-linked
audit entries. Check that this chain is intact:

```bash
curl -sS "http://localhost/api/v1/audit/validatechain/details" \
  -H "Authorization: Bearer ${TOKEN}" | jq '{valid, checkedEntries, issues}'
```

`"valid": true` means every entry in the system/action audit store still links
to its predecessor with a matching SHA-256 hash — local tampering with those
records would show up here. This is a local integrity check, not an external
anchor or signature. Topic-level message capture is separate; this endpoint
does not claim to validate every MQTT payload.

## 7. See it in the Web UI

Open **http://localhost/trailmq/** as `testadmin` and open **Activity**. Review
the denied attempt (filter **Outcome → Denied**), the topic creation
(**Created**), and the related client sessions. The Preview is a system/action
review surface; do not expect it to act as a payload browser.

## Clean up (optional)

```bash
curl -sS -X DELETE "http://localhost/api/v1/topics/by-name/factory/line-1/temperature" \
  -H "Authorization: Bearer ${TOKEN}"
```

> Note: deleting the topic removes the stored configuration, but the broker
> keeps the in-memory access grant until its next restart
> (`docker restart trailmq-backend`). Topic *creation* takes effect
> immediately; revocation is applied on reload.
