# Tusk Upstream Boundary

## Status

Normative placement note for work that spans `fish`, `kurma`, and `tusk`.

This note exists to keep `tusk` from turning into a second half-compiler with
workflow state bolted onto it.

## Intent

`tusk` should be the operational control plane around realized artifacts and
repo workflow.

It should not become:

- the theory authority,
- the carrier/runtime substrate,
- or the home of theory-specific normalization and validation logic.

Those other roles already have cleaner homes upstream.

## Layering

The intended stack is:

- `fish`: normative meaning, specs, notes, and public doctrinal authority
- `kurma`: `Premath -> KCIR` substrate, theory landings, compiled artifacts,
  and validators
- `tusk`: repo workflow, operator control plane, admission/realization, and
  receipts around realized artifacts

So `tusk` is downstream of theory meaning and downstream of runtime carriage.
It is the external adapter over those surfaces, not the place where they are
defined.

## Ownership Rule

Use this placement rule whenever a new slice could land in more than one repo.

### `fish` owns

- what a theory or protocol means
- normative schemas and law statements
- explanatory and doctrinal notes
- public authority for semantic changes

### `kurma` owns

- carrier rows and internal runtime substrates
- reference binding and mapping gates
- normalization, compilation, and validation of theory-specific artifacts
- public compiled boundaries once those shapes stabilize

### `tusk` owns

- repo-local workflow and operator UX
- verified checks over stable commands and artifacts
- admission, realization, and receipt recording
- CI, publication, deploy, and automation surfaces around already-realized
  artifacts
- generic adapters that invoke stable upstream implementation surfaces

## Placement Test

Ask these questions in order:

1. Does this change define meaning?
   Put it in `fish`.
2. Does it carry, compile, normalize, bind, or validate meaning?
   Put it in `kurma`.
3. Does it operate around already-realized artifacts, repos, or external
   authorities?
   Put it in `tusk`.

If a slice fails the third test, it should not land in `tusk`.

## Kurma To Tusk Contract

`tusk` should consume stable upstream surfaces rather than recreate them.

Good inputs for `tusk`:

- stable `kurma` commands
- compiled artifacts
- witnessable validation results
- publishable payloads
- projection outputs suitable for CI or release workflows

Bad inputs for `tusk` to own directly:

- `Premath` or `KCIR` row definitions
- theory-specific wire or carrier objects
- normalization logic
- reference-binding logic
- theorem or protocol validators
- theory claim or proof vocabularies

## Examples

- changing a `Nerve` law or normative schema belongs in `fish`
- adding a `MorNF_sigma -> kcir.mor_nf` mapping belongs in `kurma`
- defining a new `WCAT` compiled wire boundary belongs in `kurma`
- running a `kurma` validator in CI and turning failures into receipts belongs
  in `tusk`
- publishing a compiled artifact after admitted checks pass belongs in `tusk`

## Contributor Rule

Before starting a new slice, classify it as one of:

- meaning
- carrying meaning
- operating around meaning

Only the third class belongs in `tusk`.

When in doubt, keep theory and runtime semantics out of `tusk` until a stable
upstream surface exists to consume.

## Relationship To Other Tusk Notes

This note is narrower than
[`design/notes/tusk-architecture.md`](../notes/tusk-architecture.md).
That note defines the operational calculus inside `tusk`.

This note is also narrower than
[`design/notes/tusk-transition-carrier.md`](../notes/tusk-transition-carrier.md).
That note defines how `tusk` should carry one local workflow transition once
the repo boundary has already been chosen.
