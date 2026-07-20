# Scenarios

Hands-on walkthroughs against the local evaluation stack. Every command here
was verified against a running system — including the outputs.

## Start here

**New to TrailMQ?** Read
[Scenario 0 — Why not just use a broker?](00-why-not-just-a-broker.md) first.
It runs the same commands against a standard MQTT broker and against TrailMQ
and lets the difference speak for itself. Everything else builds on that.

**Want the 30-second version?** `./trailmq verify` proves the core claim
automatically.

## The question each scenario answers

| | Scenario | The question it answers |
| --- | -------- | ----------------------- |
| 0 | [Why not just use a broker?](00-why-not-just-a-broker.md) | "We already have MQTT. What is actually different here?" |
| 1 | [Sensor to dashboard](01-sensor-to-dashboard.md) | "Does normal MQTT traffic still just work?" |
| 2 | [Denied by design](02-denied-actions.md) | "What happens when something is *not* allowed — and how would I notice?" |
| 3 | [Govern a namespace](03-governed-namespace.md) | "How do I open up a topic for a specific team, without opening everything?" |
| 4 | [Tamper evidence](04-tamper-evidence.md) | "If someone edits the history, would anyone ever know?" |
| 5 | [Add your own user](05-add-your-own-user.md) | "How do I give someone read-only access?" |
| 6 | [Queue & dead letters](06-queue-and-dead-letters.md) | "What happens to messages that can't be processed right now?" |
| 7 | [When "success" isn't delivery](07-message-policy-qos.md) | "Can a message silently disappear even though my client says it worked?" |

## Suggested paths

**"Convince me in 10 minutes"** → 0 → 2 → 4

The difference to a plain broker, what enforcement looks like, and why the
record can be trusted.

**"I need to actually run something"** → 1 → 3 → 5

Get traffic flowing, govern a real namespace, onboard a colleague.

**"I care about data integrity"** → 7 → 4 → 6

Silent message loss, tamper detection, and what happens to messages that
fail processing.

## Prerequisites

```bash
./trailmq quickstart     # stack is up
./trailmq credentials    # shows the generated passwords
```

Plus [`mosquitto-clients`](https://mosquitto.org/) (`mosquitto_pub` /
`mosquitto_sub`) for all scenarios, and `curl` + `jq` for scenarios 3, 6
and 7.

Scenarios 3, 6 and 7 share a login token and the topic created in scenario 3,
so run them in order if you want to follow along exactly.

## The one thing to take away

If you only remember one sentence from these walkthroughs:

> A broker moves messages. TrailMQ decides about them, enforces the decision,
> and keeps a record you can check afterwards.
