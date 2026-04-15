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

For `tusk`, the canonical preflight is `tuskd doctor`. It bundles the four tracker invariants and emits one specific repair per failure:

```bash
cd "$repo_root"
tuskd doctor --repo "$repo_root"                # human
tuskd doctor --repo "$repo_root" --json | jq .  # programmatic
```

The invariants covered:

| Name           | Checks                                                                  |
|----------------|-------------------------------------------------------------------------|
| `dolt-mode`    | server mode is active (not embedded)                                    |
| `supervisor`   | `.beads/dolt-server.pid` is live and `.beads/dolt-server.port` is bound |
| `dolt-remote`  | configured remote URLs parse into a known scheme                        |
| `beads-perms`  | `.beads/` is 0700 (warn on 0750/0755, fail on world-anything)           |

A non-zero exit means at least one invariant failed; the stdout lines name which and carry the exact repair command.

For fine-grained checks or drift diagnosis, fall back to raw `bd`:

```bash
cd "$repo_root"
bd ready --json >/dev/null
bd dolt status || true
bd show "$issue_id" >/dev/null
```

- If the repo documents a wrapper or managed shell, use that instead of raw commands.
- If a long-lived service such as `devenv up` keeps Dolt alive, the coordinator should own that session.

Outside the dogfood shell in `tusk`, prefix with `nix run .#bd -- …` and `nix run .#tuskd -- …`. Inside the dogfood shell, plain `bd` and `tuskd` are equivalent because the shell pins the wrapper-backed runtime.

## Supervisor Singletons

The Dolt supervisor is a per-checkout singleton. In `tusk` 2026-04 and later, prefer the `tuskd supervisor-*` verbs over raw `bd dolt start`:

- `tuskd supervisor-start --repo "$tracker_root"` — idempotent. No-op and JSON success when a supervisor is already alive; acquires an atomic `mkdir` lock under `.beads/tuskd/supervisor.start.lock/` before shelling to `bd dolt start`; refuses concurrent starts.
- `tuskd supervisor-attach --repo "$tracker_root"` — verify-only. Returns `{ok:true, role:"attach", pid, port}` when alive, or `{ok:false, error:{kind:"supervisor-down"}}` when not. Never starts anything. Workers should use this.
- `tuskd supervisor-stop --repo "$tracker_root" [--force]` — shells to `bd dolt stop`; with `--force` falls back to SIGTERM on the recorded pid when bd's own stop fails.

Raw `bd dolt start` still works, but it has no concurrent-start protection: running it twice in parallel can leave orphan Dolt processes holding the data-dir lock while the latest pid file points at a dead pid. The `tuskd supervisor-*` wrappers exist to make that class of failure impossible by construction.

## Read Projections and Degraded Mode

Six read projections in `tusk` surface a top-level `"degraded"` field when the supervisor is down rather than crashing or hanging:

- `tuskd status`
- `tuskd coordinator-status`
- `tuskd sessions-status`
- `tuskd receipts-status`
- `tuskd operator-snapshot`
- `tuskd board-status`

The field shape is stable:

```json
{ "degraded": { "reason": "supervisor-down", "repair": "bd dolt start" } }
```

When the supervisor is healthy, the field is absent — consumers can branch on `jq -e '.degraded'` without extra defense. UIs and coordinator shells should surface the repair line instead of interpreting a sea of `ok: false` subfields.

## Workspace-Lane Commands Preflight

Ten workspace-lane commands gate on the supervisor at dispatch and fail fast with a doctor pointer when it is down:

`launch-lane`, `dispatch-lane`, `autonomous-lane`, `handoff-lane`, `finish-lane`, `lane-park`, `lane-abandon`, `archive-lane`, `complete-lane`, `compact-lane`.

None of them will start Dolt; they refuse and tell the caller to run `tuskd supervisor-start` or `tuskd doctor`. This keeps lifecycle ownership explicit: the coordinator owns the supervisor; the lane commands consume a healthy one.

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
