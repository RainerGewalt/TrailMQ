# Windows distribution

What a Windows evaluator downloads instead of installing Git, WSL and a shell:

| Artifact | What it is |
| --- | --- |
| `TrailMQ-<version>-windows-x64.zip` | Portable copy. Extract and run `trailmq.exe`. |
| `TrailMQ-Setup-<version>.exe` | Inno Setup installer, built from [`trailmq.iss`](trailmq.iss). Start Menu entries for start, demo, open and stop. |
| `SHA256SUMS-windows` | Checksums for both. |

`trailmq.exe` is a launcher, not a second runtime. It drives the same signed
container stack, so there is exactly one deployment path to test, harden and
support. [`verify-artifacts.ps1`](verify-artifacts.ps1) checks what a
downloader receives rather than the source it came from: a fresh install, the
packaged scenario pack, and `doctor` answering honestly on a machine with no
Docker.

Both are built and verified by
[Launcher release](../../.github/workflows/launcher-release.yml).

## Publisher identity

The artifacts are **not Authenticode-signed yet**. An unsigned installer shows
SmartScreen's "unknown publisher" on the path that is meant to be the easiest
one, and it starts from zero reputation at every version, because SmartScreen
weighs a consistent publisher identity. Signing does not guarantee a
warning-free first run — file reputation is counted separately — but it removes
the worst state and lets reputation accumulate.

`verify-artifacts.ps1` already reports the signature of the packaged launcher,
the installer and the installed launcher on every run. `-RequireSignature`
turns that report into a gate, and the release workflow passes it by itself as
soon as `release.yaml` names a `distribution.windows_installer`. So the switch
is the release contract, not a flag somebody has to remember.

To enable signing, add a step between *Build the installer* and *Verify the
built artifacts* that signs both PE files — `trailmq.exe` inside the payload
(before the installer is built, so the installed copy is signed too) and
`TrailMQ-Setup-<version>.exe`. Azure Artifact Signing is the intended route:
no hardware token, and it authenticates from Actions through a federated
credential rather than a stored secret, which is why `id-token: write` will
have to join the job's permissions.

Then set `distribution.launcher` and `distribution.windows_installer` in
[`release.yaml`](../../release.yaml). The gate turns itself on, and the first
release naming a Windows installer cannot ship one without a publisher.
