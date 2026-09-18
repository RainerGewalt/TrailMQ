# Security Policy

TrailMQ controls MQTT access and keeps relevant access decisions reviewable, so
security reports are handled privately first.

## Reporting a vulnerability

Please do not open a public GitHub issue for suspected vulnerabilities.

Report security issues to **contact@trailmq.com**, or through the contact
channel listed at [trailmq.com](https://trailmq.com).

That is the same address the README and the LICENSE give for commercial
contact. There is one channel, not several.

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

## Supported versions

TrailMQ is distributed as an evaluation preview. Only the most recently
published minor line receives security fixes.

| Version | Security fixes |
| --- | --- |
| latest published `3.1.x` | yes |
| any earlier `3.1.x` patch | no — upgrade to the latest patch |
| `3.0.x` and earlier | no |

Older images stay available so an evaluation in progress does not break. That is
availability, not support: an unfixed vulnerability in an older tag is not
patched in place, and the fix ships in the next patch release.

## What to expect after you report

There is one maintainer, and this is an evaluation preview. So the honest
answer, rather than a service level nobody is contracted to meet:

- Reports are read. There is no guaranteed response time, and none is implied
  by this document.
- A report that includes a reproduction is acted on before one that does not.
- If a report is a duplicate, out of scope, or not reproducible, you are told
  that rather than left waiting.
- Fixes ship in the next patch release. There is no separate advisory feed and
  no backport to older tags.

If you need a contractual response commitment, that belongs to a commercial
agreement and not to this evaluation license. Contact **contact@trailmq.com**.

## Local evaluation reminders

The generated certificates and users are for local evaluation only. Rotate or
replace them before any non-local deployment, and review the license before any
production or commercial use.
