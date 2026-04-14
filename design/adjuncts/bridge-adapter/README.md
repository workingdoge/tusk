# Bridge Adapter Bundle v0.2

This bundle adds the missing adapter layer between:

1. the external caller request,
2. authoritative verification providers, and
3. the existing bridge policy contract consumed by Rego/Cedar.

## Main idea

The adapter does three jobs:

- takes an external `AuthorizeRequest`,
- resolves authoritative provider facts,
- assembles `PolicyInput` for the policy engine.

The caller never supplies `preflight` booleans directly.

## Placement and ownership

- This bundle is a repo-owned adjunct contract surface in `tusk`, not Tusk
  kernel law.
- The companion ownership note is `../../notes/tusk-bridge-topology.md`.
- The first Tusk-owned runtime surface over this contract lives in
  `crates/tusk-bridge-adapter/`.
- The stable repo-owned conformance entrypoint for this adjunct surface is
  `nix run .#tusk-bridge-conformance-check -- --repo <checkout>`.
- The optional bridge edge-contract entrypoint is
  `nix run .#tusk-bridge-conformance-check -- --repo <checkout> --bridge-flake <flake-ref>`.
  That path treats the external `bridge` flake as canonical and verifies that
  it exports `bridge-conformance-check`, `bridge-property-check`, and
  `reference-planner`.
- Public doctrine belongs in `fish`, reusable carriage belongs in `kurma`, and
  live provider/policy/secrets proof belongs in a downstream repo unless the
  boundary later proves to be shared operational infrastructure.

## Files

- `adapter-contract.md` — normative contract and assembly rules
- `provider-mapping.yaml` — which provider populates which field
- `schemas/authorize.request.schema.json` — external request
- `schemas/provider-results.schema.json` — authoritative provider facts
- `schemas/policy-input.schema.json` — assembled policy input
- `schemas/decision.schema.json` — decision envelope returned by the policy layer
- `schemas/audit-record.schema.json` — durable audit record shape
- `schemas/mode-command.schema.json` — burn/restore command shape
- `schemas/mode-state.schema.json` — current mode state shape
- `openapi/bridge-adapter.openapi.yaml` — starter API surface
- `python/reference_adapter.py` — reference assembler and validator
- `examples/` — example requests, provider results, policy inputs, decisions, and mode objects

## Reference adapter usage

```bash
python reference_adapter.py \
  --authorize-request ../examples/example.authorize-request.json \
  --provider-results ../examples/example.provider-results.accept.json \
  --out ../examples/out.policy-input.json \
  --audit-out ../examples/out.audit-record.json
```

The script validates the request and provider result schemas, assembles the internal policy input, validates the policy input shape, and emits an audit stub.

## Important rule

The adapter MUST treat all caller input except the witness and call facts as untrusted. It is the adapter's job to turn authoritative results into `input.preflight`, `input.events`, and the authoritative parts of `input.runtime_request`.
