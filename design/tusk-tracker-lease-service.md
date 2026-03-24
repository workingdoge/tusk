# Tusk Tracker Lease Service

## Status

Top-down design note for a repo-scoped tracker supervisor and lease service.

This note exists to preserve the architecture before we rush into another
ad hoc `bd` / Dolt workaround.

The managed-repo bootstrap contract is defined separately in
[`design/tusk-bootstrap-contract.md`](./tusk-bootstrap-contract.md). This note
describes an optional downstream service layer, not a prerequisite for treating
a repo as `tusk`-managed.

## Question

Is this a distributed systems problem?

Yes, but only in a small and specific sense.

At the right level, this is a resource coordination problem over:

- a shared tracker backend,
- multiple independent worker lanes,
- partial failure,
- health checks,
- lease ownership,
- and eventual cleanup of stale holders.

That means it has the shape of a distributed system even if v0 runs on one
host and only listens on loopback or a Unix socket.

So the correct move is:

- treat it as a coordination service,
- keep v0 single-host and repo-scoped,
- and only later widen it into a network-visible service if the rest of `tusk`
  actually needs cross-process or cross-host coordination.

## What Problem Are We Solving

We are **not** primarily solving "find a free port."

We are solving:

- how one repo owns one healthy tracker backend,
- how multiple `tusk` lanes discover and share it,
- how they avoid racing to start competing Dolt servers,
- how they distinguish "port occupied" from "tracker healthy",
- and how the coordinator can recover or garbage-collect stale state.

So the service should lease **tracker access**, not raw ports.

Ports are only one implementation detail inside that problem.

## Why A Port Allocator Is Not Enough

A raw port allocator answers:

- "what port can I bind?"

That is too weak.

`bd` / Dolt needs stronger answers:

- which repo is this backend for?
- what process owns it?
- what data directory is it serving?
- is it healthy right now?
- who currently depends on it?
- when was the last lease heartbeat?
- is the server reusable or stale?

If we only lease ports, we still cannot tell whether:

- the existing process is the right Dolt server,
- the process is healthy enough for `bd show`,
- a second lane should reuse the server or replace it,
- or a dead coordinator left a stale backend running.

So the abstraction should be:

`tracker service = repo identity + endpoint + process + health + leases`

not:

`tracker service = port number`

## Top-Down Shape

The service should sit in the coordinator plane.

That matches the `tusk` tracker contract:

- tracker ownership is shared infrastructure,
- the coordinator owns readiness and repair,
- worker lanes consume a healthy tracker environment,
- workers should not each become responsible for Dolt lifecycle.

So the top-down stack is:

1. `tusk` skill / coordinator
2. managed-repo bootstrap contract
3. optional tracker lease service
4. repo-scoped `bd` + Dolt backend
5. worker lanes that lease the tracker

The important sequencing rule is:

- bootstrap determines how the repo is entered and preflighted,
- the lease service coordinates one optional shared runtime inside that repo.

This preserves the right boundary:

- coordinator owns backend lifecycle when the service exists,
- worker owns issue-specific code work,
- service mediates access and health.

## Service Object Model

The minimum objects are:

### 1. Service Key

Identifies the backend being coordinated.

For v0:

```text
service_kind = "bd-tracker"
repo_root = /Users/arj/dev/blackhole/config
service_key = hash(service_kind, repo_root)
```

This makes one tracker backend canonical per repo.

### 2. Endpoint

Where the backend is reachable.

For v0:

- host or socket path
- port if TCP is used
- protocol

Example:

```json
{
  "protocol": "tcp",
  "host": "127.0.0.1",
  "port": 13606
}
```

Later we may prefer a Unix socket for local-only coordination.

### 3. Runtime Record

Describes the backend process and data.

Example:

```json
{
  "pid": 15171,
  "data_dir": ".beads/dolt",
  "log_path": ".beads/dolt-server.log",
  "started_at": "2026-03-15T13:00:00Z"
}
```

### 4. Lease

Represents a lane or coordinator consumer that depends on the backend.

Example:

```json
{
  "lease_id": "lease-abc",
  "holder": "config-8vr.5",
  "holder_kind": "lane",
  "workspace": "/path/to/workspace",
  "acquired_at": "...",
  "expires_at": "...",
  "heartbeat_at": "..."
}
```

### 5. Health

Separates mere process existence from actual tracker readiness.

It should be able to say:

- process exists
- port/socket reachable
- `bd dolt status` matches expected repo data dir
- a real tracker read succeeds, e.g. `bd ready --json` or `bd show <id>`

This distinction matters because "port occupied" is not the same as
"tracker healthy."

### 6. Receipt

The service should emit operational receipts for:

- backend start,
- lease acquire,
- lease release,
- health failure,
- garbage collection,
- backend stop or replacement.

This should rhyme with the broader `tusk` semantics:

`witnesses -> intents -> admission -> realization -> receipts`

The tracker lease service is one executor-side operational subsystem inside that
larger picture.

## Core Operations

V0 should expose only a small command surface.

### `ensure`

Ensure that the canonical tracker backend for a repo exists and is healthy.

Responsibilities:

- find existing runtime record
- confirm health
- if absent or stale, allocate endpoint and start backend
- return endpoint + runtime record

### `status`

Report current health and lease state.

Responsibilities:

- show repo root
- show endpoint
- show PID
- show health result
- show active leases

### `lease`

Acquire a lease on the repo's tracker backend.

Responsibilities:

- ensure the backend first
- record holder identity
- return lease + endpoint

### `heartbeat`

Refresh lease liveness.

Responsibilities:

- update holder TTL
- optionally re-check backend health on a cheap cadence

### `release`

Release a lease.

Responsibilities:

- drop the holder record
- maybe stop backend if no leases remain and policy allows

### `gc`

Garbage-collect stale leases and stale runtimes.

Responsibilities:

- reap expired holders
- detect dead PIDs
- mark or remove stale runtime records

## Admission Model

The service should preserve an admission boundary.

Not every caller who can ask for a lease should necessarily:

- start a new backend,
- replace a stale backend,
- or mutate repo-global tracker settings.

So even in v0, there is a useful split between:

- declared consumer intent: "I need tracker access"
- admitted lease: "you may use this backend"
- repair authority: "you may replace or restart this backend"

That suggests two classes of holders:

- coordinator holders
- worker holders

Default policy:

- coordinator may `ensure`, repair, and replace
- worker may `lease`, `heartbeat`, `release`
- worker should not unilaterally replace shared backend state

## Local First, Distributed Later

The service should not begin life as a network platform.

V0:

- one host
- one repo
- one service record per repo
- local process supervision
- local leases

Good implementation options:

- JSON state in `.tusk/` or `.beads/`
- a small local daemon
- Unix socket or loopback TCP

Only later, if we actually need "other tusks can ping this one," should we
widen to:

- loopback HTTP with stable schema
- SSH-tunneled access
- or some other distributed control plane

The important thing is that the semantics already support widening.

## Relationship To Existing Repo Workflow

Today:

- `devenv up` owns managed services
- tracker preflight is performed from the repo's managed shell
- wrapper commands may exist in some repos, but are not assumed by the
  bootstrap contract

With the tracker lease service:

- `devenv up` may still own the long-lived daemon
- repo-local lane wrappers should call `tusk tracker ensure` or `lease`
  instead of raw startup/retry logic when the service is active
- worker briefs should state that the tracker lease is coordinator-owned shared
  infrastructure
- any repo-local handoff or follow-up helpers should rely on the same service
  path

That means the service belongs adjacent to `tusk` workflow helpers, not buried
inside a single script.

## Relationship To Tusk Semantics

This service should be treated as a subsystem of `tusk`, not as a random helper.

One way to read it in the current operational vocabulary:

- witness:
  tracker health report, endpoint, runtime record
- intent:
  acquire tracker lease for a lane
- admission:
  is this caller allowed to use or repair the backend?
- realization:
  lease granted, backend started or reused
- receipt:
  lease/start/release/gc record

That is why this service fits `tusk` naturally.

## Failure Modes

The design should explicitly handle:

1. Port occupied by unrelated process
2. Port occupied by Dolt but wrong repo/data dir
3. Process exists but tracker reads fail
4. Lease holder disappears without release
5. Multiple coordinators race to start the backend
6. Backend dies while leases remain active
7. Repo moves or workspace path changes while a lease remains recorded

If we do not model these up front, the service will just become another opaque
retry loop.

## Suggested V0 Interface

At the command level:

```bash
tusk tracker ensure --repo /path/to/repo
tusk tracker status --repo /path/to/repo
tusk tracker lease --repo /path/to/repo --holder config-8vr.5
tusk tracker heartbeat --lease lease-abc
tusk tracker release --lease lease-abc
tusk tracker gc --repo /path/to/repo
```

At the library level:

- a repo-scoped tracker service record
- a lease record
- a health probe result
- a receipt type for lifecycle events

## Recommendation

Build this as a **tracker lease service**, not a port lease service.

Start with:

1. repo-scoped identity
2. health-aware `ensure`
3. explicit lease records with TTL
4. coordinator-versus-worker admission boundary
5. local-only implementation

Do **not** start with:

- arbitrary free-port leasing,
- network distribution as a first goal,
- per-worker Dolt ownership,
- or hidden auto-restart loops with no receipts

## Next Slice

The next implementation slice should be:

1. add a design-tracked `tusk` issue for the tracker lease service
2. implement a local state/receipt format
3. implement `status` and `ensure`
4. wire `bd-lane` preflight to the service
5. only then extend to worker leases and remote callers
