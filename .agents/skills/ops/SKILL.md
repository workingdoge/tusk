---
name: ops
description: >
  Use this skill when Codex needs to design, inspect, compare, or debug a
  Nix-native operational pipeline: CI/CD topology, verified checks, admissible
  effects, Hercules CI, hercules-ci-effects, forge workflow generators such as
  actions.nix, caches, deploy surfaces, local container/microvm attachment,
  and the boundary between pure evaluation and effectful realization. Trigger
  it for questions about what should remain pure CI, what should become
  effectful CD, how to place secrets/state, how to compare Hercules against
  generated forge workflows, how a local isolation probe should attach to the
  control plane, when a structural probe is sufficient versus when a live
  host or executor proof is still required, or how to decide when an
  ops-shaped lane can cleanly close. Prefer local flake inspection and
  official-source docs first.
---

# Ops

This is the operational counterpart to the repo's `nix` skill.

It is **not** a generic devops skill.
It is for Nix-native operational topology: checks, effects, releases,
deployments, caches, and the transport layer that carries them.

Read:
- `references/PIPELINE-SHAPE.md` for the bundle-shaped operational model
- `references/PROOF-LEVELS.md` for the five-rung proof ladder and the
  close-boundary rule
- `references/LOCAL-ISOLATION.md` for lane-scoped local probes and later
  executor-family promotion
- `references/PLATFORMS.md` for Hercules vs actions.nix vs adjacent tools
- `references/TOOLING.md` for local inspection and validation commands

## Core doctrine
Default order:

1. inspect the local flake and current automation surface,
2. identify the pure verified base,
3. identify the admissible effects or local runtime attachments above that
   base,
4. identify the secrets/state and authority boundary,
5. locate the work on the proof ladder (inspection → structural probe →
   lane-scoped local proof → live host smoke → reusable executor-family
   promotion) and name which rung is sufficient for this lane,
6. distinguish lane-scoped proof from reusable executor-family promotion,
7. only then compare operational platforms,
8. propose the smallest useful slice.

The skill exists because Nix-native operations are not one flat problem:
- `git-hooks-nix` is local and check-oriented
- `actions.nix` is forge workflow generation
- Hercules effects are a separate effect layer over successful jobs
- deployment and cache tooling live further out at the realization edge
- local isolation is a bounded runtime attachment, not a second semantic center

## Run this first
Before reading platform docs:

1. inspect `flake.nix`
2. search for current operational markers, for example:
   - `checks`
   - `githubActions`
   - `herculesCI`
   - `effects`
   - `deploy-rs`
   - `colmena`
   - `attic`
3. inspect only the narrow files that define those surfaces

Do not start with product comparisons before you know what the flake already
exports or declares.

## Workflow
### 1) Pipeline topology
Use when the user asks:
- what is our CI/CD shape?
- what is pure and what is effectful?
- what are the operational outputs of this flake?

Default moves:
1. inspect the local flake
2. read `references/PIPELINE-SHAPE.md`
3. validate the existing outputs with the smallest possible checks

Goal:
Produce a map of verified sections, admissible effects, and realizations.

### 2) Platform choice
Use when the user asks:
- Hercules or actions.nix?
- where does git-hooks-nix fit?
- do we need CI only or CI plus effects?

Default moves:
1. inspect what transport or platform is already present
2. read `references/PLATFORMS.md`
3. compare the smallest viable path, not the whole ecosystem

Goal:
Choose the semantic center first, then the transport.

### 3) Operational debugging
Use when the user asks:
- why did this check/effect/deploy fail?
- where is this workflow or effect defined?
- why is this secret/state/deploy step admissible here?

Default moves:
1. identify whether the failure is in pure evaluation, build/check, or effect
2. inspect the narrow local definition
3. use `references/TOOLING.md` for command order
4. only then read the exact official docs page

Goal:
Find the first user-owned operational boundary that explains the failure.

### 4) Local isolation attachment
Use when the user asks:
- should this container or microvm work live in `tusk`?
- is this a lane-scoped local probe or a reusable executor family?
- how should a local Hermes-style runtime attach to the control plane?
- what crosses the guest boundary as explicit mounts, env, network, and
  receipts?

Default moves:
1. inspect the existing lane, workflow, and runtime surfaces
2. read `references/LOCAL-ISOLATION.md`
3. classify the slice as a lane-scoped local probe or an admitted realization
4. name the constructor inputs explicitly:
   - mounts
   - environment policy
   - network mode
   - receipt sink
   - reattach mode
5. keep payload, credentials, and product policy outside `tusk`

Goal:
Choose one bounded local proof path without widening into a general
agent-runtime framework.

### 5) Close-boundary decision
Use when the user asks:
- is this ops-shaped lane done?
- is a structural probe enough, or do we still need a live host or executor
  proof?
- can we close the tracker issue now, or is this only a handoff?

Default moves:
1. read `references/PROOF-LEVELS.md`
2. name the highest rung the lane actually reached, not the rung it aspires
   to
3. match that rung against the lane's declared landing boundary
4. distinguish skill/spec/doc-shaped lanes (where structural completion is
   usually sufficient) from executor/runtime/effect-shaped lanes (where a
   live host smoke or repeated lane-scoped proof is required)
5. if promotion to a reusable executor family is in question, treat it as a
   separate issue, never as an implicit close

Goal:
Close on the declared landing boundary, and make any remaining live-proof
debt explicit as a follow-up issue rather than hiding it behind a structural
pass.

## Local-first rules
- Prefer local flake inspection before platform comparison.
- Prefer the smallest check or effect boundary over whole-system reasoning.
- Prefer official-source docs after the local shape is known.
- Treat secrets/state as a separate layer, not as an implementation detail.
- When the question is really about bridge admission or secret materialization
  rather than generic repo operations, route to the canonical `bridge` skill
  when it is available. Strong triggers include `AuthorizeRequest`,
  `ProviderResults`, `PolicyInput`, `MaterializationPlanRequest`, and
  `MaterializationSession`.
- Keep the semantic center on validated sections plus admissible effects.
- Prefer lane-scoped local probes before reusable executor families.
- Treat mounts, env policy, network policy, receipt sinks, and reattach mode as
  explicit contract fields, not ambient shell inheritance.
- Keep Hermes/bootstrap commands, credentials, and product policy downstream of
  the `tusk` attachment boundary.
- Name the rung of the proof ladder the lane actually reached, and treat
  structural completion as insufficient evidence for runtime or effect
  changes.
- Do not close an ops-shaped lane on a structural probe when the declared
  landing boundary requires a live host smoke; file the missing proof as a
  follow-up issue instead of widening the lane.
- Treat promotion into a reusable executor family as a separate issue, not a
  silent side effect of closing the current lane.

## References
- Read `references/PIPELINE-SHAPE.md` for the operational model.
- Read `references/PROOF-LEVELS.md` for the five-rung proof ladder and
  close-boundary rule.
- Read `references/LOCAL-ISOLATION.md` for local isolation attachment.
- Read `references/PLATFORMS.md` for official-source platform positioning.
- Read `references/TOOLING.md` for concrete command order.
