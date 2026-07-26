# Cinquain changelog

## 0.0.2 — 2026-07-26

- Rebased on upstream Continuwuity `main` at version `26.6.2` (60 upstream
  commits; the protocol core remains unmodified).
- Fixed `cinquain token` never returning the first-admin token. Continuwuity
  colourises its first-run banner unconditionally — yansi is built without
  `detect-tty`, so `Condition::os_support()` is always true and ANSI escapes reach
  the container log even with no TTY — and the extractor required an alphanumeric
  character immediately after `registration token `. Escapes are now stripped
  first, and the pattern is anchored on the full banner phrase so the unrelated
  `registration token configured.` and `registration token issued:` log lines can
  no longer be mistaken for a token.
- `bootstrap.sh` now performs a complete unattended deployment when given a domain
  and operator email, instead of only installing the panel and requiring a browser.
- `bootstrap.sh` now prefers the published release bundle and verifies it against
  its `.sha256` sidecar automatically; `CINQUAIN_SHA256` can pin a digest
  explicitly. Copies are staged through a file because POSIX `sh` has no
  `pipefail`, so a failing `tar | tar` producer used to go unnoticed.
- Added pre-deployment checks for DNS resolution and for foreign listeners on
  port 80/443, the two failures behind most broken first deployments. ACME can
  never succeed for a name that does not resolve, so this now fails fast with a
  specific reason rather than after the stack is already running.
- `doctor.sh` no longer reports a false failure on hosts that cannot reach their
  own public address (no NAT hairpin): checks fall back to the local Caddy with
  the real SNI, and say when external reachability was left unverified. Non-443
  `CINQUAIN_HTTPS_PORT` values are now included in the probed URL.
- `deploy` tolerates a failed image pull when the exact images are already in the
  local store, and prints the first-admin token directly instead of deferring to
  a second command.
- Fixed a backup/restore data-loss path: an interrupted backup left a truncated
  archive under the final name with no checksum sidecar, and `restore.sh` treated
  a missing sidecar as "skip verification" and wiped the live volumes with partial
  data. Archives are now built under `.partial`, verified readable, and promoted
  only after their sidecar exists; restore requires the sidecar unless
  `CINQUAIN_SKIP_CHECKSUM=1`.
- Made the upgrade rollback idempotent. It is reachable from both the signal trap
  and the failure branch, and the second `mv` aborted the handler under `set -e`
  before the stack was brought back up. Stale rollback snapshots are also swept.
- Fixed panel request logging corrupting every message: redacting the whole path
  turned each separator in the request line into a redaction when the path was
  `/`. Only the query string is redacted now.
- Fixed the panel validating an upgrade image against the config module's `.env`
  instead of the deployment's own (`CINQUAIN_ROOT`).
- CI derives the product version instead of hardcoding `0.0.1`, asserts every copy
  of the version agrees, boots the built image and asserts the first-run banner is
  still parseable, so an upstream rewording breaks the build instead of shipping a
  broken onboarding step.
- `preflight.sh` announces skipped checks instead of omitting them silently.

## 0.0.1 — 2026-07-12

Initial production release.

- Rebased the product on Continuwuity 26.6.0 and latest upstream `main` commit
  `4001b99261a81ad41adcb691b3e89b3a2eb9639c`.
- Replaced all prior Cinquain deployment content with a core-independent,
  versioned deployment layer.
- Added fresh-server dependency bootstrap for Debian/Ubuntu and Fedora/RHEL.
- Added a protected, responsive Chinese web panel with validated deployment,
  live operation output, container state, backups, upgrades and first-admin
  onboarding.
- Added Caddy-managed TLS, discovery endpoints, private service networking,
  persistent volumes, log rotation and strict response headers.
- Added atomic private configuration, immutable Matrix-domain protection,
  consistent checksummed backup/restore and health-gated rollback upgrades.
- Added local release preflight, Python API/config tests, CLI smoke tests,
  browser-panel tests, GitHub CI, multi-architecture signed container publishing,
  SBOM/provenance generation and automated release bundles.
- Isolated and locked Cargo caches per target platform, enabled resilient Git
  submodule fetching, and reused CI architecture caches during release builds.
