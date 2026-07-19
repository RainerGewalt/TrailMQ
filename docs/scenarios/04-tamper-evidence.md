# Scenario 4 — Tamper evidence, demonstrated

**Goal:** modify one recorded audit entry behind TrailMQ's back and watch the
chain validation catch it — down to the exact record.

**What you learn:** every system/action audit record is SHA-256-linked to its
predecessor. Changing stored history breaks the recomputed hash, and the
validation endpoint reports precisely where.

> ⚠️ **Local evaluation stack only.** This scenario deliberately edits the
> evaluation database. Requires the `sqlite3` CLI. Never do this to data you
> care about.

Log in first (as in [scenario 3](03-governed-namespace.md)) so `TOKEN` is set.

## 1. Baseline — the chain is intact

```bash
curl -sS -o /tmp/chain.json -w 'HTTP %{http_code}\n' \
  "http://localhost/api/v1/audit/validatechain/details" \
  -H "Authorization: Bearer ${TOKEN}"
jq '{valid, checkedEntries, issues}' /tmp/chain.json
```

```text
HTTP 200
{ "valid": true, "checkedEntries": 293, "issues": null }
```

## 2. Tamper with one record

Stop the backend and edit a single recorded value directly in the database —
exactly what an attacker (or a careless script) with file access might do:

```bash
docker stop trailmq-backend

sqlite3 recipes/secure-mqtt-core/data/mqtrail.db \
  "UPDATE audit_logs SET details = replace(details, 'disconn', 'TAMPERED')
   WHERE id = (SELECT id FROM audit_logs
               WHERE details LIKE '%disconn%'
               ORDER BY timestamp DESC LIMIT 1);"

docker start trailmq-backend
```

Wait until `./trailmq status` shows the backend healthy again.

## 3. Validation catches it

```bash
curl -sS -o /tmp/chain.json -w 'HTTP %{http_code}\n' \
  "http://localhost/api/v1/audit/validatechain/details" \
  -H "Authorization: Bearer ${TOKEN}"
jq '{valid, checkedEntries, firstIssue: .issues[0]}' /tmp/chain.json
```

```text
HTTP 409
{
  "valid": false,
  "checkedEntries": 292,
  "firstIssue": {
    "logId": "693b99f4…",
    "issue": "hash_mismatch",
    "expected": "ce4cc8c2…",
    "actual": "6b034f25…",
    "message": "recomputed hash does not match stored hash"
  }
}
```

The endpoint switches to HTTP `409 Conflict`, `valid` flips to `false`, and
the issue names the exact tampered record with the expected and recomputed
hash.

## 4. Restore

Because this demo knew the original value, putting it back repairs the chain
(integrity is about content, not timestamps of edits):

```bash
docker stop trailmq-backend
sqlite3 recipes/secure-mqtt-core/data/mqtrail.db \
  "UPDATE audit_logs SET details = replace(details, 'TAMPERED', 'disconn')
   WHERE details LIKE '%TAMPERED%';"
docker start trailmq-backend
```

Re-run step 1 — `HTTP 200`, `"valid": true` again. In a real incident you
would *not* know the original value; the mismatch itself is the finding.
Alternatively, wipe the evaluation data entirely with `./trailmq reset`.

## What this is — and is not

- **Is:** a local integrity check over the hash-linked system/action audit
  store. Any modification of recorded entries becomes detectable.
- **Is not:** immutability. Records are not externally anchored,
  independently signed, or protected against an attacker who also recomputes
  every subsequent hash. Treat it as tamper *evidence*, and control file
  access to the database in any serious deployment.
