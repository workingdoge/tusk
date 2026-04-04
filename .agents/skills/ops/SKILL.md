---
name: ops
description: >
  Use this skill when Codex needs to design, inspect, compare, or debug a
  Nix-native operational pipeline: CI/CD topology, verified checks, admissible
  effects, Hercules CI, hercules-ci-effects, forge workflow generators such as
  actions.nix, caches, deploy surfaces, and the boundary between pure
  evaluation and effectful realization. Trigger it for questions about what
  should remain pure CI, what should become effectful CD, how to place
  secrets/state, how to compare Hercules against generated forge workflows, or
  how to operationalize a flake without collapsing into generic devops. Prefer
  local flake inspection and official-source docs first.
---

# Ops

This is the operational counterpart to the repo's `nix` skill.

It is **not** a generic devops skill.
It is for Nix-native operational topology: checks, effects, releases,
deployments, caches, and the transport layer that carries them.

Read:
- `references/PIPELINE-SHAPE.md` for the bundle-shaped operational model
- `references/PLATFORMS.md` for Hercules vs actions.nix vs adjacent tools
- `references/TOOLING.md` for local inspection and validation commands

## Core doctrine
Default order:

1. inspect the local flake and current automation surface,
2. identify the pure verified base,
3. identify the admissible effects above that base,
4. identify the secrets/state boundary,
5. only then compare operational platforms,
6. propose the smallest useful slice.

The skill exists because Nix-native operations are not one flat problem:
- `git-hooks-nix` is local and check-oriented
- `actions.nix` is forge workflow generation
- Hercules effects are a separate effect layer over successful jobs
- deployment and cache tooling live further out at the realization edge

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

## Local-first rules
- Prefer local flake inspection before platform comparison.
- Prefer the smallest check or effect boundary over whole-system reasoning.
- Prefer official-source docs after the local shape is known.
- Treat secrets/state as a separate layer, not as an implementation detail.
- Keep the semantic center on validated sections plus admissible effects.

## References
- Read `references/PIPELINE-SHAPE.md` for the operational model.
- Read `references/PLATFORMS.md` for official-source platform positioning.
- Read `references/TOOLING.md` for concrete command order.
