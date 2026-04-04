# Agent Instructions

These instructions apply to `/Users/arj/dev/blackhole/tusk`.

## Workflow

- Use `nix develop --no-pure-eval path:.` or `direnv allow` before tracker or workflow work.
- The dev shell provides `bd`, `dolt`, `jj`, `deadnix`, `statix`, `nil`, `nixd`, `nix-tree`, `nix-output-monitor`, `nixfmt`, and `codex`.
- Run `devenv up` inside the dev shell to start managed services such as the repo's Dolt server when `.beads/` exists.
- This repo uses Jujutsu (`jj`) with a colocated Git repo for local change management.
- Use this repo to develop `tusk` as a standalone flake and skill/tooling home; keep consumer-specific `bd-*` wrappers in the consuming repo unless they are intentionally promoted.

## Quick Reference

```bash
nix develop --no-pure-eval path:.
devenv up
bd init -p tusk
bd ready --json
bd status --json
jj workspace list
jj st
nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'
codex-nix-check
```

## Repo Shape

- `flake.nix` exports `lib.tusk`, `flakeModules.tusk`, the development shell, and `devenvModules.{codex,scratch,consumer,tusk-skill,ops-skill,nix-skill}` for consuming shared modules and skills from other flakes.
- `devenv-codex-module.nix` contains the internal `devenv.files` projection logic used to materialize `tusk` inside a developer environment.
- `devenv-scratch-module.nix` contains the shared per-repo scratch relocation policy for common build tools in `devenv` shells.
- `scripts/tusk-clean.sh` contains the conservative cleanup/quarantine script for rebuildable repo-local artifacts.
- `lib.nix` contains the generic `tusk` normalization and validation logic.
- `flake-module.nix` contains the reusable Nix module surface for `tusk`.
- `design/` contains architecture and workflow notes that belong to `tusk` itself.
- `.agents/skills/tusk/` contains the repo-local source of truth for the `tusk` workflow skill.
- `.agents/skills/ops/` contains the repo-local source of truth for the shared `ops` skill.
- `.agents/skills/nix/` contains the repo-local source of truth for the shared `nix` skill.

## Tusk Skill Flow

- Treat `.agents/skills/tusk/`, `.agents/skills/ops/`, and `.agents/skills/nix/` as the canonical editable sources for the shared skills carried by this repo.
- Treat `.codex/skills/` as a `devenv.files` projection of packaged skills, not as the editable source.
- Prefer `devenvModules.consumer` when another flake wants the shared tusk shell surface. Prefer `devenvModules.codex` once plus any needed skill modules when the consumer needs a more custom shell assembly, and use `devenvModules.scratch` alongside that when it only wants the shared scratch policy.
- Ignore global skill roots such as `~/.codex/skills` as editable sources in this workflow.
- During dogfooding, it is acceptable to symlink `~/.codex/skills/tusk` to `.agents/skills/tusk/` so live Codex sessions exercise the repo-local skill copy. Keep the repo path as the source of truth and treat the global path as a projection only.
- Do not use this repo as the home for consumer-specific skills. If a skill depends on a repo's own domain context, schemas, workflows, or policies, keep that skill in the consuming repo under its own `.agents/skills/<name>/`.
- Only promote a skill into this repo when it is intentionally shared and generic across repos, the same way `tusk`, `ops`, and `nix` are.

## Change Rules

- Keep `tusk` core generic. Consumer-specific runtime bindings and tracker wrappers belong in the consuming repo until they clearly generalize.
- Keep consumer-context skills in the consuming repo; do not centralize them in `tusk` unless they are intentionally becoming shared infrastructure.
- Keep the shared scratch module focused on generic environment redirection; repo-specific cleanup choices still belong in the consuming repo.
- Keep `tusk-clean` conservative: dry-run by default, skip `.jj-workspaces/`, and quarantine instead of deleting.
- Keep `bd` rooted at the canonical repo root even when working from a `jj` workspace under `.jj-workspaces/`.
- Prefer one claimed `bd` issue per active `jj` workspace.
- Prefer `codex-nix-check` and a shell smoke test after changing the flake or module surface.
- If you initialize `.beads/` here for dogfooding, treat it as this repo's own tracker, not as an extension of `config`. The tracker state is local and ignored by Git in this repo.

## Verification

- `codex-nix-check`
- `nix develop --no-pure-eval path:. -c sh -lc 'cd "$DEVENV_ROOT" && bd version && jj --version && dolt version'`
- `nix run path:.#tusk-clean -- --help`
- `nix run path:.#beads -- status --json`
