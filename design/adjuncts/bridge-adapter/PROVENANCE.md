# Bridge Adapter Provenance

This adjunct spec family was imported from:

- `/Users/arj/irai/bridge_spec_v0_2_adapter_bundle.zip`

The imported bundle root was `bridge_spec_v0_2_adapter/`.

## Relationship To Tusk

- This surface defines the bridge adapter contract: external authorize request,
  authoritative provider results, assembled policy input, decision envelope,
  audit record, and mode/admin objects.
- It is a repo-owned adjunct contract surface in `tusk`.
- It is **not** part of the Tusk kernel series under `design/specs/`.

## Repo Ownership

After import, the copies under `design/adjuncts/bridge-adapter/` are the
authoritative files for this repo. The ambient zip file is staging provenance,
not live authority.

## Status

- Imported as bridge adapter adjunct spec family `v0.2`.
- The contract surface is present in-tree.
- The Rust adapter/runtime implementation is not part of this import lane.

## Edit Rule

- Preserve the imported contract surface and examples unless there is an
  intentional, reviewable reason to change them.
- Record any future semantic divergence here or in a companion note rather than
  silently drifting from the imported bundle.
