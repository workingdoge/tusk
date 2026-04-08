# Tusk Self-Host Witnesses

## Status

Normative note for the first concrete self-hosting witness set exported by
this repo.

## Intent

The first fixed-point loop for `tusk` should start from a narrow witness set
over `tusk` itself.

That set should be:

- real,
- repo-owned,
- small enough to review,
- and strong enough that later executor and self-hosting work can consume it
  without redefining the witness vocabulary.

## Export Surface

The canonical normalized witness graph is exported from this repo at:

- `path:.#tusk.base`
- `path:.#tusk.witnesses`
- `path:.#tusk.graph`

This is the repo-local instantiation of the generic `flakeModules.tusk`
surface.

## First Witness Set

The first self-hosting witness set is:

1. `self.codex-nix-check`
   Witness id: `base.self.codex-nix-check.contract`
   Meaning: the repo-local flake/runtime/skill smoke contract passes through
   `codex-nix-check`.

2. `self.tuskd-core-build`
   Witness id: `base.self.tuskd-core-build.binary`
   Meaning: the Rust coordinator core builds from the canonical repo toolchain.

3. `self.tusk-ui-build`
   Witness id: `base.self.tusk-ui-build.binary`
   Meaning: the operator-facing TUI builds from the canonical repo toolchain.

4. `self.tuskd-status`
   Witness id: `base.self.tuskd-status.service`
   Meaning: the repo-local control-plane service can publish a status snapshot
   through `tuskd`.

## Why These Four

This first set is intentionally narrow.

It covers:

- the shared repo/runtime contract,
- the core coordinator build,
- the operator surface build,
- and one repo-state observation over the control plane.

That is enough for the next slices to reason about:

- "can `tusk` still build itself?"
- "can `tusk` still observe its own control plane?"

without jumping straight to remote automation, deployment, or consumer repos.

## Non-Goals

This witness set does not try to model:

- every package in the repo,
- every tracker or lane fact,
- remote automation state,
- or multi-repo witness federation.

Those can land later if the first loop proves too small.

## Relationship To Later Slices

This note is the witness root for the next two core tasks:

- `tusk-asy.2.4`: local trace executor
- `tusk-asy.2.5`: first receipted self-hosting automation slice

Those slices should consume these witnesses rather than redefine a second
self-hosting witness vocabulary.
