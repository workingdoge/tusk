# Tusk Transition Carrier

## Status

Normative workflow-law note for the first-class transition carrier in `tusk`.

This note exists to stop `tuskd` from treating control-plane authority as shell
execution order plus ad hoc JSON updates. The goal is to define the smallest
stable runtime artifact that can carry one control-plane transition from
witness collection through receipt emission.

## Intent

`tusk` needs one primitive carried runtime object for local workflow
transitions.

The semantic spine already named elsewhere in the design set remains:

`witnesses -> intents -> admission -> realization -> receipts`

This note says what object carries that spine for the existing repo-local
control plane.

## Layering

The intended stack is:

- `fish`: concrete domain instances and consuming repos
- `kurma`: internal carrier/kernel substrate
- `tusk`: local operational runtime over repo-scoped workflow state
- `WCAT`: public compiled action/wire boundary above the local runtime

So `tusk` is not the deepest kernel and not the public protocol boundary.
It is the local runtime that:

- gathers witnesses from repo-local state,
- forms and admits transitions,
- realizes admitted transitions against local authorities,
- and emits receipts.

This note intentionally imports the method from `nerve` and `kurma`, not the
whole theorem vocabulary. The important lesson is:

- carry the smallest stable runtime seam first,
- keep downstream public/proof/claim surfaces above that seam,
- and do not confuse projections with authority.

## Why This Seam Comes First

Today `tusk` already has:

- issue truth in `bd`,
- lane truth in `.beads/tuskd/lanes.json`,
- service truth in `.beads/tuskd/service.json`,
- receipt truth in `.beads/tuskd/receipts.jsonl`,
- and imperative transitions in `tuskd`.

What it does not yet have is a first-class carried transition object.

That is the missing seam behind the current failures:

- concurrent clients can race on shared state,
- partial failures can leave orphaned workspaces,
- and admission is duplicated across imperative shell branches instead of being
  carried as an explicit object.

## Primitive Carrier

The primitive carried runtime object in `tusk` is the transition carrier.

Prototype shape:

```text
TransitionCarrier = {
  repo,
  tracker,
  service,
  issue?,
  lane?,
  workspace?,
  witnesses,
  intent,
  admission?,
  realization?,
  receipts
}
```

The carrier is repo-scoped and transition-scoped.

It is not:

- the issue itself,
- the lane itself,
- the service record itself,
- or the receipt log itself.

It is the object that carries one proposed or realized change over those
authorities.

## Authority Boundaries

The carrier does not replace existing authorities.

It must preserve this split:

- `bd` owns issue truth and dependency edges
- `tusk` owns service state, lane state, and transition receipts
- workspace existence is observed from the filesystem and `jj`
- the carrier may hold snapshots or references to those authorities, but does
  not become a new hidden source of truth

Commands remain projections over authoritative objects, not truth by
themselves.

## Carrier Fields

### `repo`

Repo-scoped identity and context:

- canonical repo root
- service key
- expected workspace root
- current clock / request identity

### `tracker`

Issue-side snapshots from `bd`:

- issue record when one exists
- dependency/readiness summary when relevant
- tracker summary needed for the transition

### `service`

Shared runtime snapshot:

- service record
- backend health
- endpoint and runtime facts
- holder role if the transition depends on coordinator-versus-worker authority

### `lane`

Lane-side snapshot when relevant:

- current lane record
- stored lane status
- previous handoff/finish/archive data

### `workspace`

Workspace facts when relevant:

- intended workspace name/path
- existence or absence
- resolved base revision or handoff revision
- whether the workspace observation is live, stale, or removed

### `witnesses`

The carrier should keep explicit witnesses rather than only derived booleans.

At minimum:

- issue-status witness
- dependency/readiness witness
- lane-status witness
- workspace-fact witness
- service-health witness
- authority/capability witness
- prior-receipt or idempotence witness

### `intent`

The requested control-plane action:

- `claim_issue`
- `launch_lane`
- `handoff_lane`
- `finish_lane`
- `archive_lane`
- `close_issue`

The intent is a proposal, not authority.

### `admission`

Admission is the explicit decision over the carried witnesses.

It should record:

- admitted or rejected
- rejection reason when denied
- which witness classes were consulted
- whether repair authority was exercised

### `realization`

The concrete mutations or externalized effects to apply if admitted.

Examples:

- `bd update --claim`
- `jj workspace add`
- lane-state upsert
- service-record update
- receipt append

### `receipts`

The receipts linked to the transition:

- previous receipt references for replay/idempotence
- receipt kind to emit
- emitted receipt reference after success

Receipts are evidence of realization, not current truth.

## Transition Law

Every `tusk` control-plane action should follow this law:

1. collect the authoritative snapshots needed for one transition carrier
2. derive explicit witnesses from those snapshots and local facts
3. construct one intent over those witnesses
4. evaluate admission against structure, authority, and runtime policy
5. if admitted, realize the transition through one serialized mutation path
6. emit a receipt that records the realized transition
7. refresh the relevant projections from authoritative state

A conforming runtime MUST keep admission distinct from realization.

A conforming runtime MUST also serialize or otherwise make atomic any carrier
realization that mutates shared lane/service/receipt state.

## Admission Classes

The admission boundary should distinguish at least four classes.

### 1. Structural admission

Examples:

- does the issue exist?
- is the issue in the right status?
- does a lane record already exist?
- does the base revision resolve?
- is the workspace present or absent as required?

### 2. Authority admission

Examples:

- may this caller claim or close the issue?
- may this caller repair shared service state?
- may this caller archive a lane?

### 3. Runtime admission

Examples:

- is the tracker backend healthy?
- is repair required before the transition may proceed?
- is the transition blocked on stale workspace or stale service state?

### 4. Replay/idempotence admission

Examples:

- has this transition already happened?
- would replay duplicate a lane launch or archive?
- is there already a terminal receipt that makes the transition invalid?

## Existing Action Families

The current `tuskd` action surface should be read through the carrier law.

### `claim_issue`

Preconditions:

- issue exists
- issue is ready/claimable
- no conflicting terminal issue state exists

Postconditions:

- issue is `in_progress` in `bd`
- `issue.claim` receipt exists
- board projection reflects claimed ownership

### `launch_lane`

Preconditions:

- issue exists and is already claimed
- no conflicting live lane exists for that issue
- base revision resolves
- workspace path is absent

Postconditions:

- workspace exists
- lane record exists with status `launched`
- `lane.launch` receipt exists

### `handoff_lane`

Preconditions:

- lane record exists
- handoff revision resolves
- lane is not archived

Postconditions:

- lane status is `handoff`
- handoff revision and timestamp are recorded
- `lane.handoff` receipt exists

### `finish_lane`

Preconditions:

- lane record exists
- lane is not archived
- outcome is explicit

Postconditions:

- lane status is `finished`
- outcome and timestamp are recorded
- `lane.finish` receipt exists

### `archive_lane`

Preconditions:

- lane record exists
- lane is already `finished`
- workspace is gone

Postconditions:

- lane is removed from live lane state
- `lane.archive` receipt exists

### `close_issue`

Preconditions:

- issue exists
- close reason is explicit
- no live lane remains unless closure is part of one admitted combined transition

Postconditions:

- issue is `closed` in `bd`
- `issue.close` receipt exists

That final precondition is intentionally stronger than the current shell
implementation. It names the admission rule the runtime should converge on.

## Out Of Scope For The First Seam

The first carried seam in `tusk` should not try to absorb:

- `kurma` kernel carrier laws
- `WCAT` public action and wire schemas
- theorem/proof/attestation layers
- remote federation/control-plane distribution
- richer agent planning or task decomposition languages

Those may later compile from or sit above this seam, but they should not
replace it.

## Immediate Consequences

This note implies the following implementation order.

1. define the transition carrier and admission law
2. replace ad hoc per-command shell mutation logic with one serialized
   transition evaluator
3. add concurrency and rollback tests at the service boundary
4. only then consider a public `WCAT`-style action surface over the stabilized
   runtime law

## Recommendation

Proceed as if:

- `tusk` is the local operational runtime layer,
- the transition carrier is the primitive carried runtime object,
- witnesses remain explicit,
- admission remains distinct from realization,
- receipts remain evidence rather than truth,
- and later public/proof/catalog layers should compile from this seam rather
  than replacing it.
