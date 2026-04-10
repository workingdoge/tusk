# TUSK-0001 — Base / Fiber

## Status

Draft.

Depends on `TUSK-0000`.

## Purpose

Define the structural split between canonical coordination state and local work
contexts.

The payoff is simple:

> **Context should be recoverable from structure, not re-explained from memory.**

## Guiding picture

The clean reading is:

\[
\pi : \mathcal{E} \to \mathcal{B}
\]

where:

- \(\mathcal{B}\) is canonical coordination state,
- \(\mathcal{E}\) is the total operational space of lawful local work
  contexts,
- and \(\pi\) projects any local context back to the canonical locus it is
  over.

Equivalently, Tusk may be read as the Grothendieck construction of indexed work
contexts:

\[
\mathcal{E} = \int \mathsf{Ctx}
\qquad
\text{for}
\qquad
\mathsf{Ctx} : \mathcal{B}^{op} \to \mathbf{Cat}.
\]

This math is not decorative. It names the exact structural split the repo is
already trying to enforce.

## Base locus

For the first kernel, the base SHALL be the smallest authoritative coordination
substrate needed for governed work.

For issue-oriented transitions, a base locus SHOULD include enough authoritative
state to answer:

- what issue is under discussion,
- what the tracker currently says about it,
- whether readiness/dependency conditions are satisfied,
- whether a live lane already exists,
- what service/runtime state is currently published,
- what receipt history is relevant.

In current repo terms, the base is composed from:

- issue and dependency truth in `bd`,
- live lane state in Tusk runtime state,
- service/backend observations,
- relevant receipt refs.

The base is **not** the workspace.

## Fiber

A fiber over a base locus is the category of admissible local work contexts over
that locus.

For the first kernel, the important fiber object is the **lane context**.
A lane context includes bounded local facts such as:

- `issue_id`
- workspace name/path
- base revision / resolved base commit
- lane status
- handoff revision (when present)
- outcome (when present)
- timestamps and receipt-relevant fields

A fiber object is not merely a folder. It is a lawful local room to work.

## Transition phases

The first kernel has five structural phases:

1. **Base-only**
   - `create_child_issue`
   - `claim_issue`
   - `close_issue`

2. **Fiber entry**
   - `launch_lane`

3. **Fiber internal**
   - `handoff_lane`
   - `finish_lane`

4. **Fiber discharge**
   - `archive_lane`

5. **Service realization**
   - `tracker.ensure`

This taxonomy matters because not every transition is “inside a lane”, and not
all issue mutations are fiber moves.

## Laws

### Law 1 — Projection law

Every live local work context SHALL project to exactly one canonical base locus.

No orphan local worlds.
No live lane without a named governing locus.

For the first kernel, that usually means one live lane projects to one issue.

### Law 2 — Authority split law

The projection target SHALL remain canonical coordination truth.
The local context SHALL remain local work state.

At minimum:

- tracker root remains distinct from checkout root,
- lane records remain distinct from issue status,
- workspace contents remain distinct from tracker truth,
- projections remain distinct from authority.

The tracker-root / checkout-root split is structural law, not optional
ergonomics.

### Law 3 — Lane law

A lane SHALL be treated as an object in a fiber, not as a synonym for issue
lifecycle.

An issue may be `in_progress` with no live lane.
A live lane does not redefine what the issue *means*.

### Law 4 — One-live-lane law

For the first kernel, at most one live lane SHALL exist per issue.

This matches the current runtime’s `no_live_lane` witness for `launch_lane`.
Future concurrency MAY be introduced later, but only by refining the base/fiber
law accordingly.

### Law 5 — Chosen-lift law

`launch_lane` SHALL be treated as the distinguished chosen lift from an
issue-side base locus into an explicit local work context.

In plain language:

- the issue is the canonical locus,
- `launch_lane` chooses the local working room over it,
- that choice must be explicit,
- and it must be recoverable later.

### Law 6 — No implicit fiber-entry law

No other transition may silently create live lane state.

For the first kernel, live lane creation belongs to `launch_lane` and live lane
removal belongs to `archive_lane`.

### Law 7 — Recoverability law

A lawful local context SHOULD let the system recover, at minimum:

- the governing locus,
- the workspace it owns,
- the revision basis it carries,
- the state it is in,
- the next lawful moves,
- the receipts already emitted against it.

If those facts live only in prompts, shell history, or operator memory, the
fiber law is not being satisfied.

### Law 8 — One-wire law

Each live lane SHOULD carry one main development wire.

A good wire declares:

- its input context,
- its expected output artifact,
- its verification boundary,
- its landing or handoff boundary.

This keeps lanes typed and composable instead of becoming bags of ongoing life.

## Examples

### Claim without a lane

A claimed issue is still a base-side fact. Claiming an issue does **not** enter
its fiber.

### Launch as fiber entry

`launch_lane` moves from:

- issue truth in the base

to:

- issue truth plus a specific local work context in the fiber.

### Handoff / finish as internal fiber moves

These transitions mutate the live local context without discharging it.
They keep the lane live.

### Archive as fiber discharge

`archive_lane` removes the live lane record. In the current runtime there is no
persisted live status called `archived`; archive is represented by *absence of
live lane state plus an archive receipt*.

## Result

This spec makes the structural promise of Tusk explicit:

> canonical coordination stays canonical, local work stays local, and the
> relationship between them is explicit enough to recover context from the
> system rather than from the operator’s memory.
