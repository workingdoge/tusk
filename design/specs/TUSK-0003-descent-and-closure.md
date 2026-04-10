# TUSK-0003 — Descent / Closure

## Status

Draft.

Depends on `TUSK-0000` through `TUSK-0002`.

## Purpose

Define how local work stops being merely local.

This spec exists to separate three things that are easy to blur together:

- local progress,
- local terminality,
- canonical closure.

## Core distinction

Local work is only valuable if it can rejoin canonical history without
handwaving.

For the first kernel, that rejoining happens through **descent evidence**.

A descent witness is not a single object. Depending on the transition, it may
include:

- a revision or resolved revision reference,
- live lane state,
- authoritative receipts,
- refreshed board/projection evidence,
- explicit closure reason,
- absence of a live lane.

A single commit is not enough.
A single receipt is not enough.
The relevant compatible bundle is the descent witness.

## Descent states

For issue-oriented lane work, the first kernel has the effective descent states
below.

| Local state | Live lane exists? | Meaning |
|---|---:|---|
| none | no | no live local context is recorded |
| launched | yes | a live local work context exists |
| handoff | yes | revision-level handoff evidence exists, but the lane remains live |
| finished | yes | local terminality has been recorded |
| archived/discharged | no | the live lane has been removed and archive evidence exists |

Important current-runtime note:

> There is no persisted live lane status named `archived`.
> Archive is represented by **absence of live lane state plus `lane.archive`
> receipt evidence**.

## Lifecycle reading

### `launch_lane`

Lawful entry into a local working world.

### `handoff_lane`

First explicit local-outward descent witness.

It says, in effect: this local lane has produced a revision-level handoff
artifact, and the handoff is now recorded.

### `finish_lane`

Records local terminality.

It is stronger than handoff, but it is still not canonical issue closure.

### `archive_lane`

Discharges the live local world.

It removes the live lane record, requires the workspace to already be removed,
and emits archive evidence.

### `close_issue`

Performs canonical base-side closure.

It may occur only after the local world has already been discharged for the
first kernel.

## Laws

### Law 1 — Receipt humility law

A receipt is authoritative evidence that a governed transition was applied.
It is part of the descent witness. It is not identical to current truth.

### Law 2 — Archive-as-discharge law

Archive SHALL be treated as a discharge edge, not as cleanup trivia.

It matters because it:

- removes live lane state,
- preserves evidence in the receipt log,
- marks the local context as no longer active.

Without archive, local work remains half-attached.

### Law 3 — Close-requires-discharge law

Issue closure SHALL require completed discharge, not mere local satisfaction.

For the first kernel, that means at least:

- the issue exists,
- it is not already closed,
- the close reason is explicit,
- no live lane remains.

### Law 4 — Closure-eligibility law

A projection SHOULD be able to answer, per issue:

- whether a live lane remains,
- what descent artifact is missing,
- whether canonical closure is currently admissible.

### Law 5 — Failure-visibility law

If application fails after mutating local state, the runtime SHOULD either:

- restore the prior state, or
- return a failure result that makes the incomplete descent visible.

The current runtime already follows this pattern for several lane transitions.

## Closure predicate

For the first kernel, the operator-facing closure predicate is intentionally
small:

\[
\texttt{closure\_eligible(issue)} :=
\texttt{issue\_exists}
\wedge
\texttt{issue\_not\_closed}
\wedge
\texttt{no\_live\_lane}
\wedge
\texttt{close\_reason\_supplied}
\]

Later kernels MAY strengthen this predicate, but they SHALL preserve the same
shape: closure is a base-side act that depends on explicit descent conditions.

## Result

This spec turns a psychologically expensive question into a structural one:

> **When is local work actually rejoined to the shared world?**

Answer:

- when the required descent evidence exists,
- the live local state has been discharged as required,
- and canonical closure is performed under the base-side rules.
