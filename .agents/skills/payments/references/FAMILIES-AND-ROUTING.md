# Families And Routing

Use this when the question is less "how do I retry?" and more "what belongs in
`tusk` versus somewhere else?"

## Family boundary

The reusable center in `tusk` is the paid-request family boundary, not one
provider and not one funded runtime.

Current family split:

## `paymentauth`

Typical runtime shape:
- probe returns `402`
- challenge lives in `WWW-Authenticate`
- retry carries `Authorization`
- receipt may return in `Payment-Receipt`

This family is method-oriented.
`tempo` is one concrete method under it.

## `x402`

Typical runtime shape:
- probe returns `402`
- requirement lives in `PAYMENT-REQUIRED`
- retry carries `PAYMENT-SIGNATURE`
- receipt may return in `PAYMENT-RESPONSE`

This family is scheme-oriented.

## Consequence

Do not treat:
- `x402` as "another PaymentAuth adapter"
- provider-local free or API-key fallbacks as payment families
- a funded executor as part of the shared kernel

## Ownership split

### `tusk` owns
- the operator-facing `402` challenge loop
- family classification
- normalized executor-attempt boundary
- family-correct retry and receipt reasoning
- high-level routing to the real owner when the question leaves shared infra

### `bridge` owns
- canonical signing, session, witness, and materialization-domain types when
  the question is really about those typed contracts

### `kurma` owns
- the future carried `Nerve` or witness-realization method once the seam
  proves stable across consumers

### downstream repos such as `home` own
- funded runtime truth
- provider-specific proof work
- live chain submission and confirmation
- operator secrets and wallet custody

## When to route away

- Route to `topology` when repo ownership or simplex shape is still unclear.
- Route to `bridge` when the question is really about canonical witness or
  signing-session types.
- Keep live provider settlement diagnosis in the downstream proof repo until a
  stable shared boundary emerges.
