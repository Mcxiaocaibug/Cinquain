# Cinquain Tasks

Canonical execution log for turning this codebase into `cinquain`: a polished,
easy-to-deploy Matrix server built on top of Continuwuity.

## North Star

- Deliver a production-ready Matrix homeserver that can be deployed with
  `docker compose up -d`.
- Hide database and reverse-proxy complexity behind a curated default stack.
- Provide a beautiful operator-facing web experience before, during, and after
  deployment.
- Keep the protocol core close to upstream Continuwuity while productizing the
  deployment and onboarding layers around it.

## Product Shape

- Core: Continuwuity homeserver and Matrix protocol implementation.
- Packaging: a curated Docker Compose stack with Caddy, TLS, `.well-known`,
  persistent storage, and sane defaults.
- Bootstrap: first admin creation, support metadata, and first-run guidance.
- Web UI: product landing page, deployment guide, operator quickstart,
  post-install status page, and later an install wizard.

## Delivery Principles

- Prefer opinionated defaults over option sprawl.
- Optimize for the first successful deploy on a fresh VPS.
- Keep every step reversible, inspectable, and documented.
- Treat `server_name` and federation constraints as product requirements, not
  user homework.

## Milestones

### Phase 1: Foundation

- [x] Write and save the Cinquain roadmap and execution task list.
- [x] Create the first curated one-command deployment kit.
- [x] Add operator-facing install and verification scripts.
- [x] Add a branded runtime landing page and support page in the packaged stack.
- [x] Rework the built-in homeserver landing page into a Cinquain onboarding page.

### Phase 2: Deployment Product

- [x] Make the Compose stack fully branded and self-documenting.
- [x] Add bootstrap health checks and post-install verification commands.
- [x] Replace manual first-user token flow with a safer operator bootstrap flow.
- [x] Add upgrade and backup procedures for the packaged deployment.

### Phase 3: Operator Web UI

- [ ] Ship a polished quickstart flow in docs with architecture, prerequisites,
      and failure recovery.
- [x] Add a dedicated support page surfaced through `/.well-known/matrix/support`.
- [x] Add a post-install checklist page for federation, client login, and admin access.
- [ ] Add a visual deployment comparison page for single-domain and split-domain setups.

### Phase 4: Product Hardening

- [ ] Test the deployment kit against fresh machines and different DNS layouts.
- [ ] Add automated docs/build validation for Cinquain assets.
- [x] Automate multi-arch Docker image publishing for packaged deployments.
- [ ] Add versioned release notes and upgrade notes for packaged deployments.
- [x] Define branding, release naming, and image publishing entrypoint.

## Current Execution Order

1. Establish the roadmap and product surface.
2. Ship the first curated deployment kit in-repo.
3. Tighten bootstrap UX and packaged health verification.
4. Rework built-in pages and operator-facing runtime UX.
5. Harden, validate, and automate.

## Notes

- The current deployment kit intentionally targets the simplest viable
  production path: single domain, ports 80/443, Caddy-managed TLS, and embedded
  RocksDB storage.
- `server_name` remains a one-time decision due to Matrix identity rules and
  storage layout constraints.
