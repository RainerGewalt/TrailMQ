# Frequently asked questions

The questions engineers ask first, answered in the order they usually come up.
Each answer links to the document that goes deeper.

## Why was my MQTT publish denied?

Because one of **two independent gates** said no, and the recorded reason says
which one.

1. **The role's permission.** Does the role attached to your identity hold the
   operation at all — `publish`, `subscribe`?
2. **The namespace/topic rule.** Is there a rule that brings the requested topic
   into scope for one of the roles you hold?

Both must pass. A role with `publish:*` is still refused if no rule brings the
requested path into scope, because unknown namespaces fail closed until a topic
rule grants roles.

The refusal carries a canonical reason that tells the two causes apart:

| `reason` | What it means |
| --- | --- |
| `acl_role_not_in_topic_scope` | No rule brings this topic into scope for any role the identity holds. Gate 2. |
| `acl_role_action_not_permitted` | A rule covers the topic, and that role may not perform this operation. Gate 1. |

To read the reason for your own refusal, open the Preview at
**http://localhost/trailmq/**, filter **Activity** by **Outcome: Denied**, and
look at the decision detail — actor, MQTT client id, topic and a plain-language
explanation are attached. From the shell:

```bash
./trailmq logs backend | grep ACLMon
```

The full reason table is in the
[Secure MQTT Core reference](../recipes/secure-mqtt-core/README.md), and
[Denied by design](scenarios/02-denied-actions.md) walks a refusal end to end.

## What is the difference between MQTT authentication and MQTT authorization?

**Authentication** happens once, at CONNECT: the client proves *who it is*, with
credentials over MQTT/TLS or MQTT over WebSocket. It fails with
`Connection Refused: not authorised.` and the connection never opens.

**Authorization** happens on *every* PUBLISH and SUBSCRIBE afterwards: an
authenticated identity is checked against the two gates above for *this topic,
this operation, right now*. A perfectly valid login is refused a specific topic
without anything being wrong with the credentials.

Conflating them is the usual reason a denial is hard to explain: the client
connected fine, so the credentials are blamed last, when the topic scope was the
real answer. TrailMQ records the two separately — `acl_unauthenticated` is an
authentication result, every other `acl_*` reason is an authorization result.

## Why does my MQTT client show a network protocol error instead of "not authorized"?

Because MQTT 3.1.1 has no return code for "this publish was refused". There is
no `PUBACK` that means *denied*, so a broker has exactly two options: drop the
connection, or say nothing. What the client prints is the broker's reaction, not
a description of the decision.

| You did | Symptom on the client | What actually happened |
| --- | --- | --- |
| Publish at QoS 1 to a denied topic | `Error: A network protocol error occurred…` | The ACL denied it; at QoS 1 the broker disconnects instead of acknowledging |
| Publish at QoS 0 to a denied topic | Nothing — it "succeeds" locally | QoS 0 has no acknowledgement; the message is discarded |
| Subscribe without a `subscribe:` permission | Connection stays up, no messages arrive | The subscription was denied; nothing is delivered |

This is exactly the gap TrailMQ closes. The client cannot tell you why, so the
decision is recorded on the broker side with actor, role, client id, topic,
outcome and reason, and reviewed in **Activity**. The full symptom table is in
[Connect an MQTT client](connect-a-client.md).

## Does a successful publish mean the message was delivered?

No. A publish that is *allowed* is an authorization result and an acceptance at
the broker. It is not proof that a subscriber received the payload.

At QoS 0 there is no acknowledgement at all, so a client reports success for a
message that was discarded. Preview counters are not delivery proof either.

To confirm delivery, observe it: `./trailmq verify` publishes to
`public/demo/temperature` and asserts that a real subscriber received it, which
is why the proof reports `[PASS] Authorized publish reached the subscriber`
rather than counting accepted publishes.
[Message policy and QoS](scenarios/07-message-policy-qos.md) makes the
difference visible.

## Does the integrity check cover every MQTT decision?

No, and the product says so next to its own verdict.

The hash-linked chain walks the **system/action audit store**: sign-ins,
administrative changes, identity and role changes, policy changes and
topic-rule changes. `./trailmq verify` validates that chain, and **Activity**
shows the same verdict with its scope.

**MQTT decision records are recorded and reviewed separately.** They are not
part of the validated chain — the API reports this itself as `chain.excluded`.
A valid verdict does not prove that every MQTT payload is included,
tamper-checked, externally anchored or digitally signed.

Keeping those apart is deliberate. Conflating them is how a system ends up
claiming more than it can show. See
[Trust and evidence scope](../README.md#trust-and-evidence-scope) and
[Tamper evidence](scenarios/04-tamper-evidence.md).

## Is TrailMQ open source?

No. TrailMQ is distributed under a **proprietary evaluation license**.

This repository is public and free to use for personal learning, local demos
and non-production technical evaluation. It contains the `./trailmq` launcher,
the ready-to-run Docker recipe, configuration examples, scenarios and
documentation. The backend and frontend are delivered as signed Docker images;
their source is not part of this repository.

Production, commercial, managed-hosting, redistribution and customer-facing use
require a separate agreement. See [LICENSE](../LICENSE), or write to
**contact@trailmq.com**.

## Still stuck?

Run `./trailmq doctor` first — it checks Docker, config, certificates,
credentials and ports — then see [Troubleshooting](troubleshooting.md).
