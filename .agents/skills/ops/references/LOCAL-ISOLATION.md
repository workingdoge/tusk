# Local isolation attachment after local inspection

Do **not** start here.
Use this note when the operational question is about local containers,
microvms, or agent runtimes.

## First split

Read local isolation as one of two attachment sites:

1. Lane-scoped local probe
   Use for first proofs and bounded runtime experiments.
2. Admitted realization / executor family
   Use only after the constructor is stable enough to be reused.

Rule:
- prefer the lane-scoped local probe before promoting anything into an
  executor family

## What belongs in `tusk`

- the normalized runtime request shape
- the binding from lane or realization context into that request
- admission checks over the local authority boundary
- receipt normalization and sink selection
- reattachment rules back to shared repo truth

## What stays out of `tusk`

- Hermes-specific or app-specific bootstrap payload details
- credentials, model/provider policy, and funded runtime behavior
- product-local guest state
- engine-specific implementation details unless they remain generic reusable
  operational infra

## Minimal constructor checklist

Before comparing substrates, name these fields:

- source context:
  issue id, lane/workspace, and optional realization id
- runtime identity:
  kind, constructor id, profile id
- command
- mounts
- environment policy
- network policy
- inputs
- receipt family and sink
- reattach mode

If those fields are still ambient shell assumptions, the boundary is not
ready.

## Questions to answer first

1. Is this work a lane-scoped local probe or a reusable executor family?
2. What is the smallest runtime constructor that proves the path?
3. What crosses the boundary as explicit mounts, env, and network choices?
4. How does the run emit a receipt?
5. How does success reattach to shared truth without collapsing directly into
   issue closure?

## Anti-patterns

Avoid:

- starting with a general agent-runtime framework
- treating ambient host env as the operational contract
- hiding credentials or product policy inside `tusk`
- promoting to executor family before one local proof repeats cleanly

## Related repo notes

- `design/tusk-isolation-attachment.md`
- `design/tusk-workflow-topology.md`
- `design/tusk-local-trace-executor.md`
