<div align="center">

<h1 align="center">
  Sentinel Control Plane
</h1>

<p align="center">
  <em>Fleet management for Sentinel reverse proxies.</em><br>
  <em>Declarative configuration distribution with safe rollouts.</em>
</p>

<p align="center">
  <a href="https://elixir-lang.org/">
    <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.17+-4B275F?logo=elixir&logoColor=white&style=for-the-badge">
  </a>
  <a href="https://www.phoenixframework.org/">
    <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.8-f5a97f?style=for-the-badge">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-Apache--2.0-c6a0f6?style=for-the-badge">
  </a>
</p>

<p align="center">
  <a href="https://github.com/raskell-io/sentinel">Sentinel Proxy</a> •
  <a href="https://sentinel.raskell.io/docs/">Documentation</a> •
  <a href="https://github.com/raskell-io/sentinel/discussions">Discussions</a>
</p>

</div>

---

Sentinel Control Plane is a fleet management system for [Sentinel](https://github.com/raskell-io/sentinel) reverse proxies. It handles configuration distribution, rolling deployments, and real-time node monitoring — built with Elixir/Phoenix and LiveView.

<p align="center">
  <img src="priv/static/images/dashboard-screenshot.png" alt="Sentinel Control Plane Dashboard" width="800">
</p>

## Status

**Beta.** The core workflow (compile config → create bundle → roll out to nodes) works end-to-end. Multi-tenant support, audit logging, drift detection, approval workflows, and the full LiveView UI are implemented. Actively being hardened for production use.

## How It Works

```
KDL Config → Compile & Sign → Immutable Bundle → Rollout → Nodes Pull & Activate
```

1. **Upload** a KDL configuration (validated via `sentinel validate`)
2. **Compile** into an immutable, signed bundle (tar.zst with manifest, checksums, SBOM)
3. **Create a rollout** targeting nodes by label selectors
4. **Orchestrate** batched deployment with health gates, pause/resume/rollback
5. **Nodes pull** the bundle, verify the signature, stage, and activate

Every mutation is audit-logged with actor, action, and diff.

## Features

| Feature | Description |
|---------|-------------|
| **Bundle Management** | Immutable, content-addressed config artifacts with deterministic SHA256 hashing |
| **Bundle Signing** | Ed25519 signatures with cryptographic verification on every node |
| **SBOM Generation** | CycloneDX 1.5 for every bundle — supply chain visibility out of the box |
| **Rolling Deployments** | Batched rollouts with configurable batch size, health gates, and progress deadlines |
| **Scheduled Rollouts** | Schedule deployments for future execution with calendar view |
| **Approval Workflows** | Require approval before rollouts execute with audit trail |
| **Rollout Templates** | Reusable rollout configurations for consistent deployments |
| **Drift Detection** | Automatic detection when node config diverges from expected state |
| **Node Management** | Registration, heartbeat tracking, label-based targeting, stale detection |
| **Node Groups** | Organize nodes with label-based groups for targeted operations |
| **Environments** | Promotion pipeline (dev → staging → prod) with bundle tracking |
| **Multi-Tenant** | Organizations, projects, and scoped API keys with RBAC |
| **GitOps** | GitHub webhook integration — auto-compile bundles on push |
| **Audit Logging** | Every mutation logged with who, what, when, and resource diff |
| **Observability** | Prometheus metrics, structured JSON logging, health endpoints |
| **LiveView UI** | K8s-style sidebar layout with real-time updates across all views |
| **Node Simulator** | Built-in fleet simulator for testing rollout logic without real nodes |

## UI Overview

The control plane provides a comprehensive LiveView UI with real-time updates:

| Page | Path | Description |
|------|------|-------------|
| **Dashboard** | `/orgs/:org/dashboard` | Fleet overview with node status, active rollouts, and drift alerts |
| **Nodes** | `.../nodes` | Node list with status, labels, bundle versions, and health |
| **Bundles** | `.../bundles` | Bundle management with diff viewer, SBOM inspector, and promotion pipeline |
| **Rollouts** | `.../rollouts` | Rollout list with progress tracking, controls, and node-level status |
| **Drift** | `.../drift` | Drift events with filtering and manual resolution |
| **Node Groups** | `.../node-groups` | Label-based node organization |
| **Environments** | `.../environments` | Promotion pipeline configuration |
| **Health Checks** | `.../health-checks` | Custom health check definitions |
| **Webhooks** | `.../webhooks` | GitHub integration configuration |
| **Schedule** | `/schedule` | Calendar view of scheduled rollouts |
| **Approvals** | `/approvals` | Pending rollout approval queue |
| **API Keys** | `/api-keys` | Scoped API key management |
| **Audit Log** | `/audit` | Searchable audit trail with export |
| **Profile** | `/profile` | User settings and password management |

## Quick Start

### Prerequisites

- [mise](https://mise.jdx.dev/) (manages Elixir 1.15+ / OTP 26+ and task runner)
- PostgreSQL (production) or SQLite (development)
- A [Sentinel](https://github.com/raskell-io/sentinel) binary (for config validation)

### Development

```bash
# Clone and setup
git clone https://github.com/raskell-io/sentinel-control-plane.git
cd sentinel-control-plane
mise install
mise run setup

# Start the development server
mise run dev
```

Visit [localhost:4000](http://localhost:4000). Default login: `admin@localhost` / `changeme123456`.

### Development Commands

```bash
mise run dev              # Start interactive dev server (iex -S mix phx.server)
mise run test             # Run test suite
mise run test:coverage    # Run tests with coverage report
mise run check            # Run format check, credo, and tests
mise run lint             # Run Credo static analysis
mise run format           # Format all Elixir files
mise run db:reset         # Drop, create, and migrate database
mise run db:migrate       # Run pending migrations
mise run routes           # List all routes
```

### Local Dev Stack (Docker Compose)

Starts PostgreSQL, MinIO (S3), and the control plane together:

```bash
docker compose -f docker-compose.dev.yml up
```

### Production Docker

```bash
docker build -t sentinel-cp .
docker run -p 4000:4000 \
  -e DATABASE_URL="postgres://user:pass@host/sentinel_cp" \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  sentinel-cp
```

## API

### Node API

Nodes authenticate with registration keys or JWT tokens.

```
POST /api/v1/projects/:slug/nodes/register   # Register a node
POST /api/v1/nodes/:id/heartbeat             # Send heartbeat
GET  /api/v1/nodes/:id/bundles/latest        # Fetch latest bundle
POST /api/v1/nodes/:id/token                 # Refresh JWT token
```

### Control Plane API

Authenticated via scoped API keys (`nodes:read`, `bundles:write`, `rollouts:write`, etc).

```
# Bundles
GET/POST       /api/v1/projects/:slug/bundles              # List / create bundles
GET            /api/v1/projects/:slug/bundles/:id/download # Download bundle artifact
GET            /api/v1/projects/:slug/bundles/:id/sbom     # Download SBOM (CycloneDX)
POST           /api/v1/projects/:slug/bundles/:id/revoke   # Revoke a compromised bundle

# Rollouts
GET/POST       /api/v1/projects/:slug/rollouts             # List / create rollouts
POST           /api/v1/projects/:slug/rollouts/:id/pause   # Pause rollout
POST           /api/v1/projects/:slug/rollouts/:id/resume  # Resume rollout
POST           /api/v1/projects/:slug/rollouts/:id/rollback # Rollback to previous bundle

# Nodes
GET            /api/v1/projects/:slug/nodes                # List nodes
GET            /api/v1/projects/:slug/nodes/stats          # Fleet statistics

# Drift Detection
GET            /api/v1/projects/:slug/drift                # List drift events
GET            /api/v1/projects/:slug/drift/stats          # Drift statistics
POST           /api/v1/projects/:slug/drift/:id/resolve    # Resolve drift event

# API Key Management (requires api_keys:admin scope)
GET/POST       /api/v1/api-keys                            # List / create API keys
POST           /api/v1/api-keys/:id/revoke                 # Revoke an API key
```

### Webhooks

```
POST /api/v1/webhooks/github    # Auto-compile on push (signature verified)
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Control Plane (Phoenix)            │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ LiveView │  │ REST API │  │ GitHub Webhook│  │
│  │    UI    │  │          │  │               │  │
│  └────┬─────┘  └─────┬────┘  └────────┬──────┘  │
│       │              │                │         │
│  ┌────┴──────────────┴────────────────┴───────┐ │
│  │           Contexts (Business Logic)        │ │
│  │  Bundles · Nodes · Rollouts · Audit · Auth │ │
│  └────┬──────────────┬────────────────────────┘ │
│       │              │                          │
│  ┌────┴─────┐  ┌─────┴──────┐                   │
│  │ Postgres │  │  S3/MinIO  │                   │
│  │  (state) │  │ (bundles)  │                   │
│  └──────────┘  └────────────┘                   │
└─────────────────────────────────────────────────┘
         │                          ▲
         │  Rollout assigns bundle  │  Heartbeat + status
         ▼                          │
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│  Sentinel   │  │  Sentinel   │  │  Sentinel   │
│   Node A    │  │   Node B    │  │   Node C    │
└─────────────┘  └─────────────┘  └─────────────┘
```

## Tech Stack

- **Elixir / Phoenix 1.8** — Web framework with LiveView for real-time UI
- **Oban** — Reliable background jobs for bundle compilation and rollout orchestration
- **PostgreSQL** — Persistent state (SQLite for development)
- **S3 / MinIO** — Bundle artifact storage
- **Ed25519** — Bundle signing via JOSE
- **PromEx** — Prometheus metrics integration

## Related

- [**Sentinel**](https://github.com/raskell-io/sentinel) — The reverse proxy this control plane manages
- [**sentinel.raskell.io**](https://sentinel.raskell.io) — Documentation and marketing site

## License

Apache 2.0 — See [LICENSE](LICENSE).
