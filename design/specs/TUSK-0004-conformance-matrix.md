# TUSK-0004 Conformance Matrix

## Status

Draft companion.

Depends on `TUSK-0004`.

## Purpose

Make the current implementation and test alignment legible without changing
contract authority.

`TUSK-0004-transition-contracts.md` remains normative. This file is a
repo-owned companion that points at the current builder, realization, receipt,
and verification surfaces.

## Matrix

| Transition | Witness basis | Current implementation surface | Receipt family | Current test surface | Current note |
| --- | --- | --- | --- | --- | --- |
| `create_child_issue` | `parent_id`, `title`, `parent_exists`, `parent_open`, `child_issue_id` | Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_create_child_issue_carrier`, `realize_create_child_issue_transition`; shell wrapper: `cmd_create_child_issue` in `scripts/tuskd.sh` | `issue.create` | `test_concurrent_child_creates`, `test_child_create_identity_mismatch` in `scripts/tuskd-transition-tests.sh` | Success and post-create identity mismatch are covered. Missing-parent and closed-parent obstruction paths are not yet isolated in the transition suite. |
| `claim_issue` | `issue_id`, `issue_exists`, `issue_status_open`, `issue_ready` | Shell carrier/realizer in `scripts/tuskd.sh`: `build_claim_issue_carrier`, `realize_claim_issue_transition`; Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_claim_issue_carrier`, `realize_claim_issue_transition` | `issue.claim` | `test_lifecycle_guards`, `test_concurrent_claims` | Success and concurrent obstruction are covered. An explicit missing-issue path is not yet singled out. |
| `launch_lane` | `issue_id`, `base_rev`, `issue_exists`, `issue_in_progress`, `no_live_lane`, `base_rev_resolves`, `workspace_absent` | Shell carrier/realizer in `scripts/tuskd.sh`: `build_launch_lane_carrier`, `realize_launch_lane_transition`; Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_launch_lane_carrier`, `realize_launch_lane_transition` | `lane.launch` | `test_lifecycle_guards`, `test_launch_rollback`, `test_compact_lane_remove`, `test_compact_lane_quarantine`, `test_complete_lane` | Success and rollback are covered. Bad-base and workspace-already-present obstructions are not yet isolated. |
| `handoff_lane` | `issue_id`, `revision`, `lane_exists`, `lane_handoffable`, `revision_resolves` | Shell carrier/realizer in `scripts/tuskd.sh`: `build_handoff_lane_carrier`, `realize_handoff_lane_transition`; Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_handoff_lane_carrier`, `realize_handoff_lane_transition` | `lane.handoff` | `test_lifecycle_guards`, `test_compact_lane_remove`, `test_compact_lane_quarantine`, `test_complete_lane` | Success and missing-lane obstruction are covered. A revision-resolution failure path is not yet isolated. |
| `finish_lane` | `issue_id`, `outcome`, `lane_exists`, `lane_finishable` | Shell carrier/realizer in `scripts/tuskd.sh`: `build_finish_lane_carrier`, `realize_finish_lane_transition`; Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_finish_lane_carrier`, `realize_finish_lane_transition` | `lane.finish` | `test_lifecycle_guards`, `test_compact_lane_remove`, `test_compact_lane_quarantine`, `test_complete_lane` | Success and missing-lane obstruction are covered. A distinct non-finishable path is not yet isolated. |
| `archive_lane` | `issue_id`, `lane_exists`, `lane_finished`, `workspace_removed` | Shell carrier/realizer in `scripts/tuskd.sh`: `build_archive_lane_carrier`, `realize_archive_lane_transition`; Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_archive_lane_carrier`, `realize_archive_lane_transition` | `lane.archive` | `test_lifecycle_guards`, `test_compact_lane_remove`, `test_compact_lane_quarantine`, `test_complete_lane` | Success and workspace-still-present obstruction are covered. A no-live-lane path is not yet isolated. |
| `close_issue` | `issue_id`, `close_reason`, `issue_exists`, `issue_not_closed`, `no_live_lane` | Shell carrier/realizer in `scripts/tuskd.sh`: `build_close_issue_carrier`, `realize_close_issue_transition`; Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_close_issue_carrier`, `realize_close_issue_transition` | `issue.close` | `test_lifecycle_guards`, `test_concurrent_claims`, `test_launch_rollback`, `test_compact_lane_remove`, `test_compact_lane_quarantine`, `test_complete_lane` | Success and live-lane obstruction are covered. Missing-issue and already-closed paths are not yet isolated. |
| `tracker.ensure` | `backend_observed`, `tracker_checks_observed`, `service_snapshot_observed` | Rust carrier/realizer in `crates/tuskd-core/src/main.rs`: `build_ensure_carrier`, `realize_ensure_transition`, `perform_ensure`; shell wrapper and read-side compatibility surface in `scripts/tuskd.sh`: `cmd_ensure`, `ensure_projection` | `tracker.ensure` | Harness bootstrap in `run_inner_harness` in `scripts/tuskd-transition-tests.sh`; seam contract in `tuskd core-seam` / `SEAM_JSON` in `crates/tuskd-core/src/main.rs` | The transition family is live and emits receipts, but it does not yet have the same dedicated admitted-success / admission-obstruction / restoration suite as the lane/base transitions. |

## Current split

Two seams are worth keeping explicit:

- `create_child_issue` and `tracker.ensure` already lean on the Rust-owned
  carrier/realization surface, with the shell acting primarily as wrapper and
  compatibility surface.
- The remaining first-kernel lane/base transitions still have mirrored shell and
  Rust carrier/realizer functions.

That split is current implementation fact, not a second authority source.

## Known mismatches

- The transition suite does not yet exercise every `TUSK-0004` obstruction axis
  explicitly. Many rows have admitted-success plus one obstruction or rollback
  path, but not the full three-path envelope the spec calls for.
- `tracker.ensure` is the least test-shaped contract today. It has a live Rust
  transition family and receipt path, but not a dedicated transition-suite
  section parallel to the lane/base family.
- Closeout helpers outside the first-kernel contract surface still carry one
  status-name drift: `compact-lane` branches on `handed_off`, while live lane
  state and `handoff_lane` use `handoff`. That does not change the
  `handoff_lane` contract itself, but it is a real conformance bug around
  composed closeout paths.

## Result

This matrix makes the current state citeable:

- the normative contract stays in `TUSK-0004`,
- the implementation and receipt seams are named,
- the test coverage and gaps are visible,
- later runtime cleanup can target explicit rows instead of implicit memory.
