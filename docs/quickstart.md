# Quickstart: from clone to a verified MQTT decision

This is the shortest path to a successful TrailMQ evaluation. It starts the
stack, proves one allowed and one blocked MQTT action, and shows you where to
review the result.

## Before you start

You need:

- Docker 20.10 or newer;
- Docker Compose v2 (`docker compose`, not the legacy `docker-compose`);
- Bash on Linux, macOS, or WSL;
- internet access for the first Docker image pull.

You do **not** need a local MQTT client for the automated proof. TrailMQ uses a
temporary Docker client when `mosquitto_pub` and `mosquitto_sub` are absent.

## 1. Start the evaluation stack

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq quickstart
```

On the first run, Docker may need a few minutes to download the images. The
launcher then:

1. selects the `secure-mqtt-core` recipe;
2. creates local self-signed certificates;
3. creates a JWT secret;
4. generates local passwords for `testadmin` and `testuser`;
5. starts the Docker Compose stack.

All generated state is gitignored.

## 2. Run the decision proof

```bash
./trailmq verify
```

After the images are available, this normally takes about 30 seconds. It exits
non-zero when a check fails, so it also works as a local smoke test.

Expected result:

```text
[PASS] Runtime ready
[PASS] MQTT TLS listener accepts authenticated clients
[PASS] Authorized publish reached the subscriber   public/demo/temperature
[PASS] Unauthorized publish was blocked            restricted/ops/config
[PASS] Denial recorded with user, role, action and topic
[PASS] REST API authentication issues a token
[PASS] System/action audit chain intact

7/7 checks passed
```

This is the core product proof: authenticated traffic flows, unauthorized
traffic is blocked, the reason is attributable, and the recorded system/action
history still forms a valid hash chain.

## 3. Review the result

Print the generated login and local endpoints:

```bash
./trailmq credentials
./trailmq open
```

Open **http://localhost/trailmq/**, log in as `testadmin`, open **Activity**,
and filter for **Outcome: Denied**.

The Evaluation Preview is a review-first UI. Use the REST API and
`recipes/secure-mqtt-core/config.yaml` for changes such as creating a governed
topic or adding a role.

## What was created

| Path | Purpose |
| --- | --- |
| `.trailmq/active-recipe` | remembers the selected recipe |
| `recipes/secure-mqtt-core/certs/` | generated local CA and server certificate |
| `recipes/secure-mqtt-core/secrets/` | generated JWT secret and evaluation passwords |
| `recipes/secure-mqtt-core/data/` | runtime database and state |
| `recipes/secure-mqtt-core/logs/` | local logs |
| `recipes/secure-mqtt-core/audit-archive/` | archived audit material |

Do not commit or share generated credentials, private keys, runtime databases,
or audit exports.

## Your next useful step

| If you want to… | Continue with |
| --- | --- |
| understand the differentiator | [Why not just use a broker?](scenarios/00-why-not-just-a-broker.md) |
| send data from your own code | [Connect an MQTT client](connect-a-client.md) |
| test authorization failures | [Denied by design](scenarios/02-denied-actions.md) |
| govern a new namespace | [Govern a namespace](scenarios/03-governed-namespace.md) |
| test history integrity | [Tamper evidence](scenarios/04-tamper-evidence.md) |
| understand current limits | [Evaluation boundaries](../README.md#evaluation-boundaries) |

## Daily commands

```bash
./trailmq status       # runtime and audit status
./trailmq logs         # follow stack logs
./trailmq down         # stop, keep local data
./trailmq start        # start or repair the setup
./trailmq reset        # remove runtime data, keep certs and credentials
```

`reset` asks for confirmation. `purge` removes all generated state for the
active recipe, including certificates and credentials.

## If something fails

Run the built-in diagnosis first:

```bash
./trailmq doctor
```

For port conflicts, certificate problems, credential-policy errors, and
delivery symptoms, see [Troubleshooting](troubleshooting.md).

## Security note about user removal

The evaluation uses `authsyncmode: "merge"`. Removing a user from
`config.yaml` does not by itself remove a user already stored in the runtime
database. Use [Access management](access-management.md) when adding, rotating,
or revoking an evaluation identity.
