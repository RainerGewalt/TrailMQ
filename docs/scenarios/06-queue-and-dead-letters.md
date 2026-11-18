# Scenario 6 — Queue, consumer groups and dead letters

**Goal:** watch what happens to messages on a queue-enabled topic: publish
over MQTT, consume over REST as a consumer group, acknowledge one message and
dead-letter another — with visible state at every step.

**What you learn:** on queue-enabled topics TrailMQ writes accepted publishes
to a queue for consumer groups, and a message a consumer rejects ends up in an
inspectable dead-letter queue. A publisher's acknowledgement does not prove
that the message reached the queue; see
[What an acknowledgement does not tell you](#what-an-acknowledgement-does-not-tell-you)
for what does, and for the counter to watch.

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

The message you rejected is flagged, attributed to its topic, and waiting
for review. Final `stats`:

```json
{ "acked": 1, "dlq": 1, "inflight": 0, "ready": 0 }
```

## Boundary worth knowing

Queueing is **post-publish processing**: the broker accepts and routes the
MQTT message first, then records it for queue consumers. Queue rejection does
not retroactively undo broker delivery to live MQTT subscribers — it governs
the store-and-process path.

### What an acknowledgement does not tell you

For a QoS 1 publish, the broker sends `PUBACK` **before** TrailMQ writes the
message's queue row. The acknowledgement tells the publisher that the broker
accepted the publish. It does not tell it that the message was stored.

After the acknowledgement, a publish on a queue-enabled topic ends up in one of
three places:

| Outcome | When | What records it |
| --- | --- | --- |
| In the topic's queue | the normal case | `ready` in the topic's `stats` |
| In the dead-letter queue | the queue row could not be written, a dead-letter fallback applies, and the dead-letter write succeeds — for example when the topic's queue is full | `deadLetterMessages` in `/api/v1/queue/status`, `/api/v1/queue/deadletter` |
| Nowhere | the row could not be written and no dead-letter fallback applied or succeeded — for example when the topic cannot be resolved or the database insert fails | `rejectedPublishes` and a backend log line |

Whether a dead-letter fallback applies depends on the topic's delivery class,
so a full queue does not send every message to the dead-letter queue.

**Watch `rejectedPublishes`.** It counts publishes the backend did not write to
their topic's queue, including some that the dead-letter fallback then stored.
A rising value means that publishers hold acknowledgements for messages your
consumers may never see:

```bash
curl -sS "http://localhost/api/v1/queue/status" \
  -H "Authorization: Bearer ${TOKEN}" \
  | jq '{rejectedPublishes, deadLetterMessages, enqueueBufferDrops}'
```

The counter lives in the backend's memory. It starts at zero when the backend
starts, and an administrator can reset it, so read it as a rate over time
rather than as a total since installation. The 3.1.2 images do not count three
of these exits (a topic that cannot be resolved, a full topic whose dead-letter
write also fails, and a failed insert). From 3.2, each of them is counted and
logged.

Where losing an acknowledged message is not acceptable, the publisher needs an
end-to-end check of its own, such as a consumer that confirms what it
received. The acknowledgement cannot provide one.
