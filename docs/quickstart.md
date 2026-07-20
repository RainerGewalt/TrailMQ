# Quickstart

This page exists for people who don't want to read the whole README.

## 30 seconds

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq quickstart
```

It selects `Secure MQTT Core`, generates local demo certificates, creates
evaluation credentials, and starts Docker Compose. Wait for Docker to pull
images. Done.

Open **http://localhost/trailmq/** in your browser.

Then let TrailMQ prove itself:

```bash
./trailmq verify
```

Seven checks in about 30 seconds: an authorized publish is delivered, an
unauthorized one is blocked, the denial is recorded with user and role, and
the audit chain still validates. Exits non-zero if anything fails, so you can
use it as a smoke test.

Next: [why this isn't just a broker](scenarios/00-why-not-just-a-broker.md),
the [scenarios](scenarios/), or [connect your own
client](connect-a-client.md).

## What just happened

`./trailmq quickstart` did five things:

1. Selected the `secure-mqtt-core` recipe and marked it as active
2. Generated a local self-signed CA + server certificate
3. Generated a 64-character JWT secret
4. Generated local evaluation passwords for `testadmin` and `testuser`
5. Ran `docker compose up -d` inside `recipes/secure-mqtt-core/`

State lives in two places:

- `.trailmq/active-recipe` — tracks which recipe is active
- `recipes/secure-mqtt-core/` — everything else (config, certs, data, logs)

All runtime data is gitignored. The repo stays clean.

## Logging in

The evaluation users are declared in
[`recipes/secure-mqtt-core/config.yaml`](../recipes/secure-mqtt-core/config.yaml).
Their generated passwords are stored in:

```text
recipes/secure-mqtt-core/secrets/testadmin.pwd
recipes/secure-mqtt-core/secrets/testuser.pwd
```

They exist for local evaluation only. Rotate or remove them before any
non-local deployment.

Print the generated login again at any time:

```bash
./trailmq credentials
```

## Stopping and starting again

```bash
./trailmq down      # stops the stack, keeps data
./trailmq start     # starts it back up
./trailmq status    # shows what's running
./trailmq logs      # tails the logs
./trailmq reset     # wipes data, keeps the recipe
```

## Something's off?

```bash
./trailmq doctor
```

Doctor checks Docker, the active recipe, config, certs, secrets, and ports.

## Port conflict?

If port `80` or `8883` is already in use, copy `.env.example` to `.env` and
choose different host ports:

```bash
cp .env.example .env
```

```env
TRAILMQ_HTTP_PORT=8080
TRAILMQ_MQTT_TLS_PORT=8884
```

Then start again with `./trailmq start`.

## Using your own certificates

Drop `server_cert.pem`, `server_key.pem`, and `ca_cert.pem` into
`recipes/secure-mqtt-core/certs/`. The stack picks them up on the next
`./trailmq start`.

If you later want to regenerate demo certs, run `./trailmq certs` — it asks
before overwriting.
