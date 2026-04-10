# Tusk Operator Snapshot

## Status

Normative projection contract for the compact operator-facing home surface
exposed by `tuskd`.

## Intent

`tusk-asy.9.3` defined the operator information architecture as:

- `Now`
- `Next`
- `History`
- `Context`

This note defines the concrete read-side projection that lets clients render
that home surface without manually joining `tracker_status`, `board_status`,
lane truth, workspace observations, and recent receipts.

## Surface

`tuskd` exposes the compact snapshot through:

- CLI: `tuskd operator-snapshot --repo PATH [--socket PATH]`
- protocol kind: `operator_snapshot`

This surface is provider-agnostic. It carries only operator-facing control-plane
state and recommendations, not provider-specific client metadata.

## Shape

The snapshot is one recomposed projection with these top-level sections:

- `now`
- `next`
- `history`
- `context`
- `drill_down`

### Now

`now` answers what is live, active, stale, or broken right now.

It carries:

- compact runtime health and service mode
- active lanes
- claimed-but-not-launched issues
- stale lanes
- compact obstruction records
- counts for those buckets

### Next

`next` answers what work is ready and what the operator should consider doing
next.

It carries:

- ready issues
- blocked issues
- deferred issues
- compact recommended actions derived from the current state
- counts for those buckets

### History

`history` answers what recently changed that explains the present.

It carries:

- a compact slice of recent receipts
- counts for visible versus total available receipts

It is intentionally not the full raw receipt log.

### Context

`context` answers where the operator is standing.

It carries:

- repo root
- checkout root
- tracker root
- protocol/socket identity
- service/backend identity
- summary counts
- compact workspace observations

### Drill-down

`drill_down` names the raw protocol surfaces that remain available for lower
level inspection:

- `tracker_status`
- `board_status`
- `receipts_status`

## Boundary

The snapshot is not a new source of truth.

It must remain a recomposed projection over existing authority:

- tracker/service state
- board buckets
- lane state
- workspace observations
- receipt history

If a client needs raw detail, it should drill down into the existing projections
instead of inflating the home snapshot into a second low-level API.
