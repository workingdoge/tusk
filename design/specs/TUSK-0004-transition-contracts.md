# TUSK-0004 — Transition Contracts

## Status

Draft.

Depends on `TUSK-0000` through `TUSK-0003`.

## Purpose

Bind the kernel laws to concrete governed transitions.

This spec is the engineering surface. Each transition gets an exact contract
that is explicit enough to drive implementation, tests, receipts, and UI
behavior.

See `TUSK-0004-conformance-matrix.md` for the current implementation and test
mapping of this contract surface.

## Contract schema

Every governed transition SHOULD answer the following questions:

- **phase** — is this base-only, fiber-entry, fiber-internal, fiber-discharge,
  or service realization?
- **payload** — what client input is required?
- **witness basis** — what named witnesses does admission depend on?
- **admitted iff** — what must be true for the transition to run?
- **success postconditions** — what must be true after successful application?
- **receipt family** — what authoritative receipt is emitted?
- **restoration behavior** — how is partial failure handled?
- **primary obstructions** — what should rejection or failure make legible?

The contracts below are aligned to the current runtime and its current witness
names.

## State sketch

The lane-side state machine for the first kernel is:

```text
no live lane --launch_lane--> launched
launched --handoff_lane--> handoff
handoff --handoff_lane--> handoff
launched|handoff --finish_lane--> finished
finished --archive_lane--> no live lane
```

`claim_issue` and `close_issue` are base-side tracker transitions.
`tracker.ensure` is a service realization transition.

## Naming note

The runtime internally parses `ensure`, while the emitted receipt and user-facing
family are `tracker.ensure`. This spec uses `tracker.ensure` for clarity.

## Contracts

### `create_child_issue`

- **Phase:** base-only
- **Payload:** `parent_id`, `title`, optional `description`, optional
  `issue_type`, optional `priority`, optional `labels`
- **Witness basis:** `parent_id`, `title`, `parent_exists`, `parent_open`,
  `child_issue_id`
- **Admission classes:** `structural`, `authority`, `runtime`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - one child issue has been created under the named parent,
  - reread issue identity matches creation metadata,
  - board projection has been refreshed
- **Receipt family:** `issue.create`
- **Restoration behavior:** no generalized rollback today; failure after tracker
  create is surfaced as tracker failure or identity mismatch
- **Primary obstructions:** missing `parent_id`, missing `title`, missing or
  closed parent, child id allocation failure

### `claim_issue`

- **Phase:** base-only
- **Payload:** `issue_id`
- **Witness basis:** `issue_id`, `issue_exists`, `issue_status_open`,
  `issue_ready`
- **Admission classes:** `structural`, `runtime`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - tracker claim has succeeded,
  - returned issue identity has been validated,
  - board projection has been refreshed
- **Receipt family:** `issue.claim`
- **Restoration behavior:** no explicit rollback today; there is no Tusk-side
  live-lane mutation to restore
- **Primary obstructions:** missing issue, issue not open, issue not ready

### `launch_lane`

- **Phase:** fiber-entry
- **Payload:** `issue_id`, `base_rev`, optional `slug`
- **Witness basis:** `issue_id`, `base_rev`, `issue_exists`,
  `issue_in_progress`, `no_live_lane`, `base_rev_resolves`,
  `workspace_absent`
- **Admission classes:** `structural`, `runtime`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - workspace exists and is attached to the chosen base,
  - live lane state exists with `status = launched`,
  - lane state records workspace name/path and base revision data,
  - board projection has been refreshed
- **Receipt family:** `lane.launch`
- **Restoration behavior:** if failure occurs after workspace creation or after
  live lane persistence, runtime attempts to remove lane state, forget the
  workspace, and remove the workspace directory
- **Primary obstructions:** issue not in progress, live lane already exists,
  base revision does not resolve, workspace path already exists

### `handoff_lane`

- **Phase:** fiber-internal
- **Payload:** `issue_id`, `revision`, optional `note`
- **Witness basis:** `issue_id`, `revision`, `lane_exists`,
  `lane_handoffable`, `revision_resolves`
- **Admission classes:** `structural`, `runtime`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - live lane remains present,
  - lane `status = handoff`,
  - `handoff_revision` and `handed_off_at` are recorded,
  - optional `handoff_note` is persisted,
  - board projection has been refreshed
- **Receipt family:** `lane.handoff`
- **Restoration behavior:** if receipt append fails, prior lane state is
  restored
- **Primary obstructions:** no live lane record, revision does not resolve,
  lane is not handoffable

### `finish_lane`

- **Phase:** fiber-internal
- **Payload:** `issue_id`, `outcome`, optional `note`
- **Witness basis:** `issue_id`, `outcome`, `lane_exists`,
  `lane_finishable`
- **Admission classes:** `structural`, `runtime`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - live lane remains present,
  - lane `status = finished`,
  - `outcome` and `finished_at` are recorded,
  - optional `finish_note` is persisted,
  - board projection has been refreshed
- **Receipt family:** `lane.finish`
- **Restoration behavior:** if receipt append fails, prior lane state is
  restored
- **Primary obstructions:** no live lane record, lane not finishable, outcome
  missing

### `archive_lane`

- **Phase:** fiber-discharge
- **Payload:** `issue_id`, optional `note`
- **Witness basis:** `issue_id`, `lane_exists`, `lane_finished`,
  `workspace_removed`
- **Admission classes:** `structural`, `runtime`, `replay`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - live lane record no longer exists,
  - the workspace was already absent at admission time,
  - board projection has been refreshed
- **Receipt family:** `lane.archive`
- **Restoration behavior:** if receipt append fails, archived lane state is
  restored
- **Primary obstructions:** no live lane record, lane not finished, workspace
  still present on disk

### `close_issue`

- **Phase:** base-only
- **Payload:** `issue_id`, `reason`
- **Witness basis:** `issue_id`, `close_reason`, `issue_exists`,
  `issue_not_closed`, `no_live_lane`
- **Admission classes:** `structural`, `authority`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - tracker close has succeeded,
  - returned issue identity has been validated,
  - board projection has been refreshed
- **Receipt family:** `issue.close`
- **Restoration behavior:** no explicit rollback today; precondition is
  intentionally strong because local discharge must already have happened
- **Primary obstructions:** close reason missing, issue already closed, live
  lane still exists

### `tracker.ensure`

- **Phase:** service realization
- **Payload:** optional repair/runtime options depending on caller surface
- **Witness basis:** `backend_observed`, `tracker_checks_observed`,
  `service_snapshot_observed`
- **Admission classes:** `runtime`
- **Admitted iff:** all basis witnesses above are satisfied
- **Success postconditions:**
  - ensure/adopt/publish path has completed,
  - service/backend state has been published,
  - service-facing projections may change accordingly
- **Receipt family:** `tracker.ensure`
- **Restoration behavior:** no explicit rollback contract yet; this remains the
  first Rust-owned service realization seam
- **Primary obstructions:** preflight observation unavailable, service
  publication failure, ensure/adopt failure

## Cross-transition invariants

### Invariant 1 — Application follows admission

No contract may skip explicit admission and still count as a governed
transition.

### Invariant 2 — One receipt family per successful application

Every successful transition SHALL emit an authoritative receipt of the relevant
family.

### Invariant 3 — Launch and archive bracket live lane state

For the first kernel:

- `launch_lane` creates live lane state
- `archive_lane` removes live lane state

No other transition may silently create or destroy the live lane record.

### Invariant 4 — Close requires discharge

`close_issue` SHALL NOT succeed while a live lane exists.

### Invariant 5 — Projection follows successful application

Read surfaces may lag transiently in practice, but the contract assumes
successful application refreshes the relevant projection.

### Invariant 6 — Archived is not a live status

In the current runtime, archive is represented by absence of a live lane plus
archive receipt evidence. It is not a persisted live lane status.

## Testing consequence

The transition suite SHOULD exercise each contract along at least three paths:

1. admitted success,
2. admission obstruction,
3. apply-time failure with restoration where relevant.

That turns the spec from prose into a real runtime boundary.
