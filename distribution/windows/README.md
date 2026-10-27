# Windows distribution

What a Windows evaluator runs instead of installing Git, WSL and a shell.
These are **build artifacts produced and verified in CI**, and attached to every
release whose [`release.yaml`](../../release.yaml) names a
`distribution.windows_installer`.

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
deferred until a Windows channel is distributed for production use, and the
release contract says so in its own field:
`distribution.windows_trust_mode: unsigned_evaluation`. `START-HERE.md` in the
payload says so plainly, and points at
`SHA256SUMS-windows` while keeping the two claims apart: a digest shows the
file is the artifact this release published, a signature would show who
published it. Only the first is available today, and it is not a substitute
for the second — if a release and its checksum file were compromised together,
the comparison still matches.

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

`verify-artifacts.ps1` checks the Authenticode status of the packaged
launcher, the installer and the installed launcher on every run.
[Launcher release](../../.github/workflows/launcher-release.yml) reads
`distribution.windows_trust_mode` from `release.yaml` and passes it as
`-TrustMode`, which turns the report into a gate:

| Trust mode | What the verification demands |
| --- | --- |
| `unsigned_evaluation` | Every artifact is unsigned. A signed one fails too: it would be published under a promise of no publisher. |
| `authenticode` | Every artifact carries a valid signature. |

The distribution gate adds the payload side: under `unsigned_evaluation`,
`START-HERE.md` has to carry the unknown-publisher warning and keep the
checksum from standing in for a signature. The release contract is the switch;
nobody has to remember a flag.

### When it is funded

Add a step between *Build the installer* and *Verify the built artifacts* that
signs both PE files — `trailmq.exe` inside the payload before the installer is
built, so the installed copy is signed too, and then
`TrailMQ-Setup-<version>.exe`. Azure Artifact Signing is the intended route:
no hardware token, and it authenticates from Actions through a federated
credential rather than a stored secret, which is why `id-token: write` will
have to join the job's permissions. It requires a paid Azure subscription.

Then set `distribution.windows_trust_mode` to `authenticode` in
[`release.yaml`](../../release.yaml). The verification turns itself around, and
from that release on a Windows installer cannot ship without a publisher.
