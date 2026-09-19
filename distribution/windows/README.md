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

The artifacts are **not Authenticode-signed, deliberately.** Signing is
deferred until a Windows channel is distributed for production use; funding a
signing service for an evaluation launcher that is not published yet would buy
nothing. `START-HERE.md` in the payload says so plainly and points at
`SHA256SUMS-windows`, which is the verification that does exist today.

What the deferral costs: an unsigned installer shows SmartScreen's "unknown
publisher" on the path meant to be the easiest one, and it starts from zero
reputation at every version, because SmartScreen weighs a consistent publisher
identity. Signing would not guarantee a warning-free first run either — file
reputation is counted separately — but it removes the worst state and lets
reputation accumulate. That trade is the reason this is a decision rather than
an oversight.

A self-signed certificate is the free route for local testing. It produces a
valid signature and no public trust whatsoever, so it is useful for exercising
the signing path and useless for distribution.

### What is already in place

`verify-artifacts.ps1` reports the Authenticode status of the packaged
launcher, the installer and the installed launcher on every run — so an
unsigned build is visible in the log rather than silently normal.
`-RequireSignature` turns that report into a gate, and
[Launcher release](../../.github/workflows/launcher-release.yml) passes the
switch by itself as soon as `release.yaml` names a
`distribution.windows_installer`. The release contract is the switch; nobody
has to remember a flag.

### When it is funded

Add a step between *Build the installer* and *Verify the built artifacts* that
signs both PE files — `trailmq.exe` inside the payload before the installer is
built, so the installed copy is signed too, and then
`TrailMQ-Setup-<version>.exe`. Azure Artifact Signing is the intended route:
no hardware token, and it authenticates from Actions through a federated
credential rather than a stored secret, which is why `id-token: write` will
have to join the job's permissions. It requires a paid Azure subscription.

Then set `distribution.launcher` and `distribution.windows_installer` in
[`release.yaml`](../../release.yaml). The gate turns itself on, and the first
release naming a Windows installer cannot ship one without a publisher. Until
then both stay `null`, and the Windows artifacts are built, verified and
evaluated unsigned.
