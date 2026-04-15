---
name: payments
description: >
  Use this skill when Codex needs to interpret an HTTP `402` or similar
  paid-access challenge, classify the protocol family and method, run local
  preflight, invoke or design the right witness or settlement-executor
  boundary, retry with family-correct headers, and classify the provider
  verdict without collapsing funded execution, provider policy, or wallet
  custody into `tusk`. Trigger it for paid HTTP, PaymentAuth, Tempo, x402,
  payment receipts, retry headers, max-spend hints, and operator-facing
  challenge loops.
---

# Payments

This is the shared operator-facing skill for challenged paid access under HTTP
`402`.

It is **not**:
- a funded wallet or signer custody skill
- a provider-local product policy skill
- the canonical witness or payment doctrine

Read:
- `references/CHALLENGE-LOOP.md` for the normalized `402` loop
- `references/FAMILIES-AND-ROUTING.md` for family boundaries, executor split,
  and owner routing
- `references/WITNESS-ROUTING.md` for the outer-gate versus method-family
  split, sibling method sketches, and the generic witness-realization seam

## Core doctrine
Default order:

1. confirm the outer gate is `402` or an equivalent paid-access challenge
2. classify the protocol family plus method or scheme
3. inspect local preflight and continuation state
4. build or invoke the right witness or settlement-executor boundary
5. retry with family-correct headers
6. classify the provider verdict
7. persist receipt and state transition
8. only then widen into provider-specific diagnosis or upstream type work

The semantic center is the challenge loop, not the funded runtime:
- `402` is the outer gate
- protocol family and method sit beneath it
- the executor or witness boundary is the local realization seam
- some methods are concrete family members, while the future carried witness
  method lives upstream of `tusk`

## Workflow
### 1) Challenge classification
Use when the user asks:
- what does this `402` mean?
- is this `PaymentAuth`, `tempo`, or `x402`?
- which headers actually matter?

Default moves:
1. inspect the live challenge first
2. classify the family
3. classify the method or scheme
4. note the priced intent before touching a local wallet or executor

Goal:
Produce a family-correct challenge object and a short statement of what the
provider is asking for.

### 2) Preflight and witness realization
Use when the user asks:
- why can this request not proceed?
- what local state is missing before retry?
- what should the executor receive?

Default moves:
1. read `references/CHALLENGE-LOOP.md`
2. check local preflight:
   - funds
   - allowance or approval
   - replay guard
   - session or channel continuation state
   - max-spend or policy ceilings
3. normalize one settlement attempt for the local executor or witness builder
4. keep funded execution outside `tusk`

Goal:
Choose one bounded retry path without absorbing wallet custody into the shared
skill.

### 3) Retry and verdict classification
Use when the user asks:
- why did the paid retry fail?
- what counts as success?
- how should we classify this receipt or provider error?

Default moves:
1. emit family-correct retry headers
2. distinguish transport success from provider payment acceptance
3. classify the verdict:
   - accepted
   - verification failed
   - policy blocked
   - retryable transport or provider failure
4. persist the receipt and any state transition needed for the next request

Goal:
Return one crisp outcome without collapsing every failure into "payment
failed."

## Local-first rules
- Treat the live `402` challenge as authoritative over catalogs or docs.
- Keep protocol-family identity explicit on normalized artifacts.
- Keep wire headers family-correct; do not force `x402` through
  `Authorization: Payment ...`.
- Keep funded execution downstream of `tusk`.
- Route canonical signing, session, or witness-domain types to `bridge`.
- Route the future carried witness-realization method to `kurma`, not `tusk`.
- Keep live funded proof and provider quirks in downstream repos such as
  `home`.
- When repo ownership is unclear, route through `topology` before widening the
  lane.

## References
- Read `references/CHALLENGE-LOOP.md` for the normalized `402` flow.
- Read `references/FAMILIES-AND-ROUTING.md` for family boundaries and owner
  split.
- Read `references/WITNESS-ROUTING.md` when the question is really about how a
  paid gate, a concrete method family, and the witness seam fit together.
