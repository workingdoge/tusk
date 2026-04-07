# Tusk Operator UX Model

## Status

Normative information-architecture note for the operator-facing control-plane
surface in `tusk`.

## Intent

`tusk` already has the raw pieces of a control plane:

- tracker status,
- board projections,
- lane state,
- workspace observations,
- receipts,
- and a `ratatui` client in `tusk-ui`.

But the current surface still mirrors backend partitions more than operator
questions.

The operator should not have to mentally join:

- `tracker_status`,
- `board_status`,
- `receipts_status`,
- `.beads/tuskd/lanes.json`,
- and `jj workspace list`

just to answer:

- what is happening now?
- what matters next?
- what just changed?
- and what context am I operating in?

This note defines the operator-facing information architecture that should sit
above those raw projections.

## Boundary

The operator surface must stay provider-agnostic.

That means:

- `tuskd` remains the provider-independent authority and projection source
- `tusk-ui` is one operator-facing client over that authority
- Codex is one proposal-side client
- a future `pi`-style runtime could become another proposal-side client

The UI should not encode one model vendor, one LLM runtime, or one agent
implementation into the control-plane center.

## Home Questions

The primary operator surface should answer four questions in order:

1. `Now`
   What is live, active, unhealthy, stale, or waiting on me right now?

2. `Next`
   What work is ready, what is blocked, and what action is the best next move?

3. `History`
   What recently happened that explains the current state?

4. `Context`
   Which repo, checkout, tracker root, workspace set, and runtime am I
   operating in?

These are the top-level information buckets.
Raw protocol partitions are drill-down surfaces, not the home screen.

## Human Briefing Layer

The home surface should read like a briefing, not a schema dump.

That means:

- one clear headline about what matters now
- one primary recommendation about what to do next
- a short rationale that explains *why this issue* matters now
- dependency-aware context that explains what the recommendation unlocks or is
  waiting on

The dependency graph is therefore part of the narrative substrate, not only a
separate visualization feature.

The operator should be able to answer:

- what should I do now?
- why this issue instead of another one?
- what work does it unblock or depend on?

## The Four Views

### 1. Now

`Now` is the live operational picture.

It should surface:

- active lanes
- claimed-but-not-launched issues
- stale lanes or missing workspaces
- tracker/service health
- runtime obstructions that need intervention

`Now` is not a general backlog view.
It is the answer to "what is in motion or broken?"

Current source material:

- active and stale lanes from `lane_state_projection`
- claimed issues from `board_status_projection`
- service health from `tracker_status_projection`
- workspace observations from `jj workspace list`

### 2. Next

`Next` is the action queue.

It should surface:

- ready issues worth claiming
- blocked issues with compact blocking explanation
- deferred work only when it matters to sequencing
- obvious next operator actions

`Next` should help the operator choose, not merely enumerate.

Current source material:

- ready issues from `tracker_ready`
- blocked and deferred buckets from `tracker_board_issues`
- lane/workspace absence from the board projection

### 3. History

`History` is the compact narrative of recent authoritative transitions.

It should surface:

- recent claims, launches, handoffs, finishes, archives, and ensure events
- the minimum payload needed to explain the present
- failures or obstructions that changed the control-plane picture

`History` is not the full receipt log.
It is a summarized operator-facing recency slice over receipts.

Current source material:

- `receipts_status`
- receipt kind and compact payload hints

### 4. Context

`Context` is the stable environment frame.

It should surface:

- repo root
- checkout root versus tracker root
- current bookmark or base revision where useful
- live workspaces
- socket/backend/runtime identity
- whether the current checkout is dirty or stale

`Context` explains where the operator is standing while reading `Now`, `Next`,
and `History`.

Current source material:

- tracker status repo/socket/backend fields
- workspace list
- checkout-root versus tracker-root runtime contract
- local VCS observations

## Mapping From Existing Projections

The current raw surfaces remain useful, but they map differently:

- `tracker_status`
  Feeds `Now` and `Context`

- `board_status`
  Feeds `Now` and `Next`

- `receipts_status`
  Feeds `History`

- lane truth in `.beads/tuskd/lanes.json`
  Feeds `Now`

- `jj workspace list`
  Feeds `Now` and `Context`

So the home surface should be a recomposed projection, not a 1:1 rendering of
those raw protocol calls.

## Home Versus Drill-Down

The home surface should be:

- compact
- operator-first
- action-oriented

The drill-down surfaces can still expose:

- raw tracker service detail
- raw board buckets
- raw receipts
- backend diagnostics

So the direction is:

- home screen: `Now / Next / History / Context`
- drill-down: `Tracker / Board / Receipts / Backend`

The current `tusk-ui` panes are therefore not wrong.
They are just too low-level to be the primary operator view.

## Implication For `tuskd`

The current home question requires one compact operator snapshot above the raw
protocol partitions.

That snapshot should not become a new source of truth.
It should be a recomposed projection over existing authority:

- tracker health,
- board buckets,
- lane truth,
- workspace observations,
- and recent receipts.

This is the purpose of `tusk-asy.9.1`.

## Implication For `tusk-ui`

`tusk-ui` should change its primary information architecture from:

- `Tracker`
- `Board`
- `Receipts`

to:

- `Now`
- `Next`
- `History`
- `Context`

while preserving the raw protocol panes as secondary or drill-down surfaces.

This is the purpose of `tusk-asy.9.2`.

## Non-Goals

This note does not:

- define a web UI
- define a public network protocol
- replace `tuskd` with an agent runtime
- couple the control plane to OpenAI, Anthropic, or any other provider
- redesign every keyboard interaction in one pass

## Recommendation

Proceed as if:

- `tuskd` remains the provider-independent authority,
- the operator home surface is `Now / Next / History / Context`,
- raw protocol panes are drill-down views,
- and `tusk-ui` becomes the first concrete operator client over that model.
