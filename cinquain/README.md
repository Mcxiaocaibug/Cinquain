# Cinquain 0.0.1

Cinquain turns a fresh Linux VPS into a production-oriented Matrix homeserver.
It is a deployment and operations layer around an unmodified Continuwuity core,
so upstream updates remain reviewable and future syncs do not require rebasing a
private fork of the protocol implementation.

This release is based on Continuwuity `26.6.0` plus upstream `main` through
commit `4001b99261a81ad41adcb691b3e89b3a2eb9639c` (2026-07-11).

## Documentation index

- [中文小白部署指南](docs/GUIDE.zh-CN.md)
- [English beginner's deployment guide](docs/GUIDE.en.md)
- This page: complete deployment, architecture, operations and recovery reference

## What is automated

- Docker Engine and Compose v2 installation on supported Linux distributions
- token-protected web deployment panel, bound to `127.0.0.1` by default
- validated, atomic `.env` and `continuwuity.toml` generation
- immutable Matrix `server_name` guard
- versioned Cinquain/Continuwuity and Caddy images
- automatic TLS certificate issuance and renewal with Caddy
- Matrix client, federation and support discovery on port 443
- private backend network, container restart policy and bounded JSON logs
- upstream first-run Web registration using a single-use admin token
- consistent RocksDB backups with SHA-256 sidecars and retention
- restore, backup-before-upgrade, health-gated upgrade and automatic rollback
- client, federation, discovery, landing-page and container health diagnostics

## Requirements

- A fresh Debian/Ubuntu or Fedora/RHEL-family server with `systemd`
- root or passwordless `sudo` access
- a DNS A/AAAA record for the chosen Matrix domain pointing to the server
- inbound TCP ports 80 and 443
- at least 2 GB RAM and 10 GB free disk for a small personal server

The Matrix domain becomes part of every user ID and room ID. It cannot be
changed later without starting with a new database.

## Recommended: fresh-server web deployment

Run this once over SSH:

```bash
curl -fsSL https://raw.githubusercontent.com/Mcxiaocaibug/Cinquain/cinquain-v0.0.1/cinquain/bootstrap.sh | sudo sh
```

The script prints a command similar to:

```bash
ssh -N -L 7080:127.0.0.1:7080 root@203.0.113.10
```

Keep that tunnel open, then open the printed URL on your computer. The token is
placed in the URL fragment (not the query string), moved into tab-scoped session
storage, and removed from the address bar. It is required by every panel API
request.

Fill in the Matrix domain and operator email, confirm DNS, then select
**验证并自动部署**. The panel streams the deployment status. When the services
are healthy, copy the single-use registration token and open the supplied
Continuwuity registration page. The first registered account becomes the server
administrator and receives an invitation to the admin room.

Panel service controls:

```bash
sudo systemctl status cinquain-panel
sudo systemctl restart cinquain-panel
sudo systemctl disable --now cinquain-panel  # optional after deployment
```

The panel credential is stored at `/etc/cinquain/panel.env` with mode `0600`.
The service runs as root only because Docker's control socket is root-equivalent;
the unit applies systemd filesystem, device, kernel, memory and network-family
restrictions around that unavoidable capability.

## Existing-host CLI deployment

With Docker Compose v2, Python 3 and curl already installed:

```bash
cd cinquain
./install.sh matrix.example.com admin@example.com
```

To use a mirrored or digest-pinned image:

```bash
./cinquain deploy matrix.example.com admin@example.com \
  ghcr.io/mcxiaocaibug/cinquain@sha256:<digest>
```

The command is idempotent. Running `./cinquain deploy` later applies the current
validated configuration. Cinquain refuses to overwrite a deployed server with a
different Matrix domain.

## Architecture

```text
Internet :80/:443
       │
       ▼
  Caddy edge ───── static Cinquain landing/support pages
       │
       ├──── /_matrix/* and /.well-known/matrix/*
       ▼
 Continuwuity :8008 (private Docker network)
       │
       ▼
 persistent RocksDB/media volume

Operator ── SSH tunnel ── 127.0.0.1:7080 deployment panel ── Docker socket
```

Only Caddy publishes host ports. Continuwuity is not directly exposed. The panel
is not routed through the public Caddy site and defaults to loopback.

## Operations

Run commands from `/opt/cinquain` for a bootstrap installation, or from the
repository's `cinquain/` directory for a checkout installation.

```bash
./cinquain status
./cinquain doctor
./cinquain logs
./cinquain logs homeserver
./cinquain token
./cinquain backup
./cinquain restore backups/cinquain-v0.0.1-YYYYMMDDTHHMMSSZ.tar.gz
./cinquain upgrade ghcr.io/mcxiaocaibug/cinquain:0.0.2
```

Backups briefly stop only the homeserver container so RocksDB and media are
captured consistently; Caddy remains online. Archives contain the homeserver
volume, Caddy certificate state, deployment configuration and a SHA-256 sidecar.
Treat them as secrets. Restore verifies the sidecar and rejects traversal paths.

Upgrade creates a backup first, pulls the requested image, recreates the stack,
and waits for all public health checks. If any step fails, it restores the prior
image configuration and restarts the old stack.

## Configuration

The panel and CLI write these private files:

- `.env`: Compose deployment values and image versions
- `continuwuity.toml`: minimal homeserver configuration
- `state/`: temporary rollback state
- `backups/`: local backup archives

All are ignored by Git. `.env` and `continuwuity.toml` are atomically written
with mode `0600`. Advanced Continuwuity options may be added to the generated
TOML after deployment; preserve `server_name`, `database_path`, bind address and
well-known values unless you deliberately redesign the topology.

## Release validation

```bash
./preflight.sh
```

The release gate checks every required artifact, shell and Python syntax,
configuration validation, domain immutability, authenticated panel behavior,
browser UI helpers, installer behavior, Compose rendering, security invariants,
ShellCheck when installed, and Git whitespace. GitHub CI additionally validates
the Compose/Caddy models and builds the exact multi-architecture release image.

## Scope and limitations

- `0.0.1` targets a single server and a single Matrix domain.
- SMTP, OIDC, bridges, MatrixRTC/LiveKit and TURN depend on operator-specific
  providers and credentials, so they are not silently enabled with insecure
  defaults. Add them using the upstream Continuwuity guides after base deployment.
- Local backups are not an off-site disaster-recovery strategy. Copy encrypted
  archives to independent storage.
- The public image is built from this repository at release time. Inspect GitHub
  Actions provenance and prefer a digest in high-assurance environments.

## License and upstream

Continuwuity remains under its upstream Apache-2.0 license and attribution.
Cinquain intentionally carries no protocol-core modifications; security and
compatibility issues in the homeserver should also be checked against the
[Continuwuity project](https://continuwuity.org/).
