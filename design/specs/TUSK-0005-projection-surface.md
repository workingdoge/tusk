# TUSK-0005 — Projection Surface

## Status

Draft.

Depends on `TUSK-0000` through `TUSK-0004`.

## Purpose

Keep read-side surfaces useful without letting them become authority.

The operator should be able to answer four questions at a glance:

1. **What base locus am I over?**
2. **What live local context exists, if any?**
3. **What witness is missing for the next lawful move?**
4. **Is closure currently admissible?**

## Projection doctrine

A projection is a recomposed read model over authoritative state.

It MAY summarize, narrate, or recommend.
It SHALL NOT become a second source of truth.

For the first kernel, the projection family includes at least:

- `status`
- `board_status`
- `sessions_status`
- `receipts_status`
- `operator_snapshot`

## Laws

### Law 1 — Null-over-fabrication law

If a projection cannot determine a field from authoritative state, it SHOULD
prefer `null`, `unknown`, or explicit absence over invented certainty.

### Law 2 — Recommendation humility law

A recommendation is advisory. It SHALL NOT count as admission.

### Law 3 — Missing-witness specificity law

`missing_witnesses` SHALL be interpreted with respect to a nominated next move,
not as a global statement about the entire issue forever.

### Law 4 — Closure-eligibility law

`closure_eligible` SHALL be a predicate over authoritative current state, not a
vague impression that work “feels done”.

## Minimum issue-oriented surface

A healthy issue-oriented projection SHOULD expose, per issue row or drill-down:

- `issue_id`
- current tracker status
- base placement/classification context as available
- `live_lane` object or `null`
- `next_lawful_move` or `null`
- `missing_witnesses`
- `descent_state`
- `closure_eligible`

Those fields do not require a new authority source. They are recompositions of
existing tracker, lane, service, and receipt state.

## Minimum service-oriented surface

A healthy service-oriented projection SHOULD expose:

- current service/backend health
- whether the ensure surface is healthy enough to trust
- runtime obstructions
- recent ensure receipts
- any recommendation to repair/adopt/publish

## Descent state shape

For issue-oriented surfaces, `descent_state` SHOULD at least make visible:

- whether a live lane exists,
- whether handoff evidence exists,
- whether finished state exists,
- whether workspace removal has happened,
- whether discharge/archive evidence exists.

Note that in the current runtime, archive is represented by absence of live lane
plus receipt evidence; it is not a live lane status.

## Obstructions vs missing witnesses

These are related but not identical:

- an **obstruction** is an operator-facing reason work is presently blocked or
  unhealthy,
- a **missing witness** is the explicit insufficiency for one specific
  transition.

Good projections should expose both without collapsing them.

## Current alignment

The existing `operator_snapshot` already carries much of the right shape:

- `now`
- `next`
- `history`
- `context`
- `drill_down`

It already exposes runtime health, active lanes, claimed issues, stale lanes,
obstructions, recommendations, recent receipts, and repo/tracker/workspace
context.

The sharpening required by this spec is not “more dashboard”. It is stronger
field discipline.

## Suggested issue-row shape

```json
{
  "issue_id": "config-w1b.7",
  "tracker_status": "in_progress",
  "base_locus": {
    "track": "core",
    "place": "tusk",
    "surface": "ops"
  },
  "live_lane": {
    "status": "handoff",
    "workspace_path": "...",
    "handoff_revision": "..."
  },
  "next_lawful_move": "finish_lane",
  "missing_witnesses": [],
  "descent_state": {
    "live_lane": true,
    "handoff_recorded": true,
    "finished": false,
    "workspace_removed": false,
    "archived": false
  },
  "closure_eligible": false
}
```

A service-oriented row should obey the same law even if its base locus is a
service/runtime record rather than an issue.

## Result

If this spec is followed, the operator surface stops being “another dashboard”
and becomes a lawful projection of the kernel:

- base locus is visible,
- live local context is visible,
- the next missing witness is visible,
- closure readiness is visible.

That is the practical face of the mathematics.
