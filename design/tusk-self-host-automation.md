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

The first worker-dispatch seam is now:

- command: `tuskd dispatch-lane`
- public control-plane owner: `tuskd`
- repo/runtime adapter: `tusk-codex`
- first worker engine: `codex exec`

The operator should not treat raw `codex exec` as the public automation API.
`tuskd dispatch-lane` owns the bounded lane contract, structured brief, prompt
materialization, and the `lane.dispatch` receipt, while `tusk-codex` only
adapts the active checkout and tracker roots for the worker process.

The next bounded class is:

- command: `tuskd autonomous-lane`
- issue admission: `task` issues labeled `place:tusk` and `autonomy:v1-safe`
- execution model: claim, launch, `dispatch-lane --mode exec`, run the issue
  Verification commands in the lane checkout, require one clean visible
  revision, then `complete-lane`

That command is intentionally not a scheduler.
It still requires an explicit issue id, and it fails safely by leaving the lane
inspectable when the worker does not cut a visible revision or when
verification fails.

Successful runs append `lane.autonomous` in addition to the underlying
`lane.dispatch` and `lane.complete` receipts.

`board-status` now carries the latest `self_host.run` summary so operators do
not need a separate tool to see whether the fixed-point run last passed or
failed.
