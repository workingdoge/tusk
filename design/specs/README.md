# Tusk Spec Kernel

This directory defines the smallest normative series for **Tusk**.

Kernel sentence:

> **Tusk governs repo-local workflow transitions over canonical coordination state.**

These specs are a compression layer over the existing design notes. They do not
replace the broader design set; they make the operative law explicit enough to
bind implementation, tests, projections, and future adapters.

Normative keywords such as **SHALL**, **SHOULD**, and **MAY** are used in their
usual specification sense.

## Repo Ownership

These files are repo-owned and authoritative for this checkout.

See `PROVENANCE.md` for the import note, current repo status, and the rule that
future kernel edits happen here rather than in out-of-tree spec bundles.

## Series map

- `TUSK-0000` — Identity and Boundary
- `TUSK-0001` — Base / Fiber
- `TUSK-0002` — Cover / Admission
- `TUSK-0003` — Descent / Closure
- `TUSK-0004` — Transition Contracts
- `TUSK-0005` — Projection Surface

## How to read the series

Read the series in this order:

1. **Boundary** — what Tusk is allowed to be (`TUSK-0000`)
2. **Structure** — how local work sits over canonical coordination (`TUSK-0001`)
3. **Admission** — how proposals become runnable (`TUSK-0002`)
4. **Closure** — how local work stops being merely local (`TUSK-0003`)
5. **Contracts** — what each concrete transition promises (`TUSK-0004`)
6. **Projection** — what the operator surface must expose (`TUSK-0005`)

`TUSK-0004` is the binding engineering surface.

## What the series buys

If this series is respected, Tusk gains five things:

1. **Boundary** — tracker truth, lane truth, workspace state, receipts, and
   projections stop drifting together.
2. **Recoverability** — context can be reconstructed from explicit structure
   instead of operator memory.
3. **Admission clarity** — a rejected transition explains *which witness is
   missing* rather than merely failing.
4. **Closure discipline** — “done” means local work has been discharged and the
   base side is eligible for closure.
5. **Projection honesty** — operator surfaces stay read-side and do not quietly
   become authority.

## Scope of the first kernel

The first governed family is:

- `create_child_issue`
- `claim_issue`
- `close_issue`
- `launch_lane`
- `handoff_lane`
- `finish_lane`
- `archive_lane`
- `tracker.ensure`

Future transitions MAY enter the kernel, but only by taking the same shape:
proposal, witness record, admission, application, receipt, projection.

## Existing notes this series leans on

- `design/notes/tusk-governed-transition-kernel.md`
- `design/notes/tusk-transition-carrier.md`
- `design/notes/tusk-workflow-topology.md`
- `design/notes/tusk-operator-snapshot.md`
- `design/notes/tusk-semantic-spine-map.md`
- `design/migration-candidates/tusk-upstream-kernel-recast.md`

## Deliberate non-goals

This series does **not** attempt to specify:

- public remote protocol law
- theorem/proof surfaces above the local carried seam
- paid HTTP, Radicle, or other adapters as kernel-defining surfaces
- a universal ontology for “the rest of the universe”

Those may compile *from* the kernel later. They do not define the kernel now.
