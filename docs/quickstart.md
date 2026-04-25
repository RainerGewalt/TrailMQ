# Quickstart

This page exists for people who don't want to read the whole README.

## 30 seconds

```bash
git clone https://github.com/RainerGewalt/TrailMQ.git
cd TrailMQ
./trailmq launch
```

Pick `[1] Secure MQTT Core`. When asked about certificates, pick `[1]
Generate local demo certificates`. Wait for Docker to pull images. Done.

Open **http://localhost/trailmq/** in your browser.

## What just happened

`./trailmq launch` did four things:

1. Selected the `secure-mqtt-core` recipe and marked it as active
2. Generated a local self-signed CA + server certificate
3. Generated a 64-character JWT secret
4. Ran `docker compose up -d` inside `recipes/secure-mqtt-core/`

State lives in two places:

- `.trailmq/active-recipe` — tracks which recipe is active
- `recipes/secure-mqtt-core/` — everything else (config, certs, data, logs)

All runtime data is gitignored. The repo stays clean.

## Logging in

Evaluation credentials are in
[`recipes/secure-mqtt-core/config.yaml`](../recipes/secure-mqtt-core/config.yaml)
under the `users:` key. **They exist for local evaluation only** — rotate or
remove them before any non-local deployment.

## Stopping and starting again

```bash
./trailmq down      # stops the stack, keeps data
./trailmq up        # starts it back up
./trailmq status    # shows what's running
./trailmq logs      # tails the logs
./trailmq reset     # wipes data, keeps the recipe
```

## Something's off?

```bash
./trailmq doctor
```

Doctor checks Docker, the active recipe, config, certs, secrets, and ports.

## Using your own certificates

Drop `server_cert.pem`, `server_key.pem`, and `ca_cert.pem` into
`recipes/secure-mqtt-core/certs/`. The stack picks them up on the next
`./trailmq up`.

If you later want to regenerate demo certs, run `./trailmq certs` — it asks
before overwriting.
