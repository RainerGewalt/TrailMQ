# Scenario 5 — Add your own user

**Goal:** add a read-only "viewer" account the governed way — a user that can
watch everything on `public/#` but can never publish.

**What you learn:** configured users and roles start in one reviewable config
file, passwords live in separate secret files, runtime identities persist in
the database, and role permissions compose with namespace ACLs.

> **Access-lifecycle warning:** this recipe uses `authsyncmode: "merge"`.
> Removing a user from `config.yaml` or deleting the password file does not
> revoke a user already stored in the runtime database. The cleanup section
> uses the API to remove that runtime identity as well.

## 1. Create the password file

The backend enforces a password policy: upper and lower case, a digit and a
special character (`-` and `_` are safe choices):

```bash
printf 'Vw31-kMyPanel_9xC' > recipes/secure-mqtt-core/secrets/testviewer.pwd
chmod 600 recipes/secure-mqtt-core/secrets/testviewer.pwd
```

(Pick your own value — this is a local evaluation credential.)

## 2. Declare the user in the config

Add this block under `users:` in `recipes/secure-mqtt-core/config.yaml`:

```yaml
  - username: testviewer
    password_file: ./secrets/testviewer.pwd
    roles: [viewer]
    email: ""
    enabled: true
    managed_by_config: true
```

The `viewer` role is already declared in the same file with
`permissions: ["subscribe:*"]` — subscribe anywhere the namespace ACL allows,
publish nowhere.

> The backend validates every `password_file` at startup — a user entry
> pointing at a missing file stops the container. Create the file first
> (step 1), then declare the user.

## 3. Restart the backend

The config is read at startup:

```bash
docker restart trailmq-backend
```

Wait a few seconds, or watch `./trailmq status` until the backend is healthy.

## 4. Prove it — subscribe works…

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
USER_PW=$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)

# Terminal 1 — the new viewer watches
mosquitto_sub -h localhost -p 8883 --cafile "$CA" \
  -u testviewer -P "$(cat recipes/secure-mqtt-core/secrets/testviewer.pwd)" \
  -i viewer-panel -t 'public/#' -T 'trailmq/#' -v

# Terminal 2 — publish something as testuser
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$USER_PW" \
  -t 'public/demo/temperature' -q 1 -m '{"for":"viewer"}'
```

Terminal 1 prints:

```text
public/demo/temperature {"for":"viewer"}
```

## 5. …and publishing is denied

```bash
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testviewer -P "$(cat recipes/secure-mqtt-core/secrets/testviewer.pwd)" \
  -t 'public/demo/temperature' -q 1 -m 'x'
```

```text
Error: A network protocol error occurred when communicating with the broker.
```

```bash
./trailmq logs backend | grep ACLMon
# [ACLMon] DENY user="testviewer" roles=[viewer] action=publish topic="public/demo/temperature"
```

The role never received a `publish:` permission, so the broker fails closed —
regardless of the namespace.

## Variations

- Scope the role instead of using `subscribe:*` — e.g. a gateway role with
  `permissions: ["publish:factory/line-1/#", "subscribe:factory/line-1/commands/+"]`.
  More patterns: [docs/config-examples/roles.yaml](../config-examples/roles.yaml).
- Prefer a pre-hashed password? See
  [docs/config-examples/users.yaml](../config-examples/users.yaml) for the
  `password_hash` (argon2id) form.

## Clean up (optional)

Removing only the YAML block is not sufficient in merge mode. Follow these
steps:

1. Remove the `testviewer` block from `config.yaml` so a later restart cannot
   recreate it.
2. Use the admin API to find and delete the persisted runtime user:

   ```bash
   ADMIN_PW=$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)
   TOKEN=$(
     curl -sS -X POST http://localhost/api/v1/auth \
       -H 'Content-Type: application/json' \
       -d "{\"username\":\"testadmin\",\"password\":\"${ADMIN_PW}\"}" \
     | jq -r '.token'
   )

   USER_ID=$(
     curl -sS http://localhost/api/v1/users \
       -H "Authorization: Bearer ${TOKEN}" \
     | jq -r '.items[] | select(.username == "testviewer") | .id'
   )

   test -n "${USER_ID}" || { echo 'User not found'; exit 1; }

   curl -sS -X DELETE "http://localhost/api/v1/users/${USER_ID}" \
     -H "Authorization: Bearer ${TOKEN}"
   ```

3. Delete `secrets/testviewer.pwd`, restart the backend, and confirm that a new
   connection with the old credentials is rejected.

See [Access management](../access-management.md) for the complete identity
lifecycle and the reason both config and runtime state must be handled.
