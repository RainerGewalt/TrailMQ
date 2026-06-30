# Troubleshooting

Use `./trailmq doctor` first. It checks Docker, the active recipe, config,
certificates, secrets, referenced password files, and common ports.

```bash
./trailmq doctor
```

## Docker or Compose is missing

TrailMQ expects Docker 20.10+ and Docker Compose v2.

Check:

```bash
docker --version
docker compose version
```

The old `docker-compose` command is not enough; the CLI uses
`docker compose`.

## Port 80 or 8883 is already in use

By default TrailMQ binds:

- `80` for the Web UI and REST API
- `8883` for MQTT over TLS

Use `.env` to choose different host ports:

```bash
cp .env.example .env
```

Edit:

```env
TRAILMQ_HTTP_PORT=8080
TRAILMQ_MQTT_TLS_PORT=8884
```

Then restart:

```bash
./trailmq down
./trailmq start
```

The URLs become:

```text
http://localhost:8080/trailmq/
http://localhost:8080/api/v1
localhost:8884
```

## No active recipe

Run the quickstart once:

```bash
./trailmq quickstart
```

That writes `.trailmq/active-recipe`.

## Missing certificates

Generate local demo certificates:

```bash
./trailmq certs
```

This creates:

```text
recipes/secure-mqtt-core/certs/ca_cert.pem
recipes/secure-mqtt-core/certs/server_cert.pem
recipes/secure-mqtt-core/certs/server_key.pem
```

These certificates are self-signed and for local evaluation only.

## Missing credentials

The launcher generates evaluation passwords on first run:

```text
recipes/secure-mqtt-core/secrets/testadmin.pwd
recipes/secure-mqtt-core/secrets/testuser.pwd
```

Read the admin password:

```bash
cat recipes/secure-mqtt-core/secrets/testadmin.pwd
```

Print the current generated login:

```bash
./trailmq credentials
```

If the files are missing, run `./trailmq quickstart` again. To rotate local
evaluation passwords, delete the `.pwd` files and launch again.

## Stack starts but API calls fail

Check readiness:

```bash
curl -sS http://localhost/ready
```

If you changed `TRAILMQ_HTTP_PORT`, include it:

```bash
curl -sS http://localhost:8080/ready
```

Then check logs:

```bash
./trailmq logs
```

## Reset local runtime data

Keep certs and secrets, but remove data, logs, and audit archive:

```bash
./trailmq reset
```

Remove everything generated for the active recipe:

```bash
./trailmq purge
```

Both commands ask for confirmation before deleting local runtime files.
