# TrailMQ documentation

Use this page to reach the right document without reading the repository from
top to bottom.

## Start by outcome

| I want to… | Go to |
| --- | --- |
| see TrailMQ work with the fewest steps | [Quickstart](quickstart.md) |
| understand the product difference | [Why not just use a broker?](scenarios/00-why-not-just-a-broker.md) |
| connect an MQTT client | [Connect an MQTT client](connect-a-client.md) |
| test a realistic workflow | [Guided scenarios](scenarios/README.md) |
| add, rotate, or revoke an evaluation user | [Access management](access-management.md) |
| understand the trust and evidence model | [Architecture](architecture.md) |
| call the REST API | [Secure MQTT Core reference](../recipes/secure-mqtt-core/README.md) |
| fix a setup or runtime problem | [Troubleshooting](troubleshooting.md) |

## Recommended evaluation sequence

```text
Quickstart
    ↓
Automated decision proof
    ↓
Connect your own client
    ↓
Run one scenario that matches your risk
    ↓
Review architecture and evaluation boundaries
```

1. Run `./trailmq quickstart` and `./trailmq verify`.
2. Open the Preview and locate the blocked decision under **Activity**.
3. Publish one value from your own MQTT client.
4. Choose a scenario:
   - authorization risk → [Denied by design](scenarios/02-denied-actions.md);
   - namespace governance → [Govern a namespace](scenarios/03-governed-namespace.md);
   - record integrity → [Tamper evidence](scenarios/04-tamper-evidence.md);
   - silent delivery failure → [Message policy and QoS](scenarios/07-message-policy-qos.md).
5. Read the [evaluation boundaries](../README.md#evaluation-boundaries) before
   making a production-fit or compliance assessment.

## Product model in three lines

```text
Transport     accepts standard MQTT clients over TLS or WebSocket
Enforcement   combines role permissions with namespace/topic policy
Evidence      keeps MQTT decisions reviewable and maintains a verifiable
              hash-linked system/action audit chain
```

The shortest useful summary is: TrailMQ makes MQTT access decisions at the
broker boundary and keeps the decision evidence available for later review.

## Reference

| Area | Document |
| --- | --- |
| Configuration examples | [Users](config-examples/users.yaml) · [Roles](config-examples/roles.yaml) |
| Recipe configuration and endpoints | [Secure MQTT Core](../recipes/secure-mqtt-core/README.md) |
| Extension direction | [Plugins](plugins.md) |
| Vulnerability reporting | [Security policy](../SECURITY.md) |
| Contribution scope | [Contributing](../CONTRIBUTING.md) |

## Current evaluation boundaries

- The public Preview is primarily for reading and reviewing. Use configuration
  files and the REST API for operational changes.
- Removing a configured user does not revoke a user already stored by merge
  sync. Use the documented [offboarding procedure](access-management.md#revoke-an-evaluation-user).
- The automated chain check covers the system/action audit chain. Do not infer
  that every MQTT payload is shown in the Preview or validated by the same
  endpoint.
- Local demo certificates, credentials, and permissive evaluation origins are
  not production defaults.
- TrailMQ can support traceability and regulated workflows, but does not make a
  complete deployed system compliant by itself.

