# Why was my MQTT access denied?

Three identities with different roles try five MQTT actions. Which are
accepted, which are refused, and where can you read the reason afterwards?
This page answers that with a run you can repeat yourself: once on TrailMQ,
and once, with the same policy, on Eclipse Mosquitto secured with its
Dynamic Security plugin.

It is a reproducible check, not a benchmark and not a feature comparison.
Every output below comes from one run on 7 November 2026 with TrailMQ 3.1.1
and Mosquitto 2.1.2 (`eclipse-mosquitto:2.1.2-alpine`). If your run gives a
different result, please
[open an evaluation report](https://github.com/RainerGewalt/TrailMQ/issues/new?template=evaluation-report.yml):
a run that contradicts this page is the most useful report there is.

Time: about ten minutes. You need the running evaluation stack
(`./trailmq try`), Docker, Bash and the `mosquitto_pub` / `mosquitto_sub`
clients. Run the commands from the repository root.

## The policy

One policy, set up on both brokers:

- the sensor role may publish to `public/#` and may not subscribe;
- `restricted/#` belongs to the operator role, which may also subscribe
  everywhere;
- an identity the broker does not know is refused at connect.

| Identity | Role | Client ids used |
| --- | --- | --- |
| `testuser` | sensor (`publisher` in TrailMQ) | `proof-sensor`, `proof-sensor-sub` |
| `testadmin` | operator (`admin` in TrailMQ) | `proof-ops-console`, `proof-observer` |
| `stranger` | none, unknown to the broker | `proof-stranger` |

TrailMQ ships this policy as its evaluation default: `testuser` holds
`publisher` (`publish:*`), `public/#` is open to every known role, and
`restricted/#` only to administrators
([how access is decided](../README.md#how-access-is-decided)). The
`proof-observer` subscription belongs to the operator and only shows what
really arrived.

## The five actions

Paste this function into your shell. It is the same for both brokers; only
the connection settings change.

```bash
proof() {
  timeout 12 mosquitto_sub "${BROKER[@]}" "${OPS[@]}" -i proof-observer \
    -t 'public/#' -t 'restricted/#' -T 'trailmq/#' -v > observer.txt &
  echo "1 sensor subscribes to public/#            (runs for 12 s)"
  timeout 12 mosquitto_sub "${BROKER[@]}" "${SENSOR[@]}" -i proof-sensor-sub \
    -t 'public/#' -T 'trailmq/#' -v > sensor-subscription.txt &
  sleep 2
  echo "2 sensor publishes public/demo/temperature"
  mosquitto_pub "${BROKER[@]}" "${SENSOR[@]}" -i proof-sensor \
    -t 'public/demo/temperature' -q 1 -m '{"t":21.5}'; echo "  exit=$?"
  echo "3 sensor publishes restricted/ops/config"
  mosquitto_pub "${BROKER[@]}" "${SENSOR[@]}" -i proof-sensor \
    -t 'restricted/ops/config' -q 1 -m '{"setpoint":42}'; echo "  exit=$?"
  echo "4 ops console publishes restricted/ops/config"
  mosquitto_pub "${BROKER[@]}" "${OPS[@]}" -i proof-ops-console \
    -t 'restricted/ops/config' -q 1 -m '{"setpoint":40}'; echo "  exit=$?"
  echo "5 stranger connects and publishes"
  mosquitto_pub "${BROKER[@]}" -u stranger -P 'Not-A-User_1' -i proof-stranger \
    -t 'public/demo/temperature' -q 1 -m 'x'; echo "  exit=$?"
  wait
  echo "observer received:"; sed 's/^/  /' observer.txt
  echo "sensor subscription received:"
  if [ -s sensor-subscription.txt ]; then sed 's/^/  /' sensor-subscription.txt; else echo "  (nothing)"; fi
}
```

Action 1 runs in the background for the whole run, so the sensor's own
publish in action 2 would reach it if the subscription had been accepted.

## Run it on TrailMQ

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
BROKER=(-h localhost -p 8883 --cafile "$CA")
SENSOR=(-u testuser  -P "$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)")
OPS=(-u testadmin -P "$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)")
proof
```

```text
1 sensor subscribes to public/#            (runs for 12 s)
2 sensor publishes public/demo/temperature
  exit=0
3 sensor publishes restricted/ops/config
Error: A network protocol error occurred when communicating with the broker.
  exit=2
4 ops console publishes restricted/ops/config
  exit=0
5 stranger connects and publishes
Connection error: Connection Refused: not authorised.
  exit=0
observer received:
  public/demo/temperature {"t":21.5}
  restricted/ops/config {"setpoint":40}
sensor subscription received:
  (nothing)
```

Shell job-control lines are left out here and below. Now read why the three
refusals happened, from the record rather than from the client:

```bash
TOKEN=$(curl -sS -X POST http://localhost/api/v1/auth \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"testadmin\",\"password\":\"$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)\"}" \
  | jq -r '.token')
curl -sS "http://localhost/api/v1/audit/messages?limit=3&refusals=true" \
  -H "Authorization: Bearer $TOKEN" \
  | jq -c '.items[] | {action, clientId, user, deniedTopic, reason}'
```

```text
{"action":"auth.deny","clientId":"proof-stranger","user":"stranger","deniedTopic":null,"reason":"user_not_found"}
{"action":"mqtt.publish.denied","clientId":"proof-sensor","user":"testuser","deniedTopic":"restricted/ops/config","reason":"acl_role_not_in_topic_scope"}
{"action":"mqtt.subscribe.denied","clientId":"proof-sensor-sub","user":"testuser","deniedTopic":"public/#","reason":"acl_role_action_not_permitted"}
```

The same refusals appear in the Web UI under **Activity**, filtered by
**Outcome: Denied**, and in the broker log (`./trailmq logs backend` shows
the same log, but keeps following it). Timestamps are left out here:

```bash
docker logs trailmq-backend 2>&1 | grep -E 'ACLMon|DENY user' | tail -3
```

```text
[ACLMon] DENY user="testuser" roles=[publisher] action=subscribe topic="public/#" reason=acl_role_action_not_permitted
[ACLMon] DENY user="testuser" roles=[publisher] action=publish topic="restricted/ops/config" reason=acl_role_not_in_topic_scope
[AuthMon] DENY user not found clientID="proof-stranger" user="stranger"
```

## Run it on a secured Mosquitto

The same policy on Mosquitto, using its
[Dynamic Security plugin](https://mosquitto.org/documentation/dynamic-security/)
for clients, roles and ACLs. The listener runs on port 11884, next to
TrailMQ, and without TLS to keep the setup short.

```bash
MP=$(mktemp -d)
cat > "$MP/mosquitto.conf" <<'EOF'
listener 1883
allow_anonymous false
plugin /usr/lib/mosquitto_dynamic_security.so
plugin_opt_config_file /mosquitto/config/dynamic-security.json
log_type all
EOF
docker run --rm -u "$(id -u):$(id -g)" -v "$MP:/mosquitto/config" \
  eclipse-mosquitto:2.1.2-alpine mosquitto_ctrl dynsec init \
  /mosquitto/config/dynamic-security.json dynadmin 'Dyn-Admin_42'
docker run -d --name proof-mosquitto -u "$(id -u):$(id -g)" -p 11884:1883 \
  -v "$MP:/mosquitto/config" eclipse-mosquitto:2.1.2-alpine \
  mosquitto -c /mosquitto/config/mosquitto.conf

ctrl() { docker exec proof-mosquitto mosquitto_ctrl \
  -u dynadmin -P 'Dyn-Admin_42' dynsec "$@" 2>/dev/null; }
ctrl createRole publisher
ctrl addRoleACL publisher publishClientSend 'public/#' allow
ctrl createRole operator
ctrl addRoleACL operator publishClientSend '#' allow
ctrl addRoleACL operator subscribePattern '#' allow
ctrl createClient testuser -p 'Proof-User_42'
ctrl addClientRole testuser publisher
ctrl createClient testadmin -p 'Proof-Admin_42'
ctrl addClientRole testadmin operator
```

Dynamic Security denies publishing and subscribing by default, so the sensor
role gets no subscribe rule at all. The role is called `operator` rather than
`admin` because `dynsec init` already creates an `admin` role that may manage
the plugin itself. Then run the same five actions:

```bash
BROKER=(-h localhost -p 11884)
SENSOR=(-u testuser  -P 'Proof-User_42')
OPS=(-u testadmin -P 'Proof-Admin_42')
proof
```

```text
1 sensor subscribes to public/#            (runs for 12 s)
2 sensor publishes public/demo/temperature
  exit=0
3 sensor publishes restricted/ops/config
  exit=0
4 ops console publishes restricted/ops/config
  exit=0
5 stranger connects and publishes
Connection error: Connection Refused: not authorised.
  exit=0
observer received:
  public/demo/temperature {"t":21.5}
  restricted/ops/config {"setpoint":40}
sensor subscription received:
  (nothing)
```

The broker log, with `log_type all` as configured above and timestamps
left out:

```bash
docker logs proof-mosquitto 2>&1 | grep -E 'Denied|denied|not authorised' | tail -3
```

```text
	public/# (denied)
Denied PUBLISH from proof-sensor (d0, q1, r0, m1, 'restricted/ops/config', ... (15 bytes))
Client proof-stranger [172.17.0.1:39386] disconnected: not authorised.
```

## Result

| # | Action | TrailMQ 3.1.1 | Mosquitto 2.1.2 with Dynamic Security |
| --- | --- | --- | --- |
| 1 | sensor subscribes to `public/#` | refused, nothing arrives | refused, nothing arrives |
| 2 | sensor publishes `public/demo/temperature` | allowed, observer receives it | allowed, observer receives it |
| 3 | sensor publishes `restricted/ops/config` | refused, client fails with a protocol error | refused, client exits 0 |
| 4 | ops console publishes `restricted/ops/config` | allowed, observer receives it | allowed, observer receives it |
| 5 | unknown identity connects | refused at connect | refused at connect |

Both brokers enforce the same policy with the same five outcomes. A
correctly configured Mosquitto refuses exactly what TrailMQ refuses. The
difference lies in what the client is told and in what is written down.

## Where the two runs differ

**What the client is told.** In MQTT 3.1.1 an acknowledgement cannot carry a
refusal. Mosquitto acknowledges the refused QoS 1 publish, so the client
exits 0 and looks successful. TrailMQ drops the connection instead, so the
client fails, but with a generic protocol error rather than a reason. With
MQTT 5 (`mosquitto_pub -V mqttv5`) both brokers return the refusal, and the
client prints `Warning: Publish 1 failed: Not authorized.` At QoS 0 the
client exits 0 on both brokers, because nothing is acknowledged at all.

**What is written down.** With `log_type all`, Mosquitto logged the refused
publish with client id and topic, the refused subscription filter, and the
refused connect. The username appears on the earlier connect line; the role
and the rule that refused are not in these lines. With Mosquitto's default
logging, the refused publish and subscription did not appear in this run;
connects and the refused connect did. TrailMQ records each refusal as a
decision with client id, identity, topic and a reason that names the check
that refused it: `acl_role_not_in_topic_scope` when no topic rule brings the
topic into scope for the role, `acl_role_action_not_permitted` when the role
may not perform the action. Those records are queryable over the REST API and
visible in Activity, without debug logging. The reason names the check, not
a single line of configuration.

This run used Mosquitto's built-in logging and nothing else. Other plugins
or log pipelines can record more, and this page makes no statement about
them.

**When Mosquitto is the simpler choice.** If you need enforcement and MQTT 5
reason codes for the client, and nobody has to explain a refusal later, a
secured Mosquitto does the job with less to run, and it is open source.
TrailMQ is worth evaluating when someone has to answer afterwards who was
refused, on which topic, and by which check.

## Limits of this proof

- One local run with one small policy. It is not a load, availability or
  security test of either broker.
- TrailMQ's MQTT decision records are outside its validated integrity chain:
  the built-in verdict does not cover them
  ([trust and evidence scope](../README.md#trust-and-evidence-scope)).
- An allowed publish shows acceptance at the broker. Delivery is shown here
  only by the observer subscription.
- TrailMQ ran with TLS, the Mosquitto listener without. The proof concerns
  authorization only.
- TrailMQ 3.1.1 is licensed for non-production evaluation only
  ([LICENSE](../LICENSE)).

## Clean up

```bash
rm -f observer.txt sensor-subscription.txt
docker rm -f proof-mosquitto
rm -rf "$MP"
```
