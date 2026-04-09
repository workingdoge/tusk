# Tusk Paid HTTP Protocol Boundary

## Status

Decision note for the first reusable paid-request protocol boundary that `tusk`
should own.

## Intent

`tusk` should own the protocol boundary for machine-paid HTTP requests without
owning funded wallets, provider routing policy, or settlement-specific runtime
code.

The useful reusable center is:

- request and probe artifacts
- protocol-family normalization
- challenge and requirement parsing boundaries
- retry request artifacts
- receipt normalization

The non-reusable edge is:

- provider selection
- consumer-local mode choice
- funded wallet custody
- live settlement execution

This note fixes that split before the current `home/scripts/mpp-payer/`
surface gets extracted into `tusk`.

## Two Protocol Families

`tusk` should treat `PaymentAuth` and `x402` as distinct protocol families.

They both fit the broader "paid HTTP" track, but they do not share the same
wire contract.

### `PaymentAuth`

Runtime boundary:

- unauthenticated probe returns `402`
- challenge lives in `WWW-Authenticate: Payment ...`
- retry carries `Authorization: Payment <base64url-json>`
- receipt may come back in `Payment-Receipt`

This family is method-oriented.
The current `home` surface models it with method hints such as `tempo`.

### `x402`

Runtime boundary:

- unauthenticated probe returns `402`
- requirement lives in `PAYMENT-REQUIRED`
- retry carries `PAYMENT-SIGNATURE`
- receipt may come back in `PAYMENT-RESPONSE`

This family is scheme-oriented.
The current `home` surface models it with scheme hints such as `exact`.

### Consequence

`x402` must not be forced through the `PaymentAuth` retry shape.

In particular:

- `x402` is not "another `Authorization: Payment ...` adapter"
- `PaymentAuth` request/receipt headers must stay distinct from `x402`
- shared runner logic should normalize family boundaries without erasing them

## Protocol Families Versus Execution Modes

The current `home` runner has modes such as:

- `free`
- `api_key`
- `tempo_request`
- `tempo_mpp`
- `x402`

Those are not all protocol families.

For `tusk`, the reusable split should be:

- `mode`: consumer-local execution choice
- `protocol family`: reusable paid-request wire contract
- `executor`: settlement/signing/runtime implementation

So:

- `free` and `api_key` are not machine-payment protocol families
- `tempo_request` is a client mode that bypasses the generic adapter path
- `tempo_mpp` is a `PaymentAuth`-family execution mode
- `x402` is both a mode name in `home` and a real protocol family

`tusk` should extract the family boundary first and keep mode policy
downstream.

## Reusable Artifact Set

The first reusable artifact set should be explicit and typed.

### `PaidRequest`

The outbound request before payment logic:

- URL
- method
- body digest or body reference
- consumer-local auth policy
- probe policy
- price policy or max-spend hints

This artifact is protocol-generic.

### `PaymentChallenge`

The normalized `PaymentAuth` challenge artifact:

- family = `paymentauth`
- raw header source
- parsed challenge entries
- supported methods
- request payload
- opaque payload
- expiry or digest fields when present

### `PaymentRequirement`

The normalized `x402` requirement artifact:

- family = `x402`
- raw header source
- parsed accepts entries
- supported schemes
- amount / network / asset fields when present
- provider-specific requirement payload

### `PaidResponse`

The normalized retry authorization artifact produced by a local executor or
adapter:

- family
- full headers when already encoded
- or family-specific payload fields:
  - `authorization` / `credential` for `PaymentAuth`
  - `paymentSignature` / payload for `x402`
- optional metadata for later receipts

`tusk` should allow the executor to return complete headers, but should also
define safe family-specific fallback encoding when only the protocol payload is
returned.

### `PaidReceipt`

The normalized server-side payment receipt artifact:

- family
- raw receipt header or payload
- parsed receipt body
- reference / transaction id when present
- status when present
- provider-local opaque metadata preserved without being normalized away

## Normalization Rules

`tusk` should own a small set of normalization rules.

1. Discovery is advisory.
   `openapi.json` or provider metadata may help choose a mode, but the
   authoritative runtime boundary is still the `402` challenge or requirement.

2. Family identity is explicit.
   Every normalized challenge, requirement, retry response, and receipt must
   carry its protocol family.

3. Wire headers stay family-correct.
   Shared code may normalize internal artifact names, but it must emit the
   family's real wire headers when building the retry request.

4. Executors may return either protocol payloads or full headers.
   `tusk` should not force every executor to pre-encode headers if a
   family-safe fallback encoding exists.

5. Receipt normalization preserves opaque provider detail.
   `tusk` may normalize common fields such as `reference` or `status`, but it
   must not erase raw provider artifacts that later operators or downstream
   consumers may need.

## Ownership Split

### `tusk` owns

- protocol-family definitions
- normalized request / challenge / requirement / response / receipt artifacts
- family-safe fallback encoding rules
- receipt normalization shape
- the boundary between protocol parsing and executor invocation

### Consumer-local repos own

- endpoint and provider selection
- user or product policy
- price ceilings and routing heuristics
- mode defaults such as `tempo_request` versus `tempo_mpp`

### Provider-local surfaces own

- method- or scheme-specific challenge semantics
- non-generic metadata
- provider discovery documents
- service-specific settlement expectations

### Wallet/executor implementations own

- funded keys
- signing
- chain interaction
- broadcast or settlement retries
- local secret custody

This keeps `tusk` on the reusable orchestration boundary instead of turning it
into a billing product or wallet manager.

## First Extraction Shape

The first extraction into `tusk` should be:

1. protocol-family note and artifact vocabulary
2. parser/normalizer boundary for `PaymentAuth` and `x402`
3. generic retry artifact model
4. receipt normalization model

Only after that should the runner and executor layers move:

- `tusk-asy.6.2` should extract the shared paid-fetch kernel and runner shape
- `tusk-asy.6.3` should define the wallet / settlement executor contract

## Recommendation

Proceed as if:

- paid HTTP is one incubation track with at least two protocol families
- `PaymentAuth` and `x402` are siblings, not one wrapped inside the other
- `tusk` owns protocol normalization, not wallet execution
- mode policy stays consumer-local until the kernel is extracted
- and settlement remains downstream of a clean protocol boundary

The first extracted kernel for this boundary now lives under
[`tools/paid-http-kernel`](../tools/paid-http-kernel/README.md).

The settlement seam beneath that kernel now lives in
[`design/tusk-paid-http-executor-contract.md`](./tusk-paid-http-executor-contract.md).
