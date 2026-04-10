# Tusk Upstream Kernel Recast

## Status

Normative recast note for building `tusk` on upstream `Premath`, `Nerve`, and
`WCAT` crate surfaces.

## Intent

`tusk` now has enough local workflow and development architecture to stop
growing a parallel ad hoc kernel in `tuskd-core`.

The next step is not to move `Premath`, `Nerve`, or `WCAT` into `tusk`.
The next step is to implement or stabilize those upstream crate surfaces and
then recast `tusk` onto them as the first serious downstream operational
runtime.

This note exists to make that move explicit before more local typed-state work
lands without an upstream map.

## Different Contexts

The current work is no longer happening inside one undifferentiated context.
We are crossing several contexts, and each one should keep its own authority.

### 1. Meaning Context

This is the `fish` side.

It owns:

- normative meaning
- law statements
- semantic doctrine
- public authority for what a thing means

This context should not be rebuilt inside `tusk`.

### 2. Carriage Context

This is the `kurma` side, including the crate surfaces that should carry the
reusable method:

- `Premath` for row and shape discipline
- `Nerve` for the smallest carried seam
- `WCAT` for proposal, runtime, receipt, and projection boundaries

This context owns carrying, compiling, binding, validating, or publishing
stable runtime-facing object shapes.

### 3. Governed Runtime Context

This is the `tusk` side.

It owns:

- repo-local workflow
- operator control plane
- witness gathering over stable upstream artifacts and local repo state
- admission and application around realized artifacts
- receipt emission and projection refresh

This context should instantiate upstream rows with `tusk`'s local domain
objects rather than redefine the kernel each time.

### 4. Projection Context

This is the operator-facing read surface:

- `board_status`
- `operator_snapshot`
- `receipts_status`
- issue inspection
- UI and CLI views

Projection is downstream of authoritative runtime state.
It must not quietly become the authority.

## Upstream Foundation

The upstream crate stack should be read as layered method.

### `Premath`

`Premath` should provide the row and shape discipline.

For `tusk`, that means naming stable row families such as:

- proposal rows
- witness rows
- authority-context rows
- admission rows
- application rows
- receipt rows
- projection rows

### `Nerve`

`Nerve` should provide the smallest-carried-seam discipline.

For `tusk`, that means:

- carrying one stable kernel object per governed transition
- keeping admission distinct from application
- preserving explicit witnesses
- refusing to let shell order masquerade as authority

### `WCAT`

`WCAT` should provide the act/runtime/projection boundary.

For `tusk`, that means keeping a stable distinction between:

- proposal-side requests
- runtime-side admitted executions
- authoritative receipts
- reviewable projections

`WCAT` is especially useful once `tusk` has more than one client surface.
`codex`, `tusk-ui`, and future runtimes can then all be proposal-side clients
without becoming the authority edge themselves.

## Ownership Rule

The ownership split stays:

- `fish` defines meaning
- `kurma` owns `Premath`/`Nerve`/`WCAT` crate surfaces and runtime carriage
- `tusk` instantiates those surfaces for repo workflow and operations

So the phrase "build `tusk` on those crates" is correct.
The phrase "move those crates into `tusk`" is not.

## Generic To Local Row Map

The first useful mapping is:

| Upstream row | `tusk` instantiation |
| --- | --- |
| `Proposal` | `claim_issue`, `close_issue`, `launch_lane`, `handoff_lane`, `finish_lane`, `archive_lane`, `tracker.ensure` |
| `WitnessRecord` | tracker, service, lane, workspace, backend, and authority observations plus derived checks |
| `Envelope` | repo identity + one proposal + explicit witnesses + prior receipts + authority context |
| `AdmittedExecution` | an admitted lane or service transition with execution identity |
| `Application` | tracker mutation, workspace mutation, lane-state write, service publication, receipt append |
| `Receipt` | `tracker.ensure`, `lane.launch`, `lane.handoff`, `lane.finish`, `lane.archive`, `lane.complete`, `land.main` |
| `Projection` | `board_status`, `operator_snapshot`, `receipts_status`, issue inspection, UI-facing read models |

The first `tusk`-local rows worth making explicit are:

- `RepoRef`
- `IssueSnapshot`
- `LaneRecord`
- `WorkspaceObservation`
- `ServiceObservation`
- `BackendObservation`
- `AuthorityContext`
- `BoardProjection`
- `OperatorProjection`

These rows are local to `tusk`.
They should satisfy upstream interfaces rather than replace them.

## First Recast Slice

The first downstream recast target should be `tracker.ensure`.

Reasons:

- it is already identified as the smallest stable Rust-owned seam
- it has a narrow authority surface
- it touches service publication, backend health, and receipts without dragging
  the full lane lifecycle into the first move
- it is already documented as a carried seam in
  `design/tusk-backend-service-carrier.md`

So the first implementation sequence should be:

1. stabilize the upstream row interfaces
2. define `tusk`'s `tracker.ensure` row instantiation
3. recast the backend service carrier onto those rows
4. keep heterogeneous receipt detail payloads loose until the seam itself is
   stable

Only after that should lane-state and operator-projection recasts follow.

## Multi-Lane Development As Wires

For this next phase, a lane should be read as more than "another workspace".

If category-theory language is helpful, treat a lane as a development wire:

- it has a source context
- it has a target context
- it carries one bounded artifact across that boundary
- and it should compose with other lanes only through declared interfaces

The workspace is only the local staging area.
The wire is the contract.

### What The Wire Carries

A good lane wire should declare:

- the input context it assumes
- the output artifact it produces
- the verification that makes the output admissible
- the receipt or projection that makes the result consumable downstream

Examples:

- an upstream crate lane carries a row/interface surface from carriage context
  into a publishable crate boundary
- a `tuskd-core` recast lane carries that boundary into one governed runtime
  seam such as `tracker.ensure`
- a projection lane carries typed runtime results into UI-facing projections

### Why This Matters

Without explicit wires, multiple lanes collapse into:

- file-based parallelism
- hidden assumptions
- rebases as coordination
- and accidental context leaks

With explicit wires, multiple lanes can instead compose through:

- issue dependencies
- stable typed interfaces
- receipts
- and projections that downstream lanes can consume without guessing

## Effective Multi-Lane Development Rules

The practical rules should be:

1. Split lanes by context boundary, not by file adjacency.
2. Prefer one wire per lane: one input contract, one output artifact, one main
   verification boundary.
3. Let upstream lanes land crate surfaces first; let `tusk` lanes consume those
   surfaces second.
4. Use tracker dependencies as the wiring graph between lanes.
5. Treat receipts and projections as the handoff artifacts between runtime and
   operator lanes.
6. Keep the coordinator in the context-composition role; workers should not
   invent new wires while implementing an existing one.

## First Lane Stack

The first useful lane stack for this recast should be:

1. upstream crate-surface lane
   Output: stable `Premath` / `Nerve` / `WCAT` interfaces needed by `tusk`
2. `tracker.ensure` recast lane
   Output: typed backend service carrier instantiated on the upstream rows
3. lane-state recast lane
   Output: typed `LaneRecord` and lane transition application path
4. projection lane
   Output: typed board/operator projections over the recast runtime state
5. integration lane
   Output: end-to-end verification and cleanup over the composed seams

That stack composes cleanly because each lane consumes a prior wire rather than
editing the whole control plane in parallel.

## Final Read

The development architecture is no longer the blocker.
It is now strong enough to host the original abstractions.

The next discipline is therefore:

- implement or stabilize the upstream crate surfaces
- recast `tusk` onto them seam by seam
- and run multiple lanes as explicit wires between contexts rather than as
  loosely related workspaces

That is the path that lets `tusk` become a serious downstream operational
runtime without confusing repo workflow with the upstream kernel itself.
