# Tusk Bootstrap Freeze

## Status

Frozen bootstrap baseline for `tusk` consumer adoption.

This note records the line that is considered stable enough to consume from
other repos without continuing to redesign `tusk` core in parallel.

## Frozen Boundary

The frozen `tusk` surface is the bootstrap substrate carried by the consumer
line rooted at `bootstrap-skills` and explicitly signaled by the
`bootstrap-frozen` bookmark.

That frozen surface includes:

- `lib.tusk.bootstrap.mkRepoShell`
- the shared repo-shell constructor in `repo-shell-lib.nix`
- shared skill sources under `.agents/skills/`
- store-backed projection of shared and consumer-local skills into
  repo-local `.codex/skills/`
- the packaged `tusk-openai-skill`
- the repo-local development shell used to dogfood the bootstrap flow

## Explicit Non-Goals Of The Freeze

This freeze does **not** freeze or activate:

- `lib.tusk.operational` as a stable public contract
- the workflow topology note as required consumer machinery
- the tracker lease service as required infrastructure
- the downstream operational calculus as `tusk` core mission
- optional automation adapters such as Hercules or GitHub transports

Those remain downstream design or future implementation work.

## Change Policy

Changes on the frozen bootstrap line SHOULD be limited to:

- bug fixes in the bootstrap shell or skill projection path
- verification fixes needed to keep current consumers healthy
- dependency or toolchain refreshes when they unblock real consumers
- documentation clarifications that reduce ambiguity in the frozen boundary

Changes on the frozen bootstrap line MUST NOT silently introduce:

- new control-plane semantics
- new automation or transport layers
- widened public surface area beyond the bootstrap contract
- consumer-specific behavior that has not generalized
- redefinition of repo-local tracker or landing authority

If broader changes are needed, they SHOULD begin from a new issue and a new
line rather than accreting onto the frozen baseline by drift.

## Consumer Guidance

Repos that only need disciplined bootstrap SHOULD consume the frozen line.

The intended reading order for that line is:

1. `design/tusk-freeze.md`
2. `design/tusk-bootstrap-contract.md`
3. `AGENTS.md`

Repos that want downstream operational or automation work SHOULD treat those as
separate opt-in tracks rather than as part of bootstrap adoption.

## Tracker Posture

The automation epic and its child issues are intentionally deferred under this
freeze.

That means:

- bootstrap remains the active supported mission
- optional automation remains visible in the tracker
- optional automation is not part of the current execution path
