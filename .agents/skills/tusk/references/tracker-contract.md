# Tracker Contract

Use this reference when a lane depends on `bd` and Dolt being healthy, when shared tracker ownership is ambiguous, or when you need to decide whether tracker repair belongs in the lane at all.

## Default Tracker Boundary

- Run `bd` from the canonical tracker root.
- Treat the tracker as shared infrastructure, not as a per-workspace concern.
- If the repo has its own wrapper or root-export helper, use it to override any
  inherited upstream `TUSK_*`, `BEADS_*`, or `DEVENV_*` env before trusting
  tracker commands.
- If the repo has a pinned `bd` wrapper, treat that wrapper as the canonical
  CLI/runtime contract. In `tusk`, outside the dogfood shell use
  `nix run .#bd -- ...`; inside the dogfood shell the flake-owned `bd` on
  `PATH` is already the pinned surface.
- Do not trust `/usr/local/bin/bd`, `~/.local/bin/bd`, or another ambient host
  binary when a repo-owned wrapper or managed shell exists.
- For repos that use `tuskd`, server-mode Dolt is part of the runtime contract. Fresh tracker bootstrap should use `bd init --server`; embedded mode requires explicit migration work.
- The normal `tusk` tracker scope is:
  - read issue state,
  - claim an issue,
  - update an issue,
  - close an issue only when the declared completion boundary is met.

## Readiness Sequence

Run the smallest readiness probe before worker launch:

```bash
cd "$repo_root"
bd ready --json >/dev/null
bd dolt status || true
bd show "$issue_id" >/dev/null
```

- If the repo documents a wrapper or managed shell, use that instead of raw commands.
- If a long-lived service such as `devenv up` keeps Dolt alive, the coordinator should own that session.

For `tusk` itself, read the probe as:

```bash
cd "$repo_root"
nix run .#bd -- ready --json >/dev/null
nix run .#bd -- dolt status || true
nix run .#bd -- show "$issue_id" >/dev/null
```

Inside the dogfood shell, plain `bd` is equivalent because the shell already
pins the wrapper-backed runtime.

## Ownership Rules

- Default shared-backend owner: coordinator.
- Default worker assumption: tracker is already healthy.
- If the tracker is unhealthy, either:
  - repair it in the coordinator shell, or
  - downgrade the lane so the worker does code work only and leaves issue mutation to the coordinator.

## Drift Symptoms

Treat these as tracker/runtime drift until proven otherwise:

- missing-column or unknown-field errors from `bd`
- CLI/database schema-version mismatch warnings paired with read/write failures
- board summary calls working while issue read or create calls fail
- host `bd` resolving a different repo or endpoint than the repo-owned wrapper

These are not ordinary feature-lane failures. They mean the pinned tracker
runtime contract is not actually pinned in the current shell.

## What Does Not Belong In A Normal Lane

Do not treat these as implicit worker responsibilities:

- `bd init`
- first-time Dolt server setup
- migrating an embedded Dolt tracker to server mode for `tuskd`
- tracker schema or admin repair
- tracker migration or data recovery
- flake, shell, or `devenv` authoring required just to make the tracker available

If one of those is actually the task, make it explicit and keep ownership clear. If shell or flake work is required, use the repo's Nix environment skill, such as `nix-interrogation`, when available.

## Degraded Mode

If the tracker is unavailable and you still want code progress:

- tell the worker tracker mutation is out of scope for this run,
- require exact reporting of the failing command and error, and
- keep final issue updates or closure in the coordinator shell.

If the failure smells like drift, report:

- which `bd` surface was used
- whether it came from the repo wrapper, managed shell, or host `PATH`
- the exact schema or unknown-field error
- whether the repo-owned wrapper succeeds differently

## Finish Rules

- Re-run tracker readiness before `bd update` or `bd close` at the end of the lane.
- Do not close an issue just because the code changed. Closure depends on the declared landing or completion boundary.
