# Scenario 6 — Queue, consumer groups and dead letters

**Goal:** watch what happens to messages on a queue-enabled topic: publish
over MQTT, consume over REST as a consumer group, acknowledge one message and
dead-letter another — with visible state at every step.

**What you learn:** on queue-enabled topics TrailMQ persists accepted
publishes for later processing. Delivery problems don't vanish — they end up
in an inspectable dead-letter queue.

Requires the governed topic from
[scenario 3](03-governed-namespace.md) (`factory/line-1/temperature`,
created with `queueEnabled: true`) plus `curl` and `jq`. Log in as in
scenario 3 so `TOKEN` is set.

## 1. Produce two messages

One over MQTT (as the sensor), one directly into the queue via REST with a
higher priority:

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
USER_PW=$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)

mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$USER_PW" \
  -t 'factory/line-1/temperature' -q 1 -m '{"value":42.0}'

curl -sS -X POST "http://localhost/api/v1/queues/factory%2Fline-1%2Ftemperature/enqueue" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"payload": "{\"queued\": true}", "priority": 5}' | jq
```

Check the queue state:

```bash
curl -sS "http://localhost/api/v1/queues/factory%2Fline-1%2Ftemperature/stats" \
  -H "Authorization: Bearer ${TOKEN}" | jq
```

```json
{ "acked": 0, "dlq": 0, "inflight": 0, "ready": 2 }
```

## 2. Consume as a consumer group

```bash
curl -sS -X POST "http://localhost/api/v1/queues/factory%2Fline-1%2Ftemperature/dispatch" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"group": "review-1", "batchSize": 1}' | jq '.items[0] | {id, priority, payload}'
```

The **priority 5** message is dispatched first, even though it was enqueued
last. The payload is base64 — decode with
`jq -r '.items[0].payload' | base64 -d`.

## 3. Acknowledge it

Use the `id` from the dispatch response:

```bash
curl -sS -X POST "http://localhost/api/v1/queues/factory%2Fline-1%2Ftemperature/ack" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"group": "review-1", "ids": [3]}' | jq
```

`stats` now shows `"acked": 1, "ready": 1`.

## 4. Fail the second one into the dead-letter queue

Dispatch the remaining message, then reject it with an escalation policy
(`maxAttempts: 1` + `deadLetterEnabled` sends it to the DLQ immediately;
higher values re-queue it for retry first):

```bash
curl -sS -X POST "http://localhost/api/v1/queues/factory%2Fline-1%2Ftemperature/dispatch" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"group": "review-1", "batchSize": 1}' | jq '.items[0].id'

curl -sS -X POST "http://localhost/api/v1/queues/factory%2Fline-1%2Ftemperature/nack" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"group": "review-1", "ids": [2], "maxAttempts": 1, "deadLetterEnabled": true}' | jq
```

## 5. Review the dead letters

```bash
curl -sS "http://localhost/api/v1/queue/status" \
  -H "Authorization: Bearer ${TOKEN}" | jq '.breakdown'

curl -sS "http://localhost/api/v1/queue/deadletter" \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq '.items[] | {id, topic, attempts, deadLetter, payload}'
```

```json
{
  "id": 2,
  "topic": "factory/line-1/temperature",
  "attempts": 1,
  "deadLetter": true,
  "payload": "eyJ2YWx1ZSI6NDIuMH0="
}
```

The failed message is not lost — it is flagged, attributed to its topic, and
waiting for review. Final `stats`:

```json
{ "acked": 1, "dlq": 1, "inflight": 0, "ready": 0 }
```

## Boundary worth knowing

Queueing is **post-publish processing**: the broker accepts and routes the
MQTT message first, then records it for queue consumers. Queue rejection does
not retroactively undo broker delivery to live MQTT subscribers — it governs
the store-and-process path.
