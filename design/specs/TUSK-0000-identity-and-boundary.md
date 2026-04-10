# TUSK-0000 — Identity and Boundary

## Status

Draft.

## Purpose

Define what kind of thing Tusk is, what authority it owns, and what it
explicitly does **not** attempt to become.

This spec exists to keep the kernel hard while keeping the scope small.

## Kernel sentence

> **Tusk governs repo-local workflow transitions over canonical coordination state.**

Tusk is the repo-local governed workflow kernel. It sits at the control
boundary where local work becomes lawful, reviewable, and replayable.

## Scope

For the first kernel, Tusk governs the family:

- `create_child_issue`
- `claim_issue`
- `close_issue`
- `launch_lane`
- `handoff_lane`
- `finish_lane`
- `archive_lane`
- `tracker.ensure`

A new transition belongs in Tusk only if it crosses a clear repo-local
authority boundary and can emit a meaningful authoritative receipt.

## Authority matrix

| Surface | Authority | What Tusk may do |
|---|---|---|
| `bd` tracker state | issue identity, issue lifecycle, dependency edges, issue metadata | read it, verify against it, project it, and invoke explicit tracker mutations |
| Tusk runtime state | service records, lease/runtime records, live lane records, worker sessions, receipt logs | own it directly |
| Workspace / `jj` state | local checkout state, revisions, local edits, ephemeral worker output | observe it and shape it through admitted transitions |
| Projection surfaces | none; projections are read-side only | recompute and publish them |
| Receipts | authoritative evidence of past admitted application | emit them and reference them |

## Non-goals

Tusk SHALL NOT be specified as:

- the source of issue truth,
- the workspace itself,
- the VCS itself,
- a prompt or agent persona,
- a projection surface,
- a universal ontology for all future adapters.

More sharply:

- Tusk is not `bd`.
- Tusk is not `jj`.
- Tusk is not a workspace.
- Tusk is not a dashboard.
- Tusk is not “the whole universe”.

## Boundary tests

A proposed feature belongs **inside** the kernel only if all of the following
hold:

1. it has a clear repo-local authority boundary,
2. it can be described as a governed transition over explicit witnesses,
3. successful application can emit an authoritative receipt,
4. projection can remain downstream of authority.

If any of those fail, the feature is not yet a kernel transition.

## Laws

### Law 1 — Bounded kernel law

Every governed transition SHALL name a repo-local authority boundary.

If the boundary cannot be named, the transition is not ready to enter the
kernel.

### Law 2 — No ambient authority law

A shell command sequence SHALL NOT count as authority merely because it ran.

Authority comes from admitted application plus emitted receipt.

### Law 3 — Tracker humility law

Tracker truth SHALL remain tracker truth.

Tusk MAY read it, validate against it, and mutate it through explicit tracker
operations. Tusk SHALL NOT silently replace it.

### Law 4 — Workspace humility law

A workspace is local work state. Its existence SHALL NOT be treated as
canonical coordination truth.

### Law 5 — Projection humility law

A projection MAY summarize, narrate, or recommend. It SHALL remain downstream
of authoritative tracker, runtime, lane, session, and receipt state.

### Law 6 — Receipt humility law

A receipt is authoritative evidence that an admitted transition was applied.
A receipt is **not**, by itself, current truth.

### Law 7 — Explicit adapter law

Interaction with systems beyond the local workflow kernel SHALL happen through
explicit realizations, executors, drivers, or adapters.

No hidden coupling to “the rest of the universe”.

## Result

If this spec is respected, the rest of the series can stay narrow:

- `TUSK-0001` defines how local work contexts sit over canonical coordination.
- `TUSK-0002` defines how proposals become admissible.
- `TUSK-0003` defines how local work is discharged and closure becomes lawful.
- `TUSK-0004` binds those laws to concrete transitions.
- `TUSK-0005` keeps projections useful without letting them become authority.
