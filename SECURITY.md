# Security Policy

TrailMQ is an audit-first control plane for MQTT, so security reports are
handled privately first.

## Reporting a vulnerability

Please do not open a public GitHub issue for suspected vulnerabilities.

Report security issues through the contact channel listed at:

```text
https://trailmq.com
```

Include as much detail as you can safely share:

- affected TrailMQ image tag or repository commit
- operating system and Docker version
- exact recipe and configuration changes
- reproduction steps
- expected impact
- logs or API responses with secrets removed

## Supported scope

Security reports are most useful when they affect:

- the public Docker evaluation distribution
- launcher scripts
- recipe configuration
- generated certificate or secret handling
- authentication or authorization behavior
- audit-chain integrity or evidence export behavior
- reverse proxy routing

Do not include real production credentials, private keys, JWT secrets, customer
data, or regulated data in a report.

## Local evaluation reminders

The generated certificates and users are for local evaluation only. Rotate or
replace them before any non-local deployment, and review the license before any
production or commercial use.
