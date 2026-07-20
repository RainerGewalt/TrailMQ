# Scenario 7 — When "success" isn't delivery

**Goal:** send a message that your client reports as **successfully
published** — and that never reaches the subscriber, because a message policy
constrained it. Then read the exact recorded reason.

**What you learn:** the most dangerous failure mode in MQTT isn't an error.
It's a client that thinks everything is fine. TrailMQ makes that case visible
instead of silent.

Requires `curl` and `jq`. Log in first (as in
[scenario 3](03-governed-namespace.md)) so `TOKEN` is set.

## The problem this addresses

MQTT has three quality-of-service levels. At QoS 0 there is no
acknowledgement at all — the client hands the message to the socket and
reports success. If the broker drops it, the sender never finds out.

For a temperature reading that may be acceptable. For a batch record, a
setpoint or an audit-relevant event it is not. So: require a minimum QoS on
that path, and make violations reviewable.

## 1. Define the policy

`qosRequired: 1` means "anything below QoS 1 on this path is a violation",
and `onViolation: "block"` means the message must not be delivered:

```bash
curl -sS -X POST "http://localhost/api/v1/policies" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "evaluator-qos1",
    "description": "Minimum QoS 1 on the evaluator path",
    "qosRequired": 1,
    "maxPayloadKb": 4,
    "auditLevel": "detailed",
    "onViolation": "block",
    "enabled": true
  }' | jq '{id, qosRequired, onViolation}'
```

> Use `"block"`. The value `"deny"` is accepted by the API but is **not**
> currently enforced as a blocking action in this build — it records without
> blocking.

## 2. Bind it to a topic pattern

Policies are separate from topics, so one policy can govern many paths:

```bash
curl -sS -X POST "http://localhost/api/v1/policies/bindings" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "public/demo/temperature",
    "policyId": "evaluator-qos1",
    "priority": 100,
    "enabled": true
  }' | jq '{pattern, policyId, priority, enabled}'
```

Check what now applies to that path:

```bash
curl -sS -X POST "http://localhost/api/v1/policies/resolve" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"topic":"public/demo/temperature"}' | jq '.policy | {id, qosRequired, onViolation}'
```

## 3. QoS 1 — satisfies the policy, arrives

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
APW=$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)
UPW=$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)

# Terminal 1
mosquitto_sub -h localhost -p 8883 --cafile "$CA" \
  -u testadmin -P "$APW" -t 'public/demo/temperature' -T 'trailmq/#' -v

# Terminal 2
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$UPW" -i qos-test \
  -t 'public/demo/temperature' -q 1 -m '{"qos":1}'
```

Terminal 1:

```text
public/demo/temperature {"qos":1}
```

## 4. QoS 0 — reports success, never arrives

Same topic, same credentials, same client. Only `-q 0` instead of `-q 1`:

```bash
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$UPW" -i qos-test \
  -t 'public/demo/temperature' -q 0 -m '{"qos":0}'
echo "exit=$?"
```

```text
exit=0
```

**The publisher reports success.** Terminal 1 shows: nothing. The message was
evaluated against the policy, failed the minimum-QoS requirement, and was not
delivered to subscribers.

This is the point of the scenario. If you only trust your client's exit code,
you would swear that message was delivered.

## 5. Ask TrailMQ what it decided

```bash
curl -sS "http://localhost/api/v1/policies/violations?clientId=qos-test&limit=5" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.items[0]'
```

```json
{
  "policyId": "evaluator-qos1",
  "topic": "public/demo/temperature",
  "clientId": "qos-test",
  "violation": "qos_too_low",
  "details": "QoS level below required minimum (required=1, got=0)",
  "action": "block",
  "timestamp": "2026-07-20T09:20:41Z"
}
```

Everything a reviewer needs: which policy, which client, which topic, what
was wrong (`required=1, got=0`), and what TrailMQ did about it (`block`).

## Why this matters more than it looks

Three different things are easy to confuse, and TrailMQ separates them:

| | Means | Does **not** mean |
| --- | --- | --- |
| Publish call returned 0 | Your client handed the bytes over | The message was accepted |
| Broker sent PUBACK (QoS 1) | Transport-level receipt | Policy allowed it |
| Subscriber received payload | Actual application delivery | — |

A message can pass the first two and still be stopped. Without a recorded
decision you would have no way to tell the difference — you would just have a
gap in your data and no explanation.

## Known limitation, honestly

In the violation record the `qos` field is omitted when the failing value is
`0` (a JSON encoding detail). The actual value is in the `details` string
(`got=0`), which is where you should read it.

## Clean up

```bash
curl -sS -X DELETE "http://localhost/api/v1/policies/evaluator-qos1" \
  -H "Authorization: Bearer ${TOKEN}"
```

Removing the policy takes effect for new messages; the recorded violations
stay, which is the point.
