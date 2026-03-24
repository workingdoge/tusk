# Agent Instructions

These instructions apply to `/Users/arj/dev/blackhole/tusk`.

## Workflow

- Use `nix develop --no-pure-eval path:.` or `direnv allow` before tracker or workflow work.
- The dev shell provides `bd`, `dolt`, `jj`, `deadnix`, `statix`, `nil`, `nixd`, `nix-tree`, `nix-output-monitor`, `nixfmt`, and `codex`.
- Run `devenv up` inside the dev shell to start managed services such as the repo's Dolt server when `.beads/` exists.
- Use this repo to develop `tusk` as a standalone flake and skill/tooling home; keep consumer-specific `bd-*` wrappers in the consuming repo unless they are intentionally promoted.

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
nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'
codex-nix-check
```

## Repo Shape

- `flake.nix` exports `lib.tusk`, `flakeModules.tusk`, the development shell, and the installable OpenAI/Codex skill bundle.
- `lib.nix` contains the generic `tusk` normalization and validation logic.
- `flake-module.nix` contains the reusable Nix module surface for `tusk`.
- `design/` contains architecture and workflow notes that belong to `tusk` itself.
- `design/tusk-bootstrap-contract.md` defines the managed-repo bootstrap contract and registry flow.
- `.agents/skills/tusk/` contains the repo-local source of truth for the `tusk` workflow skill.

## Change Rules

- Keep `tusk` core generic. Consumer-specific runtime bindings and tracker wrappers belong in the consuming repo until they clearly generalize.
- Prefer `codex-nix-check` and a shell smoke test after changing the flake or module surface.
- If you initialize `.beads/` here for dogfooding, treat it as this repo's own tracker, not as an extension of `config`. The tracker state is local and ignored by Git in this repo.

## Verification

- `codex-nix-check`
- `nix build .#tusk-openai-skill`
- `nix run .#install-tusk-openai-skill`
- `nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'`
- `nix run path:.#beads -- status --json`
