# Cinquain Deployment Kit

This directory contains the first curated deployment path for `cinquain`.

## Goal

Provide the smallest realistic production deployment for a Matrix homeserver:

- Continuwuity core
- embedded RocksDB storage
- Caddy-managed TLS
- `.well-known` over port 443
- one guided bootstrap flow for the first administrator

## Quick Start

```bash
./install.sh
```

## Required Operator Decisions

- `CINQUAIN_SERVER_NAME`
- `CINQUAIN_ACME_EMAIL`
- `CINQUAIN_SUPPORT_EMAIL`

## Constraints

- `CINQUAIN_SERVER_NAME` should be treated as permanent after first deploy.
- DNS for the Matrix domain must already point at the machine before first boot.
- This kit currently targets a single-node deployment.

## First-Run Flow

- `./install.sh` generates `CINQUAIN_BOOTSTRAP_SECRET` in `.env` if it is empty.
- Open `/bootstrap` after the stack is online.
- Use the bootstrap secret to create the first administrator account.

## Files

- `docker-compose.yml`: the packaged stack
- `Caddyfile`: TLS and reverse proxy
- `.env.example`: deployment inputs
- `continuwuity-resolv.conf`: recommended DNS resolvers for federation traffic
- `install.sh`: preflight and deployment entrypoint
- `doctor.sh`: post-install verification checks
- `site/`: branded landing and support pages served by Caddy
