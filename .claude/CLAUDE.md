# Sentinel Control Plane - Development Guide

## Overview

Sentinel CP is a fleet management control plane for Sentinel reverse proxies, built in Elixir/Phoenix. It provides:

- Bundle compilation and distribution
- Safe rollout orchestration with health gates
- Node lifecycle management
- Audit logging and observability

## Quick Start

```bash
# Install dependencies
mise install
mise run setup

# Start development server
mise run dev

# Run tests
mise run test
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Control Plane (Phoenix)                   │
├─────────────┬─────────────┬─────────────┬──────────────────┤
│  REST API   │  LiveView   │   Compiler  │  Rollout Engine  │
│             │     UI      │   Service   │     (Oban)       │
└──────┬──────┴──────┬──────┴──────┬──────┴────────┬─────────┘
       │             │             │               │
       │     ┌───────┴───────┐    │               │
       │     │   PostgreSQL  │    │               │
       │     │   (SQLite dev)│    │               │
       │     └───────────────┘    │               │
       │                          │               │
       │              ┌───────────┴───────────────┤
       │              │      MinIO / S3           │
       │              │   (Bundle Storage)        │
       │              └───────────────────────────┘
       │
┌──────┴──────────────────────────────────────────────────────┐
│                      Sentinel Nodes                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │ Node 1  │  │ Node 2  │  │ Node 3  │  │ Node N  │  ...   │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Project Structure

```
lib/
├── sentinel_cp/
│   ├── accounts/       # Users, API keys, authentication
│   ├── audit/          # Audit logging
│   ├── bundles/        # Bundle lifecycle
│   ├── compiler/       # Compilation pipeline
│   ├── nodes/          # Node management
│   ├── projects/       # Project/tenant management
│   ├── rollouts/       # Rollout orchestration
│   ├── simulator/      # Node simulator for testing
│   └── storage/        # S3/MinIO abstraction
└── sentinel_cp_web/
    ├── controllers/    # REST API
    ├── live/           # LiveView pages
    └── components/     # UI components
```

## Key Concepts

### Bundles
Immutable, content-addressed configuration artifacts:
- Validated via `sentinel validate`
- Compressed as `.tar.zst`
- Stored in S3/MinIO
- Identified by SHA256 hash

### Rollouts
Safe deployment plans:
- Batch-based progression
- Health gates between steps
- Automatic pause on failure
- Manual rollback support

### Nodes
Sentinel proxy instances:
- Pull-based bundle distribution
- Heartbeat-based health tracking
- Per-node status during rollouts

## Database

- **Development/Test**: SQLite (zero configuration)
- **Production**: PostgreSQL

The adapter is selected at compile time via `config :sentinel_cp, :ecto_adapter`.

## Background Jobs

Using Oban for reliable job processing:
- `RolloutTickWorker`: Advances rollout state
- `StalenessWorker`: Marks offline nodes
- `GCWorker`: Cleans old bundles

## Development

### Running Tests
```bash
mise run test           # Full suite
mise run test:coverage  # With coverage
```

### Code Quality
```bash
mise run format         # Format code
mise run lint           # Run Credo
mise run check          # Format + lint + test
```

### Database
```bash
mise run db:setup       # Create + migrate
mise run db:reset       # Drop + create + migrate
mise run db:migrate     # Run migrations
```

## Implementation Status

See [CONTROL_PLANE_ROADMAP.md](./CONTROL_PLANE_ROADMAP.md) for detailed phases.

Current phase: **Phase 1 - Skeleton**

## Work Instructions

When implementing features:

1. **Follow the roadmap phases** - Don't skip ahead
2. **Write tests first** - Especially for domain logic
3. **Use contexts** - Keep Phoenix conventions
4. **Audit mutations** - Log all state changes
5. **Handle errors explicitly** - No silent failures

### Code Style

- Use `with` for happy-path pipelines
- Use `TypedStruct` for complex structs
- Prefer explicit function heads over guards
- Keep LiveViews thin - delegate to contexts

### Naming Conventions

- Contexts: `SentinelCp.Nodes`, `SentinelCp.Bundles`
- Schemas: `SentinelCp.Nodes.Node`, `SentinelCp.Bundles.Bundle`
- Workers: `SentinelCp.Rollouts.TickWorker`
- LiveViews: `SentinelCpWeb.NodesLive.Index`

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection (prod) | Required in prod |
| `SECRET_KEY_BASE` | Phoenix secret | Required in prod |
| `PHX_HOST` | Public hostname | `localhost` |
| `PORT` | HTTP port | `4000` |
| `S3_BUCKET` | Bundle storage bucket | `sentinel-bundles` |
| `S3_ENDPOINT` | S3/MinIO endpoint | `http://localhost:9000` |
| `S3_ACCESS_KEY_ID` | S3 access key | - |
| `S3_SECRET_ACCESS_KEY` | S3 secret key | - |
