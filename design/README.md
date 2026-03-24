# Design Notes

This directory is ordered from bootstrap core outward.

## Reading Order

1. [`tusk-freeze.md`](./tusk-freeze.md)
   States the frozen bootstrap boundary, supported consumer surface, and
   change policy for the current stable line.

2. [`tusk-bootstrap-contract.md`](./tusk-bootstrap-contract.md)
   Defines the bootstrap-first contract for entering a managed repo without
   taking ownership away from that repo.

3. [`tusk-workflow-topology.md`](./tusk-workflow-topology.md)
   Defines the repo-local workflow objects that sit on top of the bootstrap
   boundary once the repo root, shell, tracker mode, and workspace policy are
   known.

4. [`tusk-tracker-lease-service.md`](./tusk-tracker-lease-service.md)
   Describes an optional downstream service layer for coordinating shared
   tracker runtime, not a prerequisite for bootstrap adoption.

5. [`tusk-architecture.md`](./tusk-architecture.md)
   Describes the richer operational calculus that may be exported above the
   bootstrap substrate. This is downstream of bootstrap core.

## Ownership Boundary

The important split is:

- the frozen bootstrap line defines the supported consumer surface for now,
- bootstrap core determines how to start disciplined repo work,
- repo-local state remains authoritative for repo-local execution,
- optional workflow and service layers may build on that substrate,
- optional operational semantics may sit above those layers.

`tusk` should read in that order. It should not begin by implying that every
consumer repo needs the full downstream stack to count as `tusk`-managed.
