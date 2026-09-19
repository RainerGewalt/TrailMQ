# Scenario 0 — Why not just use a broker?

**The question everyone asks first:** MQTT brokers already exist and they work.
What does TrailMQ actually do differently?

This scenario compares three access questions using an explicitly open
Mosquitto configuration and TrailMQ's evaluation policy. It demonstrates these
two configurations; it does not benchmark secured brokers or establish that
other products lack access control, logging or investigation tools.

Time: ~5 minutes. You need Docker and `mosquitto_pub` / `mosquitto_sub`.

## The setup

Start a broker next to your running TrailMQ stack. The command explicitly
selects Mosquitto's no-authentication example configuration:

```bash
docker run -d --name plain-mosquitto -p 11883:1883 \
  eclipse-mosquitto:2 mosquitto -c /mosquitto-no-auth.conf
```

We will pretend `restricted/ops/config` is a topic that controls something
that matters — a production line, a setpoint, a shutdown command.

## Round 1 — Can a stranger write to it?

**Standard broker:**

```bash
mosquitto_pub -h localhost -p 11883 \
  -t 'restricted/ops/config' -m '{"shutdown":true}'
echo "exit=$?"
```

```text
exit=0
```

No username, password or certificate was supplied, and the client command
returned success. This QoS 0 client result does not establish subscriber
delivery; no subscriber observation is made in this step.

**TrailMQ:**

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)" \
  -t 'restricted/ops/config' -q 1 -m '{"shutdown":true}'
```

```text
Error: A network protocol error occurred when communicating with the broker.
```

And that is with **valid credentials**. `testuser` authenticated
successfully — it simply isn't allowed in that namespace. Without credentials
it never gets past CONNECT at all.

## Round 2 — Does a made-up identity work?

**Standard broker:**

```bash
mosquitto_pub -h localhost -p 11883 \
  -u definitely-not-a-real-user \
  -t 'restricted/ops/config' -m 'x'
echo "exit=$?"
```

```text
exit=0
```

The username is accepted because nothing checks it. It appears in the log as
if it were real — an identity that was never verified.

**TrailMQ:**

```bash
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u definitely-not-a-real-user -P 'whatever' \
  -t 'restricted/ops/config' -m 'x'
```

```text
Connection error: Connection Refused: not authorised.
```

## Round 3 — Afterwards: what happened?

This is the part that matters most, and it is where the gap is widest.

**Open Mosquitto configuration** — the log output used in this example:

```bash
docker logs plain-mosquitto | tail -4
```

```text
New connection from 172.17.0.1:53000 on port 1883.
New client connected from 172.17.0.1:53000 as mosq-JcA10SwAsAJvaIkhgJ (p4, c1, k60).
Client mosq-JcA10SwAsAJvaIkhgJ [172.17.0.1:53000] disconnected.
New client connected from 172.17.0.1:53016 as mosq-7M6CFMC81vzucxWF6n (p4, c1, k60, u'definitely-not-a-real-user').
```

These example lines show connection activity. They do not establish a publish's
topic, authorization reason or subscriber receipt. That is the limit of this
configuration and observation, not a statement about every possible broker
logging or security configuration.

**TrailMQ** — the decision itself is the record:

```bash
./trailmq logs backend | grep ACLMon | tail -1
```

```text
[ACLMon] DENY user="testuser" roles=[publisher] action=publish topic="restricted/ops/config"
```

Who (`testuser`), with what authority (`roles=[publisher]`), tried to do what
(`publish`), where (`restricted/ops/config`), and what was decided (`DENY`).

Then open **http://localhost/trailmq/** → **Activity** → filter
**Outcome: Denied**: inspect the refusal's recorded identity, client, topic,
outcome and supported reason. This MQTT decision is **Outside validated scope**:
the built-in integrity verdict does not validate it. [Scenario 4](04-tamper-evidence.md)
tests the separate system/action audit chain; it does not prove integrity of
this MQTT refusal.

## The scoreboard

| | Open Mosquitto configuration used here | TrailMQ evaluation policy |
| --- | --- | --- |
| Anonymous write to a sensitive topic | Accepted | Refused at connect |
| Unverified identity | Accepted as-is | Rejected |
| Authenticated but unauthorized write | Authentication and ACL checks not configured in this example | Blocked; this QoS 1 example drops the connection |
| Recorded target of the demonstrated refused operation | Not shown in this example log | Yes, for the demonstrated recorded refusal |
| Attributable refusal and reason in this example | Not shown by this configuration's log | Recorded decision with identity, action, topic and supported reason |
| Can recorded system/action history be checked for tampering | No | Yes, SHA-256 chain |

## To be fair to the broker

A standard broker **can** be configured with TLS, password files and ACL
files. The difference isn't that it's impossible — it's:

- **Evaluation policy.** TrailMQ's evaluation restricts `restricted/#` to
  administrators and denies unknown namespaces until a rule grants access.
- **Attribution.** The demonstrated refusal carries the identity, operation,
  target and reason needed to investigate it.
- **Reviewability.** TrailMQ brings enforcement and decision review into one
  workflow through its API and Activity UI. Compare that workflow against your
  own configured broker and investigation process, rather than inferring a
  general capability difference from this open example.

The public chain check covers TrailMQ's system/action audit store. It is local
tamper evidence, not external notarization, WORM storage, or a claim that every
MQTT payload is included. [Architecture](../architecture.md#what-the-evidence-chain-proves)
defines the trust boundary precisely.

That is the whole product in one sentence:

> TrailMQ brings MQTT access enforcement and decision review into one workflow.

## Clean up

```bash
docker rm -f plain-mosquitto
```

## Next

- [Scenario 1](01-sensor-to-dashboard.md) — the happy path in detail
- [Scenario 7](07-message-policy-qos.md) — where it gets genuinely subtle:
  a publish that reports **success** and still never arrives
