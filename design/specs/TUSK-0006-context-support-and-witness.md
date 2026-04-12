# TUSK-0006 — Context Support And Witness Bundle

## Status

Draft.

Depends on `TUSK-0000` through `TUSK-0005`.

## Purpose

Define the first kernel-facing object model for plan-local support, compatible
concern sections, epoch binding, and witness-backed apply.

This spec does **not** replace the existing proposal/admission/receipt shape.
It refines how the kernel should package the local facts that make a bounded
move admissible.

## Core claim

The kernel SHALL be readable as:

`proposal -> support -> concern sections -> witness bundle -> apply token -> receipt`

The current first kernel MAY instantiate this shape in degenerate form.
It is still the right law.

## Context support

A **context support** is the sparse set of local contexts and overlaps that are
jointly relevant to one proposal or one tightly bounded plan.

It is not a standing world model.
It is not a global graph of everything Tusk has ever heard about.

## Objects

### ContextVertex

A `ContextVertex` names one local authority or admissibility region.

It SHALL carry at least:

- stable `id`
- `kind`
- `proposal_ref` or equivalent governing reference
- `authority_surface`
- `trust_class`
- `facts_ref` or equivalent local-state reference

Examples of `kind`:

- `tracker.base`
- `lane.context`
- `workspace.checkout`
- `service.runtime`
- `approval.surface`
- `audit.sink`
- `untrusted.content`

### SupportSimplex

A `SupportSimplex` names one jointly relevant overlap between context vertices.

It SHALL carry at least:

- stable `id`
- `proposal_ref`
- non-empty ordered `vertex_ids`
- `overlap_kind`
- any explicit `restriction_refs`

A support simplex exists because the overlap constrains the move, not because
all vertices happen to exist in the same universe.

### ConcernSection

A `ConcernSection` is one local admissibility or restriction record attached to
either:

- a `ContextVertex`, or
- a `SupportSimplex`.

It SHALL carry at least:

- stable `id`
- `concern_kind`
- `carrier_ref`
- `facts_ref`
- `freshness_ref`
- `status`

Examples of `concern_kind`:

- `authority`
- `approval`
- `provenance`
- `secrecy`
- `budget`
- `audit`
- `revocation`

### WitnessBundle

A `WitnessBundle` is the compatible bundle of local sections sufficient to
support one bounded move.

It SHALL carry at least:

- stable `id`
- `proposal_ref`
- `support_ref`
- `section_refs`
- `epoch_binding`
- `admission_basis`
- `compatibility_result`

If compatibility fails, the kernel SHALL return explicit obstruction rather
than silently collapsing the sections into one Boolean.

### EpochBinding

An `EpochBinding` is the temporal boundary under which the witness was judged
admissible.

It SHALL carry at least:

- stable `id`
- `observed_at`
- `fresh_until` or equivalent freshness boundary
- `revocation_refs`
- `approval_window` when relevant
- `lease_window` when relevant

### ApplyToken

An `ApplyToken` is the bounded execution authorization derived from an admitted
`WitnessBundle`.

It SHALL carry at least:

- stable `id`
- `proposal_ref`
- `witness_ref`
- `transition_kind`
- `executor_ref` when relevant
- `driver_ref` when relevant
- `epoch_binding`
- `scope`

An apply token is authority for one bounded move. It is not a standing grant.

### Receipt

A successful apply SHALL emit a receipt that preserves the execution boundary.

The receipt SHOULD retain refs to at least:

- the governing proposal
- the admitted witness bundle
- the epoch binding
- the apply token or equivalent execution handle

## Laws

### Law 1 — Plan-local support law

Every `SupportSimplex` SHALL be induced by one explicit proposal or one bounded
plan.

No support object may float free of a governing move.

### Law 2 — Sparsity law

The kernel SHALL materialize only the contexts and overlaps jointly relevant to
the nominated move.

Tusk SHALL NOT require a global context graph as a precondition for local
admission.

### Law 3 — Local-origin law

Every `ConcernSection` SHALL originate on a vertex or simplex.

Global admissibility may be assembled from local sections.
It SHALL NOT be treated as unexplained ambient truth.

### Law 4 — Gluing law

A `WitnessBundle` SHALL identify the exact support object and exact section
refs whose compatibility makes the move admissible.

No witness without explicit compatible sections.

### Law 5 — Temporal binding law

A `WitnessBundle` SHALL include an `EpochBinding`.

If freshness, approval validity, lease validity, or revocation state is
relevant to the move, those facts SHALL be part of the epoch binding rather
than implicit assumptions.

### Law 6 — Apply boundary law

No effect without an admitted witness bundle.

No admitted witness bundle without explicit support.

No apply token outside the temporal boundary carried by the witness.

### Law 7 — Degenerate first-kernel law

The first kernel MAY realize support in degenerate form, such as:

- one base locus only,
- one base locus plus one lane context,
- one service context plus one receipt sink.

This still counts as lawful support if the same object boundaries and laws are
preserved.

### Law 8 — Projection naming law

Operator projections MAY rename the internal objects into plainer terms such as
`contexts`, `overlaps`, `checks`, and `witness`.

They SHALL preserve enough references to recover the underlying kernel objects.

## Relation to prior specs

This spec refines earlier kernel objects rather than replacing them.

- It refines the `witness record` and `envelope` in `TUSK-0002`.
- It strengthens the descent evidence interpretation in `TUSK-0003` by making
  witness compatibility and epoch binding explicit.
- It gives future `TUSK-0004` transition contracts a stable way to name local
  support and witness bundles.
- It gives `TUSK-0005` projections a stable basis for operator-facing
  `missing_witnesses`, `contexts`, and `closure_eligible` fields.

## Minimal reading for the current kernel

For the first issue-oriented transition family, the kernel can be read
conservatively:

- the proposal is one transition request
- the support usually includes one issue-side base locus and any relevant lane,
  workspace, service, or receipt context
- concern sections include the current explicit witness facts already emitted by
  the runtime
- the witness bundle is the compatible admitted subset of those sections
- the apply token is the bounded authorization to mutate tracker, lane, or
  service state

This spec therefore names a stronger shape without demanding an immediate full
runtime rewrite.

## Result

The kernel now has a stricter invariant:

> no effect without witness, no witness without glued sections, no glued
> sections outside the plan-local support.
