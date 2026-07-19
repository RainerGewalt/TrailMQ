# Scenarios

Hands-on walkthroughs against the local evaluation stack. Each scenario is
self-contained, takes a few minutes, and every command has been verified
against a running stack.

Prerequisites for all scenarios:

```bash
./trailmq quickstart        # stack is up
./trailmq credentials       # shows the generated passwords
```

plus [`mosquitto-clients`](https://mosquitto.org/) (`mosquitto_pub` /
`mosquitto_sub`) and, for scenario 3, `curl` and `jq`.

| Scenario | What you see | Time |
| -------- | ------------ | ---- |
| [1 — Sensor to dashboard](01-sensor-to-dashboard.md) | A publisher-role client delivers data to a subscriber through the open `public/#` namespace; the traffic appears in the Web UI | ~3 min |
| [2 — Denied by design](02-denied-actions.md) | Wrong password, forbidden namespace, and a publish-only role trying to subscribe — and what each denial looks like | ~3 min |
| [3 — Govern a namespace](03-governed-namespace.md) | Open up a deny-by-default namespace by creating a topic with allowed roles, then verify the effective config and the audit chain | ~5 min |
| [4 — Tamper evidence](04-tamper-evidence.md) | Edit one audit record behind TrailMQ's back — chain validation flags the exact record with a hash mismatch | ~5 min |
| [5 — Add your own user](05-add-your-own-user.md) | A read-only viewer account: config + secret file + restart, then subscribe works and publish fails closed | ~5 min |
| [6 — Queue & dead letters](06-queue-and-dead-letters.md) | Consume a queue-enabled topic as a consumer group: dispatch by priority, ack, and dead-letter a failed message | ~5 min |

Scenarios 3, 4 and 6 build on each other (login token, governed topic). In a
hurry? `./trailmq demo` runs the core of scenarios 1 and 2 automatically.
