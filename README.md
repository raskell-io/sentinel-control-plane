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
    <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.15+-4B275F?logo=elixir&logoColor=white&style=for-the-badge">
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

## Status

Early development. The core workflow (compile config, create bundle, roll out to nodes) works end-to-end. Multi-tenant support, audit logging, and the LiveView UI are functional. Not yet production-hardened.

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
| **Rollout Controls** | Pause, resume, cancel, and rollback with full state tracking |
| **Node Management** | Registration, heartbeat tracking, label-based targeting, stale detection |
| **Multi-Tenant** | Organizations, projects, and scoped API keys with RBAC |
| **GitOps** | GitHub webhook integration — auto-compile bundles on push |
| **Audit Logging** | Every mutation logged with who, what, when, and resource diff |
| **Observability** | Prometheus metrics, structured JSON logging, health endpoints |
| **LiveView UI** | K8s-style sidebar layout with real-time dashboard, resource management, and audit trail |
| **Node Simulator** | Built-in fleet simulator for testing rollout logic without real nodes |

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
GET/POST       /api/v1/bundles               # List / create bundles
GET            /api/v1/bundles/:id/download   # Download bundle artifact
GET            /api/v1/bundles/:id/sbom       # Download SBOM
POST           /api/v1/bundles/:id/revoke     # Revoke a compromised bundle

GET/POST       /api/v1/rollouts              # List / create rollouts
POST           /api/v1/rollouts/:id/pause    # Pause rollout
POST           /api/v1/rollouts/:id/resume   # Resume rollout
POST           /api/v1/rollouts/:id/rollback # Rollback to previous bundle

GET            /api/v1/nodes                 # List nodes
GET            /api/v1/nodes/stats           # Fleet statistics
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
