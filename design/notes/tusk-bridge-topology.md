# Tusk Bridge Topology

This note records the current bridge placement and conformance boundary for
`tusk`.

It is not Tusk kernel law.
It explains how the imported bridge adjunct contract and the Rust adapter
surface are organized today, and where follow-on work belongs if the bridge
surface grows.

## Current split

The bridge surface in this repo has two Tusk-owned pieces:

- the adjunct contract family under `design/adjuncts/bridge-adapter/`
- the first Rust adapter/runtime surface under `crates/tusk-bridge-adapter/`

The adjunct contract defines the external request, authoritative provider
results, assembled policy input, decision envelope, audit record, and
mode/admin objects. The Rust crate implements a local adapter surface over that
contract.

This is a `tusk` adapter seam, not Tusk kernel law.

## Ownership

### `tusk`

`tusk` owns:

- the repo-owned adjunct bridge contract as staged in
  `design/adjuncts/bridge-adapter/`
- the generic adapter/runtime surface in `crates/tusk-bridge-adapter/`
- fixture-driven conformance against the imported schemas and examples
- local operator-facing assembly/API/admin wiring that stays generic shared
  operational infrastructure

### `fish`

`fish` should own the bridge surface only if it becomes durable public doctrine,
meaning, or law instead of a repo-local adjunct contract.

Examples:

- public bridge semantics
- normative bridge policy doctrine
- law that should outlive the current repo-owned adapter bundle

### `kurma`

`kurma` should own reusable carried method if the current adapter logic
generalizes beyond this one adapter seam.

Examples:

- reusable canonicalization method
- reusable schema-validation or assembly crates
- carried validation/projection machinery that is broader than bridge alone

Do not leave that kind of reusable carriage trapped inside
`crates/tusk-bridge-adapter/` if it becomes a genuine shared method surface.

### downstream repo

Downstream repos should own live bridge runtime behavior that depends on real
operator authority, provider policy, or funded runtime state.

Examples:

- provider-specific resolution and deployment wiring
- operator secrets and environment bindings
- funded runtime behavior
- product-specific bridge policy or ingest behavior
- the first live proof consumer

## Conformance boundary

The Tusk-side conformance boundary is:

- adjunct contract conformance:
  preserve imported schemas/examples unless there is an intentional reviewed
  divergence, and test the adapter against those fixtures
- runtime adapter conformance:
  verify assembly, decision shaping, and local API/admin behavior against the
  adjunct examples and local tests

The Tusk-side conformance boundary is not:

- a live provider-resolution proof
- operator-secret custody
- funded bridge runtime operations
- multi-consumer product adoption

Those belong in downstream proof or product lanes.

## Sequencing rule

Use this order when the bridge surface grows:

1. keep the adjunct contract and generic adapter seam honest in `tusk`
2. prove one live consumer downstream
3. only then extract reusable carriage to `kurma` or elevate doctrine to
   `fish` if the proof shows that split is real

Do not collapse contract staging, runtime adapter growth, and downstream proof
into one lane.

## Working rule

When bridge work is proposed in `tusk`, ask:

- is this still an adjunct contract or generic adapter seam?
- is this actually reusable carriage?
- is this really downstream provider/policy/secrets work?

If the answer changes, split the lane instead of widening `tusk`.
