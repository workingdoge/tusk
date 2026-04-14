---
name: topology
description: >
  Use this skill when Codex needs to decide where consequential work belongs
  across `fish`, `bridge`, `kurma`, `tusk`, and downstream repos such as
  `home` and `aac`, or when it needs to shape one clean lane wire before
  implementation.
  Trigger it for repo-placement questions, upstream-vs-downstream boundary
  questions, issue reshaping, proof-vs-product sequencing, and cleanup when a
  default checkout starts carrying mixed threads. Prefer the repo's placement
  rules and one-wire-per-lane discipline before starting code changes.
---

# Topology

This skill exists to stop consequential work from starting in the wrong repo or
in the wrong lane.

It is not a generic architecture essay.
It is the repo-local routing surface for:

- repo placement
- upstream versus downstream ownership
- issue shaping by context boundary
- one-wire-per-lane discipline

Read:
- `references/PLACEMENT-AND-WIRES.md` for the placement matrix, sequencing
  rules, and the wire contract

## Core move

Before starting a consequential slice:

1. classify the work by context
2. choose the owning repo or layer
3. shape one bounded wire
4. only then start or reshape a lane with `$tusk`

## Context classes

Use these first:

- `meaning`
- `carriage`
- `governed-runtime`
- `shared-operational-infra`
- `downstream-product`
- `downstream-proof`

The most important split is:

- tracked upstream `premath` and `fish` define meaning
- `bridge` owns the canonical bridge+secret domain stack
- `kurma` carries reusable method such as `Premath`, `Nerve`, and `WCAT`
- `tusk` binds stable upstream surfaces into repo workflow and operator control
- downstream repos consume that bound surface according to their own product or
  operator policy

When the question is specifically about bridge admission or secret
materialization, route to the canonical `bridge` skill when it is available.
Strong trigger terms include:

- `AuthorizeRequest`
- `ProviderResults`
- `PolicyInput`
- `MaterializationPlanRequest`
- `MaterializationSession`
- bridge admission
- secret materialization
- burn or restore of a materialized capability

## Output contract

When you use this skill, produce these five things:

1. context class
2. owning repo or layer
3. issue track or follow-up issue shape
4. one lane wire:
   - input context
   - output artifact
   - verification boundary
   - landing boundary
5. next action

## Guardrails

- Do not let `tusk` absorb meaning or carriage.
- Do not leave canonical bridge-domain changes in `tusk` once `bridge` owns
  that stack.
- Do not let downstream product work masquerade as shared infra.
- Do not start implementation from an ambient dirty default checkout when a
  cleanup lane is the real first move.
- Do not put more than one main wire in one issue if the contexts differ.
- When a consumer proof and a second consumer integration are both in view,
  prefer the first live proof before the second integration.

## References

- Read `references/PLACEMENT-AND-WIRES.md` before deciding repo placement or
  issue shape.
