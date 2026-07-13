# Cinquain changelog

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
