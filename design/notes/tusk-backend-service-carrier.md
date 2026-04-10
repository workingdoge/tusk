# Tusk Backend Service Carrier

## Status

Normative model note for the first Rust-owned daemon seam in `tuskd`.

## Intent

Name the smallest carried runtime object Rust should own first.

This seam is narrower than the full transition carrier in
[`design/tusk-transition-carrier.md`](./tusk-transition-carrier.md). It covers
only:

- backend ensure,
- live-server adoption,
- and healthy service-record publication.

The goal is to move the failure-prone center out of shell without pretending
the whole daemon has been modeled yet.

## Why This Seam

The recent multi-server fan-out bug was not a generic protocol failure. It was
one narrow runtime failure:

- `tuskd ensure` could observe stale service state,
- race while repairing backend ownership,
- and publish an unhealthy or outdated service record.

That means the first Rust extraction should start exactly there.

The method imported from `kurma` and `nerve` is only this:

- carry the smallest operational seam first,
- stabilize its rows and invariants,
- then let later protocol or lane-state work land above it.

## Relationship To The Transition Carrier

The backend service carrier is a specialization of the more general transition
carrier.

The generic transition carrier says:

`witnesses -> intent -> admission -> realization -> receipts`

The first Rust seam applies that law to one transition family:

- intent kind: `tracker.ensure`
- authority surface: repo-local backend ownership and service publication
- receipt kind: `tracker.ensure`

So this note does not replace the generic carrier note. It picks the first
runtime row set that should become typed and serialized around one stable seam.

## First Stable Rows

The first Rust-owned rows should be:

1. `repo_ref`
2. `service_observation`
3. `backend_observation`
4. `ownership_observation`
5. `ensure_witnesses`
6. `ensure_admission`
7. `service_projection`
8. `ensure_realization`
9. `ensure_receipt`

This is intentionally smaller than a full daemon model.

## Carrier Shape

Prototype shape:

```text
BackendServiceCarrier = {
  repo,
  request,
  current_service?,
  backend,
  ownership,
  witnesses,
  desired_service?,
  admission?,
  realization?,
  receipt?
}
```

This carrier is transition-scoped.

It is not:

- the whole `tuskd` server,
- the generic socket protocol,
- the lane state model,
- or the entire receipt algebra.

## Row Meanings

### `repo`

Stable repo identity and paths:

- canonical repo root
- service key
- repo-local state paths
- host-registry paths
- socket path

### `request`

The invocation-level context:

- request id
- command kind (`ensure`, `status`, or internal ensure-for-serve)
- whether repair authority is allowed

### `current_service`

Observed service publication state:

- current repo-local `service.json`
- current host registry record when present
- mismatch or staleness facts between them

This row is observational only.

### `backend`

Normalized backend facts:

- configured endpoint
- effective port candidate
- live port owner pid
- local runtime pid/port files
- tracker backend `show`, `test`, and `status` snapshots
- current running/healthy summary

This row should capture the facts before any repair or publication decision.

### `ownership`

Runtime ownership facts:

- startup lock holder facts
- service lock holder facts
- whether a live backend can be adopted
- whether this transition must start a backend, adopt one, or refuse repair

This row exists because ownership is part of admission, not just shell control
flow.

### `witnesses`

Derived but explicit witnesses over the observed rows.

At minimum:

- `backend_healthy`
- `service_record_matches_backend`
- `live_backend_adoptable`
- `repair_authorized`
- `service_publication_required`
- `singleflight_held`

These witnesses should be explicit values in Rust, not only implicit branch
conditions.

### `desired_service`

The service record projection the runtime intends to publish if admitted:

- mode (`idle` or `serving`)
- `tuskd` pid when one exists
- backend endpoint
- backend runtime summary
- checked-at timestamp

This row is derived. It is not authoritative until realization commits it.

### `admission`

The ensure-specific decision:

- `healthy_noop`
- `adopt_live_backend`
- `repair_and_start_backend`
- `reject`

Admission should also record the witness classes consulted and the exact reason
for rejection when denied.

### `realization`

The concrete mutations to perform after admission:

- configure tracker backend endpoint if required
- write local backend runtime files if required
- start backend if required
- publish repo-local and host service records
- append the `tracker.ensure` receipt

These steps should be driven by the admitted carrier, not by ad hoc re-probing
between shell branches.

### `receipt`

The resulting evidence:

- receipt kind `tracker.ensure`
- reference to the published service record
- adoption-versus-start result
- backend pid/port actually realized

## Authoritative Versus Derived

The first Rust seam should preserve this split.

Authoritative observations:

- tracker backend `show`, `test`, and `status`
- live port owner facts
- repo-local service record
- host service record
- lock ownership facts

Derived rows:

- ensure witnesses
- desired service projection
- admission result
- realization plan

Rust should own the normalization from authoritative observations into derived
rows. It should not treat already-derived shell JSON as authority.

## Rust Boundary

For this first seam, Rust should own:

- snapshot normalization
- witness derivation
- admission
- realization planning
- service-record serialization and publication
- `tracker.ensure` receipt payload construction

The shell should remain only:

- CLI argument parsing
- environment and path adaptation
- compatibility wrapping around the Rust entrypoint

That keeps the shell as an adapter edge instead of the daemon's semantic
center.

## Initial Delegation Surface

The first scaffolded boundary should stay explicit and small.

- the flake exports a dedicated `tuskd-core` package
- the shell wrapper exports `TUSKD_CORE_BIN`
- `tuskd core-seam` delegates directly into the Rust binary

That gives the repo one real shell-to-Rust seam before any runtime logic is
ported.

## Out Of Scope For This Seam

Do not pull these into the first Rust-owned carrier:

- lane launch, handoff, finish, or archive modeling
- workspace creation semantics
- socket protocol extraction
- generic receipt-log or lane-state extraction
- public wire schemas
- `Premath -> KCIR` doctrine as implementation cargo

Those may land later, but they should depend on this seam instead of widening
it now.

## Immediate Consequence

`tusk-asy.8.3.2` should scaffold the Rust crate and shell delegation seam
around this carrier shape, and `tusk-asy.8.3.3` should port only the
`ensure/adopt/publish` path against it.
