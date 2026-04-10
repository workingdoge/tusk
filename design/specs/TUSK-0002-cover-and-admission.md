# TUSK-0002 — Cover / Admission

## Status

Draft.

Depends on `TUSK-0000` and `TUSK-0001`.

## Purpose

Define how a proposal becomes runnable.

The goal is to replace hidden lore and operator memory with explicit witness
families that are locally sufficient for admission.

## Phase model

The governed kernel has four relevant phases:

1. **prepare** — build the carried object for one proposal
2. **admit** — decide whether the proposal may run
3. **apply** — perform the authoritative mutation path
4. **project** — refresh the read-side view

These phases SHALL remain distinct.

## Proposal

A proposal is a client-staged request for one governed transition.

A proposal SHALL name:

- transition kind,
- payload,
- request identity,
- client role or equivalent origin.

A proposal is never authority by itself.

## Witness record

A witness record is the explicit set of authoritative observations and derived
checks relevant to one proposal.

Witnesses SHALL remain explicit. They SHALL NOT be collapsed into one Boolean.

Examples already present in the current runtime include:

- `issue_exists`
- `issue_ready`
- `issue_in_progress`
- `no_live_lane`
- `base_rev_resolves`
- `workspace_absent`
- `lane_handoffable`
- `lane_finishable`
- `lane_finished`
- `workspace_removed`

## Cover basis

Every governed transition SHALL define a **cover basis**: the named witness
family that is sufficient for admission.

A cover basis is:

- local,
- explicit,
- inspectable,
- and minimal for the transition at hand.

A cover basis is **not** “all possible facts”.

Concrete per-transition bases are specified in `TUSK-0004`.

## Envelope

The envelope binds:

- one proposal,
- one repo identity,
- one authoritative witness record,
- one authority context,
- and any relevant prior receipts or state refs.

This is the carried kernel object that survives the gap between request and
authority.

## Admission classes

The current kernel uses the classes:

- `structural`
- `authority`
- `runtime`
- `replay`

These classes SHALL retain their meaning.

### Structural

Structural admission answers whether the transition is well-shaped relative to
current tracker, lane, workspace, and payload state.

### Authority

Authority admission answers whether the kernel is permitted to make the
transition.

### Runtime

Runtime admission answers whether current service/backend conditions are
sufficiently observed and healthy for the transition to proceed.

### Replay

Replay admission answers whether the requested move is already discharged,
invalidated by prior state, or otherwise non-fresh.

## Laws

### Law 1 — Sufficiency law

Admission SHALL depend on the explicit cover basis, not on ambient side
knowledge.

If a transition depends on a fact, that fact SHALL either:

- appear as an explicit witness in the cover basis, or
- be named as an explicit out-of-scope assumption.

Hidden preconditions are a spec bug.

### Law 2 — Determinacy law

For a given proposal, witness record, and authority context, admission SHOULD be
explainable entirely in terms of the explicit witnesses.

If the operator cannot tell *which* witness failed, the admission surface is too
soft.

### Law 3 — Negative-case law

When admission fails, the kernel SHALL return an explicit obstruction rather
than a vague rejection.

An obstruction SHOULD identify:

- the transition kind,
- the failed witness or reason,
- the relevant witness details or refs,
- the admission class involved.

### Law 4 — Application separation law

Witness gathering and admission SHALL remain distinct from application.

A structurally well-shaped proposal is not yet applied.
An admitted transition is not yet projected.
A projection is not admission.

### Law 5 — Projection humility law

A projection MAY recommend a move. It SHALL NOT count as a witness or admission
result by itself.

## Result

This spec turns “do we know enough to do this?” into a local, inspectable
question.

The concrete answer for each transition is given in `TUSK-0004` as:

- witness basis,
- admitted-iff condition,
- success postconditions,
- restoration behavior,
- primary obstructions.
