# Scenario 0 — Why not just use a broker?

**The question everyone asks first:** MQTT brokers already exist and they work.
What does TrailMQ actually do differently?

This scenario answers it by running **the exact same three commands** against a
standard MQTT broker and against TrailMQ, side by side. No slides, no claims —
just two terminals and two very different outcomes.

Time: ~5 minutes. You need Docker and `mosquitto_pub` / `mosquitto_sub`.

## The setup

Start a standard broker next to your running TrailMQ stack. This is
`eclipse-mosquitto` in its default open configuration — the way countless
MQTT deployments actually run:

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

No username. No password. No certificate. The shutdown command went through.

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

**Standard broker** — everything it knows:

```bash
docker logs plain-mosquitto | tail -4
```

```text
New connection from 172.17.0.1:53000 on port 1883.
New client connected from 172.17.0.1:53000 as mosq-JcA10SwAsAJvaIkhgJ (p4, c1, k60).
Client mosq-JcA10SwAsAJvaIkhgJ [172.17.0.1:53000] disconnected.
New client connected from 172.17.0.1:53016 as mosq-7M6CFMC81vzucxWF6n (p4, c1, k60, u'definitely-not-a-real-user').
```

Someone connected. Someone disconnected. **Which topic was written to is not
in there. What was sent is not in there. Whether it should have been allowed
was never a question.** If you were asked six months later "who sent the
shutdown command?", this log cannot answer it.

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
**Outcome: Denied**: the same denial as a recorded, timestamped event —
hash-linked to its predecessor so later edits become detectable
([scenario 4](04-tamper-evidence.md) proves that part).

## The scoreboard

| | Standard broker | TrailMQ |
| --- | --- | --- |
| Anonymous write to a sensitive topic | Accepted | Refused at connect |
| Unverified identity | Accepted as-is | Rejected |
| Authenticated but unauthorized write | *(no such concept)* | Blocked, connection dropped |
| Record of which topic was written | No | Yes |
| Record of *why* it was allowed or denied | No | Yes — user, role, action, topic |
| Can recorded system/action history be checked for tampering | No | Yes, SHA-256 chain |

## To be fair to the broker

A standard broker **can** be configured with TLS, password files and ACL
files. The difference isn't that it's impossible — it's:

- **Defaults.** The open configuration above is a realistic starting point;
  TrailMQ fails closed by default (`restricted/#` admin-only, unknown
  namespaces deny-by-default).
- **Evidence.** Broker ACLs decide and then forget. TrailMQ treats the
  decision as something worth recording, attributing and verifying later.
- **Reviewability.** ACL files are edited on a server. TrailMQ exposes the
  *effective* configuration and decisions over an API and a UI, so you can
  answer questions without SSH access.

The public chain check covers TrailMQ's system/action audit store. It is local
tamper evidence, not external notarization, WORM storage, or a claim that every
MQTT payload is included. [Architecture](../architecture.md#what-the-evidence-chain-proves)
defines the trust boundary precisely.

That is the whole product in one sentence:

> A broker moves messages. TrailMQ decides about them, enforces the decision,
> and keeps a record you can check afterwards.

## Clean up

```bash
docker rm -f plain-mosquitto
```

## Next

- [Scenario 1](01-sensor-to-dashboard.md) — the happy path in detail
- [Scenario 7](07-message-policy-qos.md) — where it gets genuinely subtle:
  a publish that reports **success** and still never arrives
