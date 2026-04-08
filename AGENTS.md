# Agent Instructions

These instructions apply to the canonical `tusk` repo checkout.

## Workflow

- Use `nix develop --no-pure-eval path:.` or `direnv allow` before tracker or workflow work.
- The dev shell provides a flake-owned `bd` wrapper, `tusk-flake-ref`, `tusk-tracker`, `tusk-claude`, `tusk-codex`, `tusk-skill-contract-check`, `tusk-skill-loop`, `dolt`, `jj`, `deadnix`, `statix`, `nil`, `nixd`, `nix-tree`, `nix-output-monitor`, `nixfmt`, `codex`, `tuskd`, `glistix`, `gleam`, `erl`, `rebar3`, a `rust-overlay` toolchain for `cargo`/`rustc`/`rustfmt`, and `rust-analyzer`.
- Run `devenv up` inside the dev shell to ensure repo-scoped tracker services when `.beads/` exists. `tuskd ensure` owns backend reuse and host-local coordination; shells must not stop Dolt on exit.
- Bootstrap fresh trackers for `tuskd` with `bd init --server`; embedded Dolt mode is not a valid `tuskd` substrate.
- Use this repo to develop `tusk` as a standalone flake and skill/tooling home; keep consumer-specific `bd-*` wrappers in the consuming repo unless they are intentionally promoted.
- When changing the canonical repo home, prefer a fresh `jj git clone --colocate` from the exported `main` line and re-bootstrap local `.beads/` runtime state there instead of moving the live `.jj/` directory in place.
- Use `glistix` for Nix-target Gleam work; the shell also keeps upstream `gleam` available for generic tooling and language-server compatibility checks.
- Use `lib.crane` from the flake for Rust package definitions so Rust builds share the same pinned `rust-overlay` toolchain as the shell, and run packaged Rust apps via `nix build` / `nix run` instead of mutating manifests ad hoc from outside Nix.
- `tuskd` writes repo-local service state under `.beads/tuskd/` and a host-local registry under `$TUSK_HOST_STATE_ROOT`, `$XDG_STATE_HOME/tusk`, or `~/Library/Caches/tusk` on macOS.
- Runtime wrappers distinguish the active checkout root (`TUSK_CHECKOUT_ROOT` / `DEVENV_ROOT`) from the canonical tracker root (`TUSK_TRACKER_ROOT` / `BEADS_WORKSPACE_ROOT`); workspace-local `CODEX_HOME` follows the checkout, while tracker state stays in the canonical repo.
- Use `tusk-codex --checkout <workspace>` when you need Codex to follow a live lane workspace, `tusk-claude --checkout <workspace>` when you want Claude Code to read repo-local `.claude/skills` from that workspace, and `tusk-skill-loop --checkout <workspace>` when iterating on `.agents/skills/**`; the loop validates before restart and does fast relaunch rather than pretending in-process hot reload exists.
- `tuskd` is the coordinator action and receipt surface; `tusk-tracker` is the internal tracker adapter seam behind it.
- `tusk-radicle` is the repo-owned helper for attaching the canonical checkout to the live Radicle RID while preserving GitHub as the `main` upstream.
  `tusk-radicle status` also surfaces best-effort publish drift between local `main`, `origin`, and `rad`.
- `.beads/tuskd/lanes.json` is the first-class lane state record; receipts remain the audit log of lane transitions.
- Outside the dev shell, use `nix run .#bd -- ...` instead of an ambient host `bd`; the wrapper reads the `tuskd` service record and exports the repo-scoped Dolt endpoint before execing Beads.

## Quick Reference

```bash
nix develop --no-pure-eval path:.
devenv up
bd init -p tusk --server
bd ready --json
bd status --json
nix run .#tusk-tracker -- status --repo "$PWD"
nix run .#tusk-tracker -- issues board --repo "$PWD"
nix run .#tusk-tracker -- backend show --repo "$PWD"
nix run .#bd -- status --json
jj st
nix build .#tusk-openai-skill
nix run .#install-tusk-openai-skill
nix run .#tusk-flake-ref -- --json
nix run .#tusk-radicle -- status
nix eval --raw path:.#packages.aarch64-darwin.rust-toolchain.name
nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.crane.buildDepsOnly
nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'
nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && glistix --help >/dev/null && erl -eval "erlang:halt()." -noshell >/dev/null && rebar3 version >/dev/null && cargo --version >/dev/null && rustc --version >/dev/null && rustfmt --version >/dev/null && rust-analyzer --version >/dev/null'
codex-nix-check
tusk-codex --launcher-help
tusk-claude --launcher-help
tusk-skill-contract-check
tusk-skill-loop --watch-help
tuskd --help
nix run .#tuskd -- ensure --repo "$PWD"
nix run .#tuskd -- status --repo "$PWD"
nix run .#tuskd -- board-status --repo "$PWD"
nix run .#tuskd-transition-tests -- --source-repo "$PWD"
nix run .#tuskd -- claim-issue --repo "$PWD" --issue-id tusk-123
nix run .#tuskd -- close-issue --repo "$PWD" --issue-id tusk-123 --reason "completed in visible commit"
nix run .#tuskd -- launch-lane --repo "$PWD" --issue-id tusk-123 --base-rev main
nix run .#tuskd -- handoff-lane --repo "$PWD" --revision <rev> --note "ready for landing"
nix run .#tuskd -- finish-lane --repo "$PWD" --issue-id tusk-123 --outcome completed --note "workspace cleaned after handoff"
nix run .#tuskd -- archive-lane --repo "$PWD" --issue-id tusk-123 --note "lane compacted into receipts"
nix run .#tuskd -- compact-lane --repo "$PWD" --issue-id tusk-123 --revision <rev> --reason "completed in visible commit <rev>"
nix build .#tusk-ui
nix run .#tusk-ui -- --help
```

## Repo Shape

- `flake.nix` exports `lib.{tusk,crane,mkRepoShell,mkDarwinSystem,mkNixosSystem,mkHomeConfiguration}`, `flakeModules.tusk`, the development shell, `tusk-tracker`, `tuskd`, `tusk-ui`, the installable OpenAI/Codex skill bundle, and `devenvModules.{codex,scratch,consumer,dogfood,tusk-skill,ops-skill,nix-skill}`.
- `flake.nix` also exports `tusk-claude`, `tusk-codex`, `tusk-skill-contract-check`, and `tusk-skill-loop` as the repo-owned launcher, validation surface, and fast-restart authoring loop for shared skills.
- `main` is the intended moving bookmark for flake consumers; once exported to Git and pushed, consumers can pin the repo with `?ref=main` and optionally a specific revision.
- `flake.nix` also exports a flake-owned `bd`/`beads` wrapper app so raw-shell `nix run` calls reuse repo-scoped tracker state instead of ambient host Beads configuration.
- `flake.nix` also exports `tusk-flake-ref`, which prints the canonical `path:`, `git+file:`, and remote `git+...?...ref=` forms for this repo and reports when no publish remote is configured.
- `flake.nix` also exports `tusk-radicle`, which attaches the existing Radicle RID to a checkout without repointing `main` away from `origin`.
- `devenv-codex-module.nix` owns the shared `codex.skills` and `claude.skills` option declarations, repo-local `CODEX_HOME` bootstrap, and `.codex/skills` plus `.claude/skills` projection logic for `devenv` consumers.
- Repo-local skill projection under `.codex/skills/` and `.claude/skills/` is one managed symlink per skill root; the runtime should not materialize fragile per-file link trees there.
- `devenv-scratch-module.nix` owns the shared per-repo scratch relocation policy for common build tools in consumer shells.
- `devenvModules.consumer` is the reusable downstream shell surface: repo-local `CODEX_HOME`, explicit skill opt-in, scratch relocation, and the conservative `tusk-clean` helper.
- `lib.mkRepoShell` is the preferred stable repo-shell builder over direct `devenv.lib.mkShell` reach-through; it composes `devenvModules.consumer` for downstream shells.
- `lib.mkDarwinSystem`, `lib.mkNixosSystem`, and `lib.mkHomeConfiguration` are the preferred stable machine/home builder entrypoints over direct upstream builder-lib reach-through.
- `devenvModules.dogfood` is the repo's own downstream composition of `codex` plus explicit `tusk`/`ops`/`nix` skill packs.
- `devenvModules.dogfood` is the repo's own downstream composition of `codex` plus explicit `tusk`/`ops`/`nix`/`skill-dev` skill packs.
- `scripts/codex-home-bootstrap.sh` copies auth/config/rules from `~/.codex` only as a first-use migration into the repo-local `.codex` home.
- `scripts/tusk-claude.sh` launches Claude Code against an explicit checkout so repo-local `.claude/skills` follows the active workspace while tracker state stays canonical.
- `scripts/tusk-codex.sh` launches Codex against an explicit checkout while preserving canonical tracker-root wiring.
- `scripts/tusk-skill-loop.sh` watches `.agents/skills/**`, reruns `tusk-skill-contract-check`, and relaunches `tusk-codex` only after validation passes.
- `scripts/tusk-clean.sh` contains the conservative cleanup/quarantine script for rebuildable repo-local artifacts.
- `scripts/tusk-radicle.sh` contains the hybrid GitHub/Radicle pilot helper for attaching the existing RID and inspecting local wiring.
- `scripts/tusk-paths.sh` centralizes checkout-root vs tracker-root resolution for flake-owned wrappers and local control-plane scripts.
- `lib.nix` contains the generic `tusk` normalization and validation logic.
- `flake-module.nix` contains the reusable Nix module surface for `tusk`.
- `design/` contains architecture and workflow notes that belong to `tusk` itself.
- `.agents/skills/tusk/` contains the repo-local source of truth for the `tusk` workflow skill.
- `.agents/skills/ops/` contains the repo-local source of truth for the shared `ops` skill.
- `.agents/skills/nix/` contains the repo-local source of truth for the shared `nix` skill.
- `.agents/skills/skill-dev/` contains the repo-local source of truth for the shared skill-authoring meta-skill.
- `scripts/tusk-tracker.sh` contains the flake-owned tracker boundary; the current implementation is a `bd` adapter so `tuskd` no longer shells out to raw `bd` commands directly.
- `scripts/tuskd.sh` contains the local control-plane service skeleton, Unix-socket protocol handler, and repo-scoped Dolt backend registry/coordination logic.
- `scripts/tuskd-transition-tests.sh` clones an isolated colocated temp repo, replays the current lane diff onto it, and runs automated lifecycle, concurrency, and rollback checks against that repo's own flake-owned `bd`/`tuskd` surface.
- `.beads/tuskd/lanes.json` holds first-class lane state for the current repo; `board-status` reads lane truth from there, derives stale-vs-live workspace observations, and carries ready, claimed, blocked, and deferred issue buckets alongside lanes.
- `crates/tusk-ui/` contains the Rust `ratatui` control-plane client crate and renders tracker, board, lane, and receipt projections from `tuskd`.

## Codex Contract

- Treat `.agents/skills/*` as the editable source of truth for shared skills.
- Treat `.claude/` as runtime state only. It is the repo-local Claude project surface, not the editable source of skills.
- Treat `.codex/` as runtime state only. It is the repo-local Codex home, not the editable source of skills.
- Bootstrap from `~/.codex` only for missing auth/config/rules; do not treat `~/.codex/skills` as runtime skill input.
- `devenvModules.consumer` should expose zero shared skills by default. Consumers opt in explicitly with `devenvModules.tusk-skill`, `devenvModules.ops-skill`, `devenvModules.nix-skill`, or their own local `codex.skills.*.source` / `claude.skills.*.source` entries.
- `devenvModules.dogfood` is allowed to project the shared skills explicitly because this repo authors them.

## Change Rules

- Keep `tusk` core generic. Consumer-specific runtime bindings and tracker wrappers belong in the consuming repo until they clearly generalize.
- Keep consumer-context skills in the consuming repo; do not centralize them in `tusk` unless they are intentionally becoming shared infrastructure.
- Import `devenvModules.codex` exactly once in a consumer flake, then compose `devenvModules.consumer` or explicit skill modules on top.
- Keep the shared scratch module focused on generic environment redirection; repo-specific cleanup choices still belong in the consuming repo.
- Keep `tusk-clean` conservative: dry-run by default, skip `.jj-workspaces/`, and quarantine instead of deleting.
- Prefer `codex-nix-check` and a shell smoke test after changing the flake or module surface.
- Prefer `tusk-skill-contract-check` when the change is specifically about repo-authored skills or their projection contract.
- Prefer `tusk-skill-loop` when iterating on repo-authored skills; it keeps the runtime repo-local and makes the restart contract honest.
- Use `tusk-radicle init-existing` to attach the canonical checkout to the existing RID; keep `origin` as the `main` upstream and treat `rad` as the additive distribution/review remote.
- If you initialize `.beads/` here for dogfooding, treat it as this repo's own tracker, not as an extension of `config`. The tracker state is local and ignored by Git in this repo.

## Verification

- `codex-nix-check`
- `nix run .#tusk-codex -- --launcher-help`
- `nix run .#tusk-claude -- --launcher-help`
- `tusk-skill-contract-check`
- `nix run .#tusk-skill-loop -- --watch-help`
- `nix build .#tusk-openai-skill`
- `nix run .#install-tusk-openai-skill`
- `nix run .#tusk-flake-ref -- --repo "$PWD" --json`
- `nix run .#tusk-radicle -- status`
- `nix run .#tusk-tracker -- status --repo "$PWD"`
- `nix run .#tusk-tracker -- issues board --repo "$PWD"`
- `nix run .#tusk-tracker -- backend show --repo "$PWD"`
- `nix run .#tuskd -- --help`
- `nix build .#tusk-ui`
- `nix run .#tusk-ui -- --help`
- `nix eval --raw path:.#packages.aarch64-darwin.rust-toolchain.name`
- `nix eval --raw path:.#packages.aarch64-darwin.tusk-ui.name`
- `nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.mkRepoShell`
- `nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.mkDarwinSystem`
- `nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.mkNixosSystem`
- `nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.mkHomeConfiguration`
- `nix flake metadata "git+file://$PWD?ref=main"`
- `nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.crane.buildDepsOnly`
- `nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'`
- `nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && glistix --help >/dev/null && erl -eval "erlang:halt()." -noshell >/dev/null && rebar3 version >/dev/null && cargo --version >/dev/null && rustc --version >/dev/null && rustfmt --version >/dev/null && rust-analyzer --version >/dev/null'`
- `nix run path:.#tuskd -- ensure --repo "$PWD"`
- `nix run path:.#tuskd -- status --repo "$PWD"`
- `nix run path:.#tuskd -- board-status --repo "$PWD"`
- `nix run path:.#tuskd-transition-tests -- --source-repo "$PWD"`
- `nix run path:.#bd -- status --json`
- `nix run path:.#beads -- status --json`
