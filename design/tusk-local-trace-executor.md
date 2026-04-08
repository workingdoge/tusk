# Tusk Local Trace Executor

## Status

Normative note for the first concrete executor surface shipped by `tusk`.

## Intent

The first executor should be:

- local,
- safe,
- deterministic,
- and strong enough to emit runtime receipts without needing remote authority.

That is the role of `local-trace`.

It does not deploy, open PRs, or mutate upstream systems.
It only records that one admitted realization was carried through the
repo-local control plane.

## Export Surface

The repo-local `tusk` instantiation now exports:

- executor id: `local-trace`
- driver id: `local.receipts`
- effect id: `self.trace-core-health`
- realization id: `self.trace-core-health.local`

The runtime entrypoint is:

- `nix run path:.#tusk-trace-executor -- --realization self.trace-core-health.local`

That entrypoint reads `path:.#tusk`, checks realization admission, and appends
one receipt through `tuskd-core`.

## First Trace Path

The first concrete realization traces the witness root from
`design/tusk-self-host-witnesses.md`:

- `base.self.codex-nix-check.contract`
- `base.self.tuskd-core-build.binary`
- `base.self.tusk-ui-build.binary`
- `base.self.tuskd-status.service`

Its meaning is:

- consume the first self-host witness set,
- bind it to a safe local executor,
- and emit one repo-local receipt that later operator views can project.

## Receipt Contract

The receipt kind is:

- `effect.trace`

The payload records:

- the realization id,
- realization admission state,
- the bound effect, executor, and driver,
- the consumed witnesses and required base entries,
- and the expected receipt metadata declared on the realization.

This is enough for later slices to build richer admission and automation logic
without redefining the executor boundary.

## Non-Goals

This executor does not:

- prove remote transport semantics,
- replace later GitHub or Hercules executors,
- or decide broader policy admission.

It only establishes the first safe runtime carrier for admitted effects.
