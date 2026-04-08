# Tusk Self-Host Automation

## Status

Normative note for the first fixed-point automation slice over `tusk` itself.

## Intent

The first self-hosting loop should use the tools already in tree:

- `tusk` to shape and track the work,
- `nix` to execute the real repo checks and builds,
- `tuskd` to record the run as authoritative receipts.

The goal is not to replace `nix build`.
The goal is to let `tusk` govern and receipt its own builds.

## First Slice

The first slice is:

- command: `tuskd self-host-run`
- default realization: `self.trace-core-health.local`

That run executes the current self-host witness set:

- `nix run path:.#codex-nix-check`
- `nix build path:.#tuskd-core`
- `nix build path:.#tusk-ui`
- `nix run path:.#tuskd -- status --repo "$PWD"`

When those steps pass, the runner then invokes the existing local trace
executor and records:

- `effect.trace`
- `self_host.run`

## Why This Is The Fixed Point

This is the first place where the control plane is used to strengthen the
control plane itself:

- the repo declares the witness graph,
- the runner executes the real build/check surface,
- the trace executor emits the semantic receipt,
- and `tuskd` keeps the authoritative audit trail.

That is enough to say the system can use its own governed loop around one real
self-hosting build slice.

## Operator Surface

The latest self-host run is visible through:

- `tuskd receipts-status`
- `tuskd board-status`

`board-status` now carries the latest `self_host.run` summary so operators do
not need a separate tool to see whether the fixed-point run last passed or
failed.
