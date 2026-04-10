# Tusk Governed Transition Adapters

## Status

Normative adapter-map note beneath the governed transition kernel.

## Intent

This note defines the adapter seams beneath the kernel named in
[`design/tusk-governed-transition-kernel.md`](./tusk-governed-transition-kernel.md).

The rule is:

- the kernel owns proposal, witness record, envelope, admission, application,
  receipt, and projection semantics
- adapters own the quirks of tracker storage, lane storage, workspaces,
  backend/service runtime, and receipt persistence

The point is not to invent many traits up front.
The point is to stop backend, `bd`, `jj`, filesystem, and receipt-log quirks
from becoming the kernel vocabulary.

## Why This Boundary Is Needed

Today `tuskd-core` still mixes at least six kinds of responsibility:

- tracker queries and mutations through `tusk-tracker`
- lane-state file reads and writes
- workspace and revision operations through `jj` and the filesystem
- backend probing/startup/adoption
- service-record and lease publication
- receipt append and projection assembly

That makes the code look like one kernel, but it is actually one kernel plus a
set of runtime adapters living in the same file.

This note names those seams before `8.6.3` recasts the action path.

## Kernel Versus Adapters

The kernel should answer:

- what was proposed?
- which witnesses matter?
- is the transition admitted?
- what application should happen?
- what receipt should be emitted?
- what projection should be returned?

Adapters should answer:

- how do we read or mutate issue truth?
- how do we observe or mutate lane truth?
- how do we resolve revisions and create/remove workspaces?
- how do we probe, start, or adopt the backend?
- how do we persist receipts?
- how do we gather authoritative inputs for projections?

The kernel is semantic.
Adapters are operational.

## First Adapter Families

### 1. `TrackerStore`

`TrackerStore` owns issue truth and dependency/readiness truth.

It should cover:

- show one issue
- claim one issue
- close one issue
- read ready issues
- read tracker status

It should not own:

- Dolt port selection
- backend startup policy
- service-record publication
- workspace creation

Current implementation:

- logical seam: `TrackerStore`
- current wrapper: [`scripts/tusk-tracker.sh`](../../scripts/tusk-tracker.sh)
- current upstream authority: `bd`

Important nuance:
the current `tusk-tracker` script also exposes backend admin commands because
`bd` exposes them. That is a current packaging convenience, not the desired
kernel boundary.

### 2. `LaneStateStore`

`LaneStateStore` owns first-class lane truth in `.beads/tuskd/lanes.json`.

It should cover:

- read all lanes
- read one lane by issue id
- upsert one lane record
- remove one lane record

Lane state is not a projection and not just a receipt cache.
It is authoritative repo-local coordinator state.

Current implementation:

- logical seam: `LaneStateStore`
- current code: `current_lanes`, `upsert_lane_state`, `remove_lane_state` in
  `crates/tuskd-core/src/main.rs`

### 3. `WorkspaceOps`

`WorkspaceOps` owns `jj` and filesystem workspace effects.

It should cover:

- resolve a revision to a commit
- observe whether a workspace path exists
- list workspaces when a projection needs it
- add a workspace
- describe or seed the new workspace
- forget a workspace
- remove workspace artifacts from disk

This boundary exists because workspace semantics are not tracker semantics and
not receipt semantics.

Current implementation:

- logical seam: `WorkspaceOps`
- current code: `resolve_revision_commit`, workspace observation helpers, and
  `jj workspace ...` / `jj describe` calls in `crates/tuskd-core/src/main.rs`
- compatibility shell path still exists in [`scripts/tuskd.sh`](../../scripts/tuskd.sh)

### 4. `BackendRuntime`

`BackendRuntime` owns the mutable backend/service control plane.

It should cover:

- observe backend health and runtime facts
- choose or adopt a port/owner
- configure tracker connection details when required
- start or adopt a live backend
- publish the repo-local and host-local service record
- read and update lease/service metadata

This is the authority behind `tracker.ensure`.

Current implementation:

- logical seam: `BackendRuntime`
- current code: `ensure_backend_connection`, `health_snapshot`,
  `write_service_record`, service/lease helpers, and host-lock handling in
  `crates/tuskd-core/src/main.rs`
- specialized design note:
  [`design/tusk-backend-service-carrier.md`](./tusk-backend-service-carrier.md)

Important nuance:
`BackendRuntime` is not the same thing as `TrackerStore`.
The current `tusk-tracker backend ...` commands are the place where the old
wrapper still leaks backend admin through the tracker boundary.

### 5. `ReceiptStore`

`ReceiptStore` owns durable receipt persistence and retrieval.

It should cover:

- append one receipt
- scan receipts
- filter receipts relevant to one issue or transition

It should not decide:

- whether a transition is admissible
- whether a lane is authoritative
- whether an issue is ready

Current implementation:

- logical seam: `ReceiptStore`
- current code: `append_receipt`, `issue_receipt_refs`,
  `receipts_status_projection` in `crates/tuskd-core/src/main.rs`
- current authority: `.beads/tuskd/receipts.jsonl`

### 6. `ProjectionQueries`

`ProjectionQueries` is the read-model boundary.

It should cover:

- tracker status projection
- board status projection
- receipts status projection

`ProjectionQueries` is not an authority-bearing store.
It derives read views from:

- `TrackerStore`
- `LaneStateStore`
- `WorkspaceOps`
- `BackendRuntime`
- `ReceiptStore`

Current implementation:

- logical seam: `ProjectionQueries`
- current code: `status_projection`, `board_status_projection`,
  `receipts_status_projection` in `crates/tuskd-core/src/main.rs`

## Composite Reality In The Current Repo

The current code shape is transitional.

### `scripts/tusk-tracker.sh`

This is currently one wrapper that bundles:

- issue-store commands
- tracker-read commands
- backend admin commands

The kernel should treat those as at least two logical seams:

- `TrackerStore`
- the tracker-facing slice of `BackendRuntime`

### `crates/tuskd-core/src/main.rs`

This file currently contains:

- kernel logic
- lane-state persistence
- receipt persistence
- projection assembly
- backend/service runtime logic
- `jj` and filesystem workspace effects

That is acceptable during extraction, but it should be read as co-located
modules, not as one undifferentiated kernel.

### `scripts/tuskd.sh`

This should converge toward a thin adapter edge only:

- CLI argument parsing
- environment and path adaptation
- socket/bootstrap compatibility
- delegation into `tuskd-core`

Any remaining write-side realization logic left in shell is debt against this
adapter map, not part of the kernel's ideal shape.

## Minimal Adapter Contracts

The first recast does not need full trait code yet, but it does need the
contract shape.

Prototype boundary names:

```text
TrackerStore
LaneStateStore
WorkspaceOps
BackendRuntime
ReceiptStore
ProjectionQueries
```

Prototype responsibilities:

```text
TrackerStore:
  show_issue
  claim_issue
  close_issue
  ready_set
  tracker_status

LaneStateStore:
  list_lanes
  lane_for_issue
  upsert_lane
  remove_lane

WorkspaceOps:
  resolve_revision
  observe_workspace
  list_workspaces
  add_workspace
  describe_workspace
  forget_workspace
  remove_workspace

BackendRuntime:
  observe_backend
  ensure_backend
  publish_service
  current_leases

ReceiptStore:
  append_receipt
  receipt_refs_for_issue
  scan_receipts

ProjectionQueries:
  tracker_status_projection
  board_status_projection
  receipts_status_projection
```

The recast may rename these, but it should preserve the split.

## What Stays Out Of The Kernel

The kernel should not know:

- how `bd` formats CLI JSON
- how `jj` prints revision errors
- how Dolt ports are chosen
- how service locks are encoded on disk
- how receipt lines are appended to a file

Those are adapter concerns.

The kernel should know:

- which witnesses are needed
- which adapter facts matter for admission
- which application steps are required
- which receipt kind is authoritative
- which projection should be returned

## Immediate Consequences

This note implies the next order:

1. `8.6.3` should reorganize the action path around the kernel vocabulary while
   depending on explicit adapter seams rather than raw helper functions.
2. the current `tusk-tracker` wrapper should be treated as an implementation of
   `TrackerStore` plus part of `BackendRuntime`, not as the kernel itself
3. projections should remain derived read boundaries, not become mutable
   authority stores
4. later replacement of `bd` becomes an adapter swap, not a kernel rewrite

## Recommendation

Proceed as if:

- `TrackerStore` owns issue truth
- `LaneStateStore` owns live lane truth
- `WorkspaceOps` owns `jj` and workspace effects
- `BackendRuntime` owns backend/service authority
- `ReceiptStore` owns durable audit records
- `ProjectionQueries` owns derived read views
- and the governed transition kernel sits above all of them without inheriting
  their quirks as its own semantics
