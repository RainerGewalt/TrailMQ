# Connect an MQTT client

TrailMQ *is* the broker — any standard MQTT client can connect. This page
explains the three things every client needs, how TrailMQ decides whether a
connect / publish / subscribe is allowed, and what a denied action looks like
from the client side.

All commands assume the default local evaluation stack
(`./trailmq quickstart`) and are run from the repository root.

## The three things every client needs

| # | What | Where it comes from (default recipe) |
| - | ---- | ------------------------------------ |
| 1 | **Endpoint + CA certificate** | `mqtts://localhost:8883`, CA file `recipes/secure-mqtt-core/certs/ca_cert.pem` (or `ws://localhost/mqtt` for WebSocket) |
| 2 | **Credentials** | A user from `config.yaml` → `users:` — passwords are generated into `recipes/secure-mqtt-core/secrets/*.pwd` (print them with `./trailmq credentials`) |
| 3 | **An allowed topic namespace** | See [How TrailMQ decides](#how-trailmq-decides-allow-or-deny) below — `public/#` works out of the box |

The evaluation users:

| User        | Role      | Can publish | Can subscribe |
| ----------- | --------- | ----------- | ------------- |
| `testadmin` | admin     | everywhere  | everywhere    |
| `testuser`  | publisher | yes         | **no** (publish-only role) |

## How TrailMQ decides: allow or deny

Every MQTT action passes **two independent checks**. Both must allow it:

1. **Role permission** — *what* the user's role may do. Configured in
   `config.yaml` → `roles:` as `"<action>:<topic-filter>"`, e.g.
   `"publish:*"` (publish anywhere), `"subscribe:factory/#"` (MQTT-style
   wildcards). A bare `"*"` grants everything (admin).
2. **Topic / namespace ACL** — *where* that role is welcome:

   | Namespace | Default access |
   | --------- | -------------- |
   | `public/#` | All authenticated roles |
   | `restricted/#` | Admin only |
   | everything else | **Deny by default** — until a topic in that namespace grants roles via its `accessControl: role` / `allowedRoles` settings (created in the Web UI or via `POST /api/v1/topics`) |

So: `testuser` (role `publisher`, permission `publish:*`) can publish to
`public/demo/temperature` immediately, but publishing to
`factory/line-1/temperature` is denied until an admin creates that topic with
`allowedRoles: [publisher]`. The [scenarios](scenarios/) walk through exactly
this.

> **Expect a handshake message.** Right after connecting, TrailMQ sends every
> client a policy handshake on `trailmq/handshake/<your-client-id>` containing
> the current policy snapshot hash and revision. It shows up in verbose
> subscriber output — it is broker metadata, not your data. Filter it out with
> `mosquitto_sub … -T 'trailmq/#'`.

## mosquitto_pub / mosquitto_sub (CLI)

Requires [`mosquitto-clients`](https://mosquitto.org/). Subscribe in one
terminal, publish in another:

```bash
CA=recipes/secure-mqtt-core/certs/ca_cert.pem
ADMIN_PW=$(cat recipes/secure-mqtt-core/secrets/testadmin.pwd)
USER_PW=$(cat recipes/secure-mqtt-core/secrets/testuser.pwd)

# Terminal 1 — subscribe as testadmin (admin may subscribe anywhere)
mosquitto_sub -h localhost -p 8883 --cafile "$CA" \
  -u testadmin -P "$ADMIN_PW" \
  -t 'public/#' -T 'trailmq/#' -v

# Terminal 2 — publish as testuser (role: publisher)
mosquitto_pub -h localhost -p 8883 --cafile "$CA" \
  -u testuser -P "$USER_PW" \
  -t 'public/demo/temperature' -q 1 \
  -m '{"value":21.4,"unit":"degC"}'
```

Terminal 1 prints:

```text
public/demo/temperature {"value":21.4,"unit":"degC"}
```

## Python (paho-mqtt ≥ 2.0)

```bash
pip install paho-mqtt
```

```python
import paho.mqtt.client as mqtt

client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="line-1-sensor")
client.username_pw_set("testuser", "<password from ./trailmq credentials>")
client.tls_set(ca_certs="recipes/secure-mqtt-core/certs/ca_cert.pem")
client.connect("localhost", 8883)
client.loop_start()

info = client.publish("public/demo/temperature",
                      '{"value": 21.4, "unit": "degC"}', qos=1)
info.wait_for_publish(timeout=5)

client.loop_stop()
client.disconnect()
```

## Node.js (mqtt.js)

```bash
npm install mqtt
```

```js
const fs = require("node:fs");
const mqtt = require("mqtt");

const client = mqtt.connect("mqtts://localhost:8883", {
  ca: fs.readFileSync("recipes/secure-mqtt-core/certs/ca_cert.pem"),
  username: "testuser",
  password: "<password from ./trailmq credentials>",
  clientId: "line-1-sensor-node",
});

client.on("connect", () => {
  client.publish(
    "public/demo/temperature",
    JSON.stringify({ value: 21.4, unit: "degC" }),
    { qos: 1 },
    () => client.end(),
  );
});
```

## Browser (MQTT over WebSocket)

The stack exposes MQTT over WebSocket at `ws://localhost/mqtt`. Browser
connections are additionally checked against the allow-list in
`config.yaml` → `mqtt_ws_allowed_origins` — add your page's origin there if
you serve it from anywhere other than `http://localhost`.

```html
<script src="https://unpkg.com/mqtt/dist/mqtt.min.js"></script>
<script>
  const client = mqtt.connect("ws://localhost/mqtt", {
    username: "testadmin",
    password: "<password from ./trailmq credentials>",
  });
  client.on("connect", () => client.subscribe("public/#"));
  client.on("message", (topic, payload) =>
    console.log(topic, payload.toString()));
</script>
```

## What a denied action looks like

TrailMQ fails closed, and the client-side symptom depends on where the check
fails:

| You did | Symptom on the client | What actually happened |
| ------- | --------------------- | ---------------------- |
| Wrong username/password | `Connection Refused: not authorised.` | Authentication rejected at CONNECT |
| Publish (QoS 1) to a namespace your role may not reach | `Error: A network protocol error occurred…` — the broker drops the connection | ACL denied the publish; at QoS 1 the broker disconnects instead of acknowledging |
| Publish (QoS 0) to a denied namespace | Nothing — the publish "succeeds" locally | QoS 0 has no acknowledgement; the broker silently discards the message |
| Subscribe without a `subscribe:` permission | Connection stays up, no messages ever arrive | The subscription was denied; nothing is delivered |
| Connect with the wrong CA file | TLS error before MQTT even starts | Certificate verification failed |

**Important:** a locally "successful" QoS 0 publish is *not* proof of
delivery. If in doubt, check what TrailMQ recorded:

```bash
# Denials in the broker log
./trailmq logs backend | grep ACLMon

# Recorded events / evidence (see the Web UI → Evidence as well)
```

Every connect, authentication decision and denial is also visible in the Web
UI: open **Evidence** and filter by outcome (e.g. **Blocked**) — each entry
is labeled with how it was captured.

## Configuration map — what must match what

| Client side | Must match (server side) |
| ----------- | ------------------------ |
| CA file passed to the client | `recipes/secure-mqtt-core/certs/ca_cert.pem` (same CA that signed the server cert) |
| Username / password | `config.yaml` → `users:` entry + its `password_file` under `secrets/` |
| Topic you publish/subscribe to | Namespace defaults or a topic's `allowedRoles` (plus your role's `permissions`) |
| QoS you request | Topic's `qosLevel` (see `GET /api/v1/topics/by-name/<path>/effective`) |
| Browser origin (WebSocket only) | `config.yaml` → `mqtt_ws_allowed_origins` |
| REST/API origin (browser apps) | `config.yaml` → `cors.allowed_origins` |

## Next steps

- Run the proof: `./trailmq verify`
- Walk through the [scenarios](scenarios/) — allowed flow, denied actions,
  and creating a governed namespace
- Explore the REST API: [Secure MQTT Core walkthrough](../recipes/secure-mqtt-core/README.md)
