# Agent Instructions

These instructions apply to `/Users/arj/dev/blackhole/tusk`.

## Workflow

- Use `nix develop --no-pure-eval path:.` or `direnv allow` before tracker or workflow work.
- The dev shell provides `bd`, `dolt`, `jj`, `deadnix`, `statix`, `nil`, `nixd`, `nix-tree`, `nix-output-monitor`, `nixfmt`, `codex`, `tuskd`, `glistix`, `gleam`, `erl`, `rebar3`, a `rust-overlay` toolchain for `cargo`/`rustc`/`rustfmt`, and `rust-analyzer`.
- Run `devenv up` inside the dev shell to start managed services such as the repo's Dolt server when `.beads/` exists.
- Use this repo to develop `tusk` as a standalone flake and skill/tooling home; keep consumer-specific `bd-*` wrappers in the consuming repo unless they are intentionally promoted.
- Use `glistix` for Nix-target Gleam work; the shell also keeps upstream `gleam` available for generic tooling and language-server compatibility checks.
- Use `lib.crane` from the flake for Rust package definitions so Rust builds share the same pinned `rust-overlay` toolchain as the shell, and run packaged Rust apps via `nix build` / `nix run` instead of mutating manifests ad hoc from outside Nix.

## Quick Reference

```bash
nix develop --no-pure-eval path:.
devenv up
bd init -p tusk
bd ready --json
bd status --json
jj st
nix build .#tusk-openai-skill
nix run .#install-tusk-openai-skill
nix eval --raw path:.#packages.aarch64-darwin.rust-toolchain.name
nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.crane.buildDepsOnly
nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'
nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && glistix --help >/dev/null && erl -eval "erlang:halt()." -noshell >/dev/null && rebar3 version >/dev/null && cargo --version >/dev/null && rustc --version >/dev/null && rustfmt --version >/dev/null && rust-analyzer --version >/dev/null'
codex-nix-check
tuskd --help
nix run .#tuskd -- ensure --repo "$PWD"
nix run .#tuskd -- board-status --repo "$PWD"
nix build .#tusk-ui
nix run .#tusk-ui -- --help
```

## Repo Shape

- `flake.nix` exports `lib.tusk`, `flakeModules.tusk`, the development shell, `tuskd`, `tusk-ui`, and the installable OpenAI/Codex skill bundle.
- `lib.nix` contains the generic `tusk` normalization and validation logic.
- `flake-module.nix` contains the reusable Nix module surface for `tusk`.
- `design/` contains architecture and workflow notes that belong to `tusk` itself.
- `.agents/skills/tusk/` contains the repo-local source of truth for the `tusk` workflow skill.
- `scripts/tuskd.sh` contains the local control-plane service skeleton and Unix-socket protocol handler.
- `crates/tusk-ui/` contains the Rust `ratatui` control-plane client crate.

## Change Rules

- Keep `tusk` core generic. Consumer-specific runtime bindings and tracker wrappers belong in the consuming repo until they clearly generalize.
- Prefer `codex-nix-check` and a shell smoke test after changing the flake or module surface.
- If you initialize `.beads/` here for dogfooding, treat it as this repo's own tracker, not as an extension of `config`. The tracker state is local and ignored by Git in this repo.

## Verification

- `codex-nix-check`
- `nix build .#tusk-openai-skill`
- `nix run .#install-tusk-openai-skill`
- `nix run .#tuskd -- --help`
- `nix build .#tusk-ui`
- `nix run .#tusk-ui -- --help`
- `nix eval --raw path:.#packages.aarch64-darwin.rust-toolchain.name`
- `nix eval --raw path:.#packages.aarch64-darwin.tusk-ui.name`
- `nix eval --raw --apply 'x: if builtins.isFunction x || builtins.hasAttr "__functor" x then "ok" else throw "not callable"' path:.#lib.crane.buildDepsOnly`
- `nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'`
- `nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && glistix --help >/dev/null && erl -eval "erlang:halt()." -noshell >/dev/null && rebar3 version >/dev/null && cargo --version >/dev/null && rustc --version >/dev/null && rustfmt --version >/dev/null && rust-analyzer --version >/dev/null'`
- `nix run path:.#tuskd -- ensure --repo "$PWD"`
- `nix run path:.#tuskd -- board-status --repo "$PWD"`
- `nix run path:.#beads -- status --json`
