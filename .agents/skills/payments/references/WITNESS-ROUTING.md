# Witness Routing

Use this when the question is not only "how do I retry?" but "what kind of
thing is this retry loop actually asking for?"

## Three layers

Keep these layers separate:

1. outer paid gate
2. concrete family and method
3. witness-realization seam

The important rule is:

- `402` is the outer gate
- a concrete paid family sits under that gate
- one method or scheme sits inside that family
- the witness or executor boundary is the local realization seam

Do not collapse those into one pseudo-method.

## Outer gate

For HTTP, the shared prompt is usually `402`.

That does **not** tell you:

- which family is active
- which method or scheme is active
- which artifact the provider expects on retry

It only tells you there is a priced or governed access gate in front of the
request.

## Concrete families and methods

Current shared family split in `tusk`:

- `paymentauth`
- `x402`

Inside those families, the concrete retry object differs.

Examples:

- `tempo` is one method under `paymentauth`
- `exact` is one scheme under `x402`

That means one agent should never assume:

- every `402` means the same retry contract
- every `paymentauth` challenge means the same method
- a funded executor can be reused across families without translation

## Concrete method sketch: Tempo session

One current downstream proof shape is a `tempo` session method:

```text
request
  -> 402
  -> family = paymentauth
  -> method = tempo
  -> intent = session
  -> state read
  -> action selection
  -> witness artifact
  -> provider validation
  -> receipt/state update
```

The state read here is method-specific. It may depend on:

- allowance or approval
- replay state
- session or channel continuation state
- priced amount
- whether the next action is `open`, `topUp`, `voucher`, or `close`

That is why `tempo` stays a concrete method-family case, not the generic law.

## Sibling method sketch: double-entry

A `double-entry` family or method belongs in the same slot as `tempo`, not
above it.

Its runtime shape would still begin at the outer paid gate, but the state and
artifact rules would differ:

```text
request
  -> challenge
  -> family or method = double-entry
  -> journal/account state read
  -> action selection
  -> journal-backed witness
  -> validator verdict
  -> receipt/state transition
```

The key point is simple:

- `double-entry` is a sibling candidate beside `tempo`
- it is not the outer gate
- it is not the generic witness seam

## Generic seam: witness realization

The generic seam lives one level up from any one method family:

```text
Challenge
  -> StateRead
  -> ActionSelection
  -> WitnessPlan
  -> WitnessArtifact
  -> ValidatorProfile
  -> ValidationResult
  -> StateTransition
```

This is the right abstraction when the question is:

- how one bounded intent becomes a validator-acceptable public artifact
- what state matters before retry
- what verdict or receipt updates the next attempt

This is **not** owned by `tusk` as doctrine.
`tusk` only packages enough of it to route other agents correctly.

## Ownership split

### `tusk`

Owns:

- the operator-facing challenge loop
- family and method routing
- shared workflow guidance for retry and receipt handling

### `bridge`

Owns:

- canonical signing, session, witness, and materialization-domain types when
  the question is really about those typed contracts

### `kurma`

Owns:

- the future carried witness-realization method once it is stable enough to be
  reusable across consumers

### tracked upstream `fish`

Owns:

- the higher-level meaning notes when the real question is doctrinal rather
  than operational

### downstream proof or product repos

Own:

- funded runtime truth
- provider-specific settlement quirks
- live chain submission or journal mutation
- wallet custody and operator secrets

## Practical routing rule

If the user is asking:

- "how do I run or classify this `402` loop?"
  - stay in `$payments`
- "what canonical witness or session type is this?"
  - route to `bridge`
- "what is the general witness method above these families?"
  - route upstream, eventually to `kurma`
- "why did this one live provider reject the paid retry?"
  - stay in the downstream proof or product repo
