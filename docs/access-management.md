# Access management in the evaluation stack

This guide explains where evaluation users come from and how to add, rotate,
and revoke them without confusing configuration state with runtime state.

All examples assume the default `secure-mqtt-core` recipe is running locally
and that `curl` and `jq` are installed.

## Understand the two user states

TrailMQ 3.0.0 starts with `authsyncmode: "merge"` in
`recipes/secure-mqtt-core/config.yaml`.

```text
config.yaml users ──merge on startup──▶ runtime user database
       │                                  │
       │ declaration                      │ active authentication state
       └─ removing an entry ──X───────────┘
```

Merge mode creates or synchronizes configured users, but it does not delete a
runtime user merely because that user is later absent from `config.yaml`.
Deleting only the YAML block or password file is therefore **not an access
revocation**.

## Inspect the built-in evaluation users

```bash
./trailmq credentials
```

| User | Role | Intended evaluation use |
| --- | --- | --- |
| `testadmin` | `admin` | Web UI, REST API, broad MQTT access |
| `testuser` | `publisher` | Publish to an allowed namespace |

They are local evaluation identities. Do not reuse them for a non-local
deployment.

## Add an evaluation user

1. Create a password file before editing the config. The password must contain
   upper- and lower-case characters, a digit, and a special character.

   ```bash
   printf 'Choose-A-Different9_Value' > \
     recipes/secure-mqtt-core/secrets/testviewer.pwd
   chmod 600 recipes/secure-mqtt-core/secrets/testviewer.pwd
   ```

2. Add the user below `users:` in
   `recipes/secure-mqtt-core/config.yaml`:

   ```yaml
     - username: testviewer
       password_file: ./secrets/testviewer.pwd
       roles: [viewer]
       email: ""
       enabled: true
       managed_by_config: true
   ```

3. Restart the backend so the config is merged into the runtime database:

   ```bash
   docker restart trailmq-backend
   ```

4. Verify the intended access. The `viewer` role may subscribe but not publish;
   the namespace ACL must also allow the role.

The complete hands-on flow is in
[Scenario 5 — Add your own user](scenarios/05-add-your-own-user.md).

## Rotate an evaluation password

Changing a password file alone does not prove that the persisted credential was
updated. For a clean local evaluation reset, remove the user through the API,
replace the file, and restart so merge sync recreates the user.

Use the same API login and lookup shown in the revocation procedure below. Do
not print passwords or tokens into issue reports or commit them to Git.

## Revoke an evaluation user

Use both configuration cleanup and runtime deletion.

### 1. Remove the declaration

Remove the user's block from `config.yaml`. This prevents merge sync from
recreating the user on the next backend start.

Keep the password file until the API operation is complete so you can recover
the previous setup if needed.

### 2. Log in as the evaluation admin

```bash
ADMIN_PW=$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)

TOKEN=$(
  curl -sS -X POST http://localhost/api/v1/auth \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"testadmin\",\"password\":\"${ADMIN_PW}\"}" \
  | jq -r '.token'
)
```

### 3. Find and delete the runtime user

Replace `testviewer` if you are revoking another evaluation identity.

```bash
USER_ID=$(
  curl -sS http://localhost/api/v1/users \
    -H "Authorization: Bearer ${TOKEN}" \
  | jq -r '.items[] | select(.username == "testviewer") | .id'
)

test -n "${USER_ID}" || { echo 'User not found'; exit 1; }

curl -sS -X DELETE "http://localhost/api/v1/users/${USER_ID}" \
  -H "Authorization: Bearer ${TOKEN}"
```

### 4. Remove the secret and verify denial

```bash
rm recipes/secure-mqtt-core/secrets/testviewer.pwd
docker restart trailmq-backend
```

Attempt a fresh connection with the old credentials and confirm it is rejected.
For a fully disposable evaluation environment, `./trailmq purge` followed by
`./trailmq quickstart` removes and recreates all generated runtime state.

## Important limits

- The Evaluation Preview currently exposes user and role information primarily
  for review; use the API/config workflow for lifecycle operations.
- The public evaluation API documents deletion, not a disable/enable workflow.
  After deletion, test a new login and review any already-connected client
  sessions explicitly.
- Always remove a config-managed user's declaration before deleting the runtime
  record, or the next startup may recreate it.
- The example is for local evaluation. Define a production identity lifecycle,
  credential policy, approval flow, and evidence-retention process separately.
