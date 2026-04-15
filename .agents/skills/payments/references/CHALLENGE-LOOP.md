# Challenge Loop

Use this when the task is concretely about executing or diagnosing one
paid-access retry loop.

## Normalized loop

1. `Probe`
   - Send the unauthenticated or under-authenticated request.
   - Record the full response.

2. `Gate`
   - Confirm the response is actually a paid-access challenge.
   - For HTTP, `402` is the outer signal.

3. `Family`
   - Classify the paid-request family from the live response, not from a
     marketing page.
   - Current shared families here are:
     - `paymentauth`
     - `x402`

4. `Method or scheme`
   - Inside the family, identify the concrete method or scheme.
   - Examples:
     - `tempo` under `paymentauth`
     - `exact` under `x402`

5. `Preflight`
   - Check only the local conditions the next retry actually depends on:
     - funds
     - allowance or approval
     - replay guard state
     - local channel or session continuation state
     - max-spend policy
     - whether the local executor is even capable of the requested family and
       method

6. `Settlement attempt`
   - Build one normalized executor or witness attempt.
   - The shared seam in `tusk` is:
     - request context
     - family
     - challenge or requirement
     - selected method or scheme
     - credential template
     - policy hints
   - Do not move wallet custody or live chain submission into the shared
     surface.

7. `Retry`
   - Emit the family's real wire headers.
   - Keep the family boundary explicit all the way through retry.

8. `Verdict`
   - Classify the provider result narrowly:
     - success with receipt
     - verification failure
     - policy refusal
     - retryable transport or provider failure
   - A settled payment is not automatically a successful provider response.

9. `Persistence`
   - Store the receipt and any state transition needed for the next request:
     - accepted cumulative amount
     - channel or session id when the provider exposed one
     - refusal fingerprint for replay guards

## Practical guardrails

- Never skip directly from `402` to funded execution without family
  classification.
- Never assume every provider that uses `402` uses the same settlement
  contract.
- Never collapse session continuation, replay, or allowance problems into
  generic "invalid payload" if a narrower local diagnosis exists.
- Never let `tusk` become the funded wallet owner just because the shared loop
  needs to mention money.
