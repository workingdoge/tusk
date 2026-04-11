# Tusk Workflow Topology

## Status

Top-down design note for the repo-local `tusk` workflow state model.

This note exists to stop issue state, lane state, dependency state, and shared
service state from drifting into separate script-local conventions.

## Intent

`tusk` needs one coherent workflow topology for this repo.

Today we already have:

- issue state in `bd`,
- partial lane state in `bd` metadata,
- dependency edges in `bd`,
- tracker health in repo-local scripts,
- and a tracker lease service only as a design note.

Those are all real pieces, but they are not yet one model.

The goal of this note is to define the minimum shared object model so that:

- commands are only projections of that model,
- each object has one authority boundary,
- and future lease/service work does not get bolted onto issue scripts by
  accident.

## The Problem

Right now, several things that look similar are actually different:

- an issue marked `in_progress`,
- a lane that is actively running,
- a dependency edge that makes work not-ready,
- a healthy shared tracker backend,
- and a lease holder that currently depends on that backend.

These should not collapse into one state bit.

The immediate symptom is already visible in this repo:

- `bd` can show multiple issues as `in_progress`,
- while `bd-board` can show zero active lanes,
- because `issue status` and `lane activity` are different objects.

That is not a bug in the board.
It is evidence that the topology needs to be named explicitly.

## Core Objects

### 1. Issue

An issue is the unit of planned work.

Examples:

- `config-w1b.7`
- `config-8vr.5`

Current authority:

- `bd`

Current data:

- `id`
- `title`
- `status`
- `priority`
- `type`
- labels
- acceptance and notes

Invariants:

- issue state answers "what work exists?"
- issue state does **not** answer "is a worker currently running?"

### Issue Facets

Issue labels should carry the orthogonal facets that the core issue schema does
not express directly.

The first required facet families for framework work are:

- `track:*`
- `place:*`
- `surface:*`

These labels are not freeform tags.
They are coordinates over the issue graph.

Current intended meanings:

- `track:*`: where the issue sits in the framework program
  e.g. `track:core`, `track:platform`, `track:proof`, `track:incubation`
- `place:*`: where the work semantically belongs
  e.g. `place:tusk`, `place:boundary`, `place:consumer`, `place:home`,
  `place:aac`, `place:kurma`, `place:fish`
- `surface:*`: which surface the issue is about
  e.g. `surface:ops`, `surface:composition`, `surface:isolation`,
  `surface:adoption`, `surface:paid-http`

For framework issues, each issue should normally carry exactly one label from
each of those three families.

The important invariant is:

- parent/child and dependency edges still express workflow shape
- statuses still express lifecycle
- facet labels express orthogonal projections over the same issue graph

### Bundle-Style Reading

It is useful to read the tracker in a bundle-style way.

The base space is the issue/dependency graph.
The fiber over each issue is the small set of orthogonal facet coordinates such
as `track`, `place`, and `surface`.

That analogy is helpful because it lets operator views project the same work by
different axes without inventing a second source of truth.

But this is only a projection model.
`bd` should remain a typed workflow graph with labels, not a literal simplicial
or fiber-bundle substrate.

### 2. Dependency Edge

A dependency edge expresses workflow shape between issues.

Examples:

- `parent-child`
- `discovered-from`
- later perhaps stronger blocker classes

Current authority:

- `bd`

Current data:

- source issue
- target issue
- edge type

Invariants:

- dependency edges answer "how does work relate?"
- they should drive readiness semantics
- they should not be inferred from lane metadata

### 3. Lane

A lane is an execution context for issue work.

Examples:

- a semantic `jj` workspace
- a prompt file
- a launch receipt

Current authority:

- `bd` issue metadata under the `lane_*` prefix

Current data:

- workspace name and path
- prompt file
- launch mode
- tracker preflight
- publish scope
- landing owner and target
- last launch time
- later handoff and outcome fields

Invariants:

- a lane answers "how is this issue being worked?"
- a lane is attached to an issue, but is not the same thing as issue status
- an issue may be `in_progress` with no live lane

### Lane-Scoped Isolation

Some lane work may run inside a bounded local isolation surface such as a
container or microvm.

That runtime is not a new issue object.
Treat it as:

- a lane-attached execution path when it is short-lived and probe-like
- or a service/lease participant if it becomes long-lived shared runtime

The important invariant is:

- the lane remains the workflow context
- the isolation runtime is only one bounded way that lane work may execute
- and the resulting run still has to reattach through explicit receipts and any
  visible repo state it produced

For the attachment contract, see
[`design/tusk-isolation-attachment.md`](./tusk-isolation-attachment.md).

### 4. Service

A service is shared runtime infrastructure needed by lanes.

Current example:

- the repo-local `bd` tracker backend

Current authority:

- mixed

Today:

- health and bootstrap are handled by repo-local scripts like
  [`bd-tracker-ensure`](../scripts/bd-tracker-ensure.sh)
- there is no first-class service state record yet

Target authority:

- `tusk`-owned runtime/service state

Invariants:

- service state answers "what shared runtime exists for this repo?"
- service state is not issue state and not lane state

### 5. Lease

A lease is a claim on a shared service by a coordinator or lane.

Current authority:

- none yet

Status:

- only designed so far in
  [`design/tusk-tracker-lease-service.md`](./tusk-tracker-lease-service.md)

Target data:

- lease id
- holder issue or lane
- holder kind
- workspace
- acquired time
- heartbeat time
- expiry

Invariants:

- a lease answers "who currently depends on this shared service?"
- leases should be explicit, not inferred from a PID or port

### 6. Receipt

A receipt is an auditable record of a workflow transition.

Current authorities:

- issue-side receipts live in `bd` notes and metadata
- service-side receipts do not exist yet

Current examples:

- lane launch receipt in [`scripts/bd-lane.sh`](../scripts/bd-lane.sh)
- tracker health repair note on issues

Target shape:

- issue receipts
- lane receipts
- service receipts
- lease receipts

Invariants:

- receipts answer "what transition actually happened?"
- receipts are evidence, not current truth

## Authority Boundaries

The simplest good split is:

- `bd` owns issues and dependency edges
- `bd` metadata currently owns lanes
- `tusk` should eventually own services and leases
- receipts may be split by object, but should preserve cross-references

That gives this current authority table:

| Object | Current authority | Future authority |
| --- | --- | --- |
| Issue | `bd` | `bd` |
| Dependency edge | `bd` | `bd` |
| Lane | `bd` metadata | maybe `bd` metadata, unless lane count or complexity forces extraction |
| Service | repo-local scripts | `tusk` |
| Lease | none | `tusk` |
| Receipt | mixed | mixed, but structured |

The important rule is:

one object should have one authoritative home.

Commands are views, not truth.

## Current Projections

Today the repo has these useful projections:

### `bd ready`

Projection of:

- issue readiness
- dependency-aware claimability

Authority:

- `bd`

### `bd-board`

Projection of:

- tracker summary
- active in-progress issues
- active lanes from `lane_*` metadata
- ready queue

Authority:

- derived view only

This is useful, but it is not yet a dependency graph and not yet a lease view.

### `bd-lane`

Projection plus transition:

- creates lane state for an issue
- writes a lane launch receipt

Authority touched:

- `bd` issue metadata and notes

### `bd-tracker-ensure`

Projection plus repair:

- tracker service health
- bounded service repair

Authority touched:

- shared repo runtime

This is still service logic without a first-class service state record.

## Why This Matters

This topology prevents several bad collapses:

### 1. Issue status vs lane activity

`in_progress` means:

- someone has taken ownership of the issue

It does **not** necessarily mean:

- a lane is live right now

### 2. Lane activity vs service lease

A lane may exist without currently holding a live tracker lease.

Likewise, a coordinator may hold a tracker lease without being a code lane.

### 3. Dependency graph vs operational sequencing

Dependencies say:

- what work relates to what

They do not fully determine:

- what runtime infrastructure is currently in use
- or which worker should perform the next transition

### 4. Receipt vs state

A receipt says:

- what happened

It does not automatically define:

- what is true now

This matters for stale lanes, stale leases, and abandoned workspaces.

## Minimal V0 Data Model

The minimum useful unified shape is:

```text
Issue
DependencyEdge
Lane
Service
Lease
Receipt
```

With these relationships:

- `Issue --has-many--> DependencyEdge`
- `Issue --has-zero-or-more--> Lane`
- `Lane --may-hold--> Lease`
- `Lease --belongs-to--> Service`
- each object may emit `Receipt`

This is enough to support:

- board view
- dependency view
- tracker service view
- lease view
- handoff/audit

without forcing a giant new database on day one.

## Command Model

The commands should be understood as projections of the topology:

See also [`design/tusk-transition-carrier.md`](./tusk-transition-carrier.md)
for the primitive carried object that should drive control-plane transitions
over these projections.

- `bd-board`: issue + lane projection
- future `tusk deps`: dependency projection
- future `tusk tracker status`: service projection
- future `tusk tracker lease`: lease transition
- future `tusk receipts`: receipt projection

This keeps the command surface honest.

We should prefer adding projections over inventing new hidden state.

The missing runtime seam is therefore not "another board view." It is one
transition carrier that can move between issue, lane, service, and receipt
authorities without collapsing them.

Isolation work fits under that seam.
It should attach either as:

- one lane-scoped runtime attempt beneath the workflow topology
- or, once stabilized, one admitted executor surface beneath the semantic
  spine

It should not introduce a second workflow truth distinct from issue, lane,
service, lease, and receipt objects.

## Phased Implementation

### Phase 0: Current state

Already present:

- issues and dependencies in `bd`
- lane metadata in `bd`
- board view
- tracker health check/repair

### Phase 1: Dependency projection

Next likely addition:

- a dependency-oriented view over current `bd` data

This could start as:

- `bd-board --json` enrichment, or
- a separate `tusk deps` / `bd-deps` command

### Phase 2: Service state

Add a first-class service record for the repo-local tracker backend.

This is the bridge from:

- health-checked scripts

to:

- explicit shared runtime state

### Phase 3: Lease state

Implement the tracker lease service from
[`design/tusk-tracker-lease-service.md`](./tusk-tracker-lease-service.md).

That is where agents can actually see:

- who currently holds tracker access
- which lane or coordinator holds it
- whether that lease is fresh or stale

### Phase 4: Structured receipts

Standardize receipts across:

- lane launch
- handoff
- tracker ensure/repair
- lease acquire/release/gc

## Recommendation

Treat this as the canonical workflow topology for `tusk`:

- `bd` remains the planning and dependency authority
- lane metadata remains attached to issues for now
- service and lease state move into `tusk` when implemented
- command surfaces are projections over those objects

That lets us keep building incrementally without pretending that issue status,
worker activity, and service leases are all the same kind of thing.

## Immediate Next Step

The next best slice is:

1. keep using `bd-board` as the issue/lane projection
2. build `config-w1b.7` as the service/lease slice
3. only then add a dependency-specific projection if the board stops being
   sufficient
