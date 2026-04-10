# Tusk Paid HTTP Executor Contract

## Status

Decision note for the wallet / settlement executor boundary beneath
`tools/paid-http-kernel`.

## Intent

`tusk` now owns the generic paid-request kernel:

- parse a protocol-family challenge or requirement
- select an adapter boundary
- build the retry request
- normalize the resulting receipt

It should not own funded wallets, chain transactions, or provider-local payment
policy.

The missing seam is the executor contract between:

- the `tusk` kernel, which knows the protocol family and selected settlement
  boundary
- and a consumer-local settlement implementation, which can sign, submit, or
  otherwise satisfy the payment challenge

This note fixes that seam.

## Ownership Rule

### `tusk` owns

- the normalized settlement-attempt shape
- the family-safe output contract for retry headers
- receipt normalization expectations
- retryable versus non-retryable failure classification

### consumer-local executors own

- funded key custody
- wallet/runtime configuration
- chain submission and confirmation
- provider-specific settlement operations
- command/process wiring for the chosen executor backend

### consequence

`tusk` should call a consumer-local settlement executor, not absorb it.

## Settlement Attempt

The kernel should hand one explicit settlement attempt to the executor.

Required fields:

- `executorId`
  The selected consumer-local executor implementation, for example
  `tempo-charge`.
- `protocolFamily`
  `paymentauth` or `x402`.
- `request`
  The outbound paid request context:
  - URL
  - method
  - body
  - request headers before settlement
- `challenge`
  Present for `PaymentAuth` families.
- `requirement`
  Present for `x402` families.
- `accept`
  Present when the server advertised multiple settlement schemes or variants.
- `credentialTemplate`
  The family-shaped payload template the executor is expected to fill.
- `policy`
  Consumer-local execution policy that the kernel can pass through, such as
  max-spend hints.

Optional fields:

- `previousReceipt`
- `metadata`
- `attemptId`

The important property is that the executor receives one normalized attempt
shape independent of the consumer repo's internal wallet code.

## Settlement Success

A successful executor result should return enough information for the kernel to
construct the retry request without learning wallet internals.

Allowed result forms:

- full `headers`
- or family-specific payload fields:
  - `authorization` / `credential` for `PaymentAuth`
  - `paymentSignature` / `payload` for `x402`

Optional success fields:

- `paymentReceipt`
- `metadata`
- `source`

The kernel then normalizes success into:

- `retryHeaders`
- optional `paymentReceipt`
- optional `metadata`

This keeps the wire contract generic while still letting a consumer-local
executor expose useful diagnostics.

## Settlement Failure

An executor failure should not collapse into a bare string.

The normalized failure shape should include:

- `ok = false`
- `retryable`
- `category`
- `message`
- optional `details`

Suggested failure categories:

- `config`
- `policy`
- `wallet`
- `provider`
- `transport`
- `unknown`

Examples:

- missing signer env is `config`, not retryable until repaired
- max-spend refusal is `policy`, not retryable without operator change
- transient RPC timeout is `transport`, retryable
- server-side settlement rejection is `provider`, maybe retryable depending on
  details

The kernel should preserve that classification and avoid rewriting every
failure into a single opaque "adapter failed" message.

## Current `home` Mapping

Today the `home` stack already approximates this split:

- the kernel-side adapter boundary is in
  `scripts/mpp-payer/adapters/tempo-charge-adapter.js`
- the funded executor is the Rust command behind
  `scripts/mpp-payer/tempo-payer-command.sh`
- the Rust command reads normalized stdin and returns protocol-shaped JSON

So the contract in `tusk` should be read as stabilizing that boundary, not
inventing a new second executor stack.

## First Shared Module Surface

The shared module surface in `tusk` should stay small:

- `buildSettlementAttempt`
- `normalizeSettlementSuccess`
- `normalizeSettlementFailure`

That is enough for:

- `home` to adapt its existing Tempo executor onto the shared boundary
- future `x402` executors to target the same kernel contract
- `AAC` or other consumers to reuse the kernel without inheriting `home`'s
  wallet runtime

## Recommendation

Proceed as if:

- the paid-http kernel stays wallet-agnostic
- the executor contract is the only shared settlement seam
- consumer repos own funded execution
- and downstream adoption should depend on this contract instead of copying the
  current `home` runner wholesale
