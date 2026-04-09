# Tusk Paid HTTP Kernel

This tool is the first extracted paid-request kernel for `tusk`.

It owns the reusable center of machine-paid HTTP without owning:

- provider routing policy
- funded wallets
- signing and settlement execution
- consumer-local mode defaults

Current scope:

- `PaymentAuth` challenge and receipt parsing
- `x402` requirement and receipt parsing
- adapter selection across protocol families
- family-safe retry header encoding
- a generic probe/retry flow that depends on an external adapter result
- discovery normalization for optional `openapi.json` metadata

Deliberately out of scope:

- provider profiles
- live wallet commands
- chain interaction
- settlement retries
- `home`-specific endpoint plans

The intended layering is:

1. `tusk-asy.6.1`: protocol-family boundary
2. `tusk-asy.6.2`: reusable paid-request kernel
3. `tusk-asy.6.3`: wallet / settlement executor contract
4. downstream consumers wire their own provider policy and funded executors

Run tests with a Node host:

```bash
cd tools/paid-http-kernel
nix run nixpkgs#nodejs -- --test test/kernel.test.js
```
