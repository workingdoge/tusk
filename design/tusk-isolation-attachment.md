# Tusk Isolation Attachment

## Status

Decision note for local container and microvm isolation surfaces beneath
`tusk`'s operational spine.

## Intent

`tusk` should support bounded local isolation when that isolation helps one
issue-scoped lane or one admitted realization run inside a controlled local
context and then reattach to canonical repo truth through explicit receipts.

Isolation is therefore not a new semantic center.
It is an operational attachment beneath the existing spine:

`witness -> intent -> admission -> executor/driver -> receipt`

The important rule is:

- canonical tracker state remains the base
- the issue lane or admitted realization remains the local work context
- the isolation surface supplies a runtime constructor plus one bounded
  execution path
- and reattachment still happens through visible repo state plus receipt trail

## Why This Belongs In `tusk`

Shared local isolation belongs in `tusk` only to the extent that it is:

- repo-local operational infrastructure
- receipt-bearing and admission-aware
- reusable across more than one downstream proof

It does not belong in `tusk` as:

- a universal VM or container framework
- app-specific bootstrap logic
- funded runtime policy
- or hidden host authority

That boundary keeps `tusk` on the operator-control side of the problem rather
than absorbing generic runtime carriage or downstream product setup.

## Ownership Rule

### `tusk` owns

- the normalized request shape for one bounded isolated run
- the binding from lane or realization context into that request
- admission checks for the repo-local authority boundary
- receipt normalization and reattachment rules
- operator projections over runtime attempts and outcomes

### isolation adapters own

- engine-specific runtime construction for a chosen substrate such as a
  container or microvm
- workspace mount wiring
- image, rootfs, or vm artifact selection
- host-local process and lifecycle mechanics
- platform-specific implementation details needed to start and observe the run

### downstream or separate contexts own

- app-specific payloads such as a Hermes bootstrap command
- provider, model, wallet, or funded operator policy
- credentials and secret material beyond the generic projection boundary
- product-specific state inside the guest runtime

## Two Attachment Sites

There are two valid places for isolation to attach.

### 1. Lane-scoped local isolation

This is the first proving path.

Use it when the goal is:

- probe one runtime locally
- run one bounded agent or installer inside an isolated workspace
- and learn what constructor, mount, env, network, and receipt fields need to
  stabilize

Authority path:

- issue claim
- lane launch
- local isolation run attached to that lane
- receipt append
- handoff or follow-up work

This path stays close to the current `tuskd` workflow and does not require the
repo to promote the runtime immediately into a flake-wide executor family.

### 2. Admitted realization isolation

Use this only once the runtime constructor is stable enough to be reused as a
real executor surface.

Authority path:

- verified witnesses
- declared intent
- admission
- realization bound to a local isolated executor
- receipt append

This is where a future `local-container` or `local-microvm` executor family
would belong.

## First Shared Contract

The first reusable contract should stay small.

An isolation attachment needs these normalized fields:

- `runId`
  Stable id for one isolated runtime attempt.
- `source`
  The attached source context:
  - issue id
  - lane id or workspace path
  - and optionally one realization id when the run is effect-bound
- `runtime`
  The selected constructor identity:
  - `kind = container | microvm`
  - `constructorId`
  - `profileId`
- `command`
  The explicit command or entrypoint to run.
- `mounts`
  The declared host-to-guest bindings, especially checkout, scratch, and
  receipt sinks.
- `environmentPolicy`
  Which environment values may cross the boundary.
- `networkPolicy`
  Whether the run is offline, loopback-only, or networked by explicit choice.
- `inputs`
  Optional witness refs, artifacts, or files required by the run.
- `receipt`
  The expected receipt family and sink.
- `reattach`
  How the run may rejoin shared truth:
  - visible revision
  - declared artifact path
  - or receipt-only when no repo mutation is allowed

The important property is that the constructor receives one normalized request
shape instead of ambient host authority plus ad hoc shell flags.

## Admission Questions

The first admission boundary should answer at least:

- does the source lane or realization exist?
- is the selected runtime profile declared and available on this host?
- are the requested mounts allowed for this profile?
- is the environment projection allowed?
- is the network mode allowed?
- does the run have a receipt sink and reattachment mode?

This is still narrower than a full multi-host scheduler.
It is only the local authority boundary needed to keep runtime probes from
escaping the existing control plane.

## Receipt And Reattachment

An isolation receipt should record at least:

- `runId`
- source issue and lane or realization id
- runtime kind, constructor id, and profile id
- normalized command
- mount and network summary
- start and end time
- terminal outcome
- produced artifact refs or visible revision when one exists
- enough context to replay operator reasoning without replaying the runtime

The key rule is:

local success is not canonical completion.

A container or microvm run may finish successfully while the issue remains
open, the lane remains in handoff, or the resulting artifact still requires
review. The receipt proves that the run happened. It does not collapse directly
into issue closure.

## First Hermes-Probe Consequence

For the later Hermes work, the first slice should be:

- one lane-scoped local isolation probe
- one declared runtime profile
- one explicit command path for the Hermes installer or follow-up probe
- and one receipt family that reports what guest context actually ran

It should not start as:

- a general agent-runtime framework
- a permanent multi-guest orchestration layer
- or a claim that every isolated run must already be modeled as a reusable
  flake executor

If that first probe repeats cleanly across hosts and repos, then promotion into
a first-class executor family becomes justified.

## Recommendation

Proceed as if:

- shared isolation in `tusk` means normalized local runtime attachment, not
  generic virtualization ownership
- the first proof is lane-scoped and receipt-bearing
- promotion to a reusable executor family is a second step
- and Hermes-specific payload, model policy, and credentials stay outside the
  `tusk` kernel
