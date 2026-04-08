---
name: skill-dev
description: >
  Use this skill when Codex needs to create, split, update, or validate a
  repo-authored shared skill inside `tusk`. Trigger it for work under
  `.agents/skills/*`, `agents/openai.yaml`, skill-specific `references/` or
  `scripts/`, or when the task is to wire a new shared skill into the repo's
  dogfood runtime. Prefer the repo-owned authoring loop: edit the source under
  `.agents/skills/*`, validate with `tusk-skill-contract-check`, launch or
  relaunch sessions with `tusk-codex`, and use `tusk-skill-loop` for fast
  restart during iteration.
---

# skill-dev

## What this skill is
This is the repo-local authoring guide for shared `tusk` skills.

It is not a generic prompt-engineering essay and it is not a replacement for
the upstream `skill-creator` skill. It exists to keep shared-skill work inside
the real `tusk` dogfood loop.

## Authoring contract
Treat these paths as the source of truth:
- `.agents/skills/<name>/SKILL.md`
- `.agents/skills/<name>/agents/openai.yaml`
- optional `.agents/skills/<name>/references/`
- optional `.agents/skills/<name>/scripts/`

Do not edit `.codex/skills/*` directly. That is projected runtime state.

## Use this order
1. inspect the target skill under `.agents/skills/*`
2. decide whether the change belongs in `SKILL.md`, `references/`, `scripts/`,
   or `agents/openai.yaml`
3. make the smallest source edit
4. run `tusk-skill-contract-check --repo <checkout>`
5. use `tusk-codex --checkout <workspace>` for a fresh session, or
   `tusk-skill-loop --checkout <workspace>` when iterating repeatedly
6. only then widen the skill surface or runtime projection

Read `references/repo-authoring-loop.md` when you need the concrete repo loop
and the decision rules for `SKILL.md` versus `references/` versus `scripts/`.

## Placement rules
- Put trigger conditions, narrow workflow, and routing guidance in `SKILL.md`.
- Put detailed repo-specific procedures or checklists in `references/`.
- Put repeatable or fragile deterministic behavior in `scripts/`.
- Keep `agents/openai.yaml` aligned with the authored skill so UI metadata stays
  honest.

Default stance:
- `SKILL.md` should stay short.
- Add `references/` before turning `SKILL.md` into a wall of text.
- Add `scripts/` only when the same logic would otherwise be recopied or when
  correctness depends on a deterministic sequence.

## Repo-specific rules
- Shared skills here are repo-authored infrastructure, not consumer-local
  project context.
- If a skill is only useful in one consuming repo, keep it there until it is
  intentionally promoted.
- Wire new shared skills through `flake.nix`, `devenvModules.dogfood`, and
  `tusk-skill-contract-check` together so projection and validation stay in
  sync.
- The runtime contract is fast restart, not hot reload. Do not claim otherwise
  in docs or metadata.

## Deliverable shape
When finishing a shared-skill change, report:
1. which authored skill sources changed
2. whether dogfood projection or flake exports changed
3. validation results for `tusk-skill-contract-check`
4. whether the change expects `tusk-codex`, `tusk-skill-loop`, or both

## References
- Read `references/repo-authoring-loop.md` for the concrete command loop and
  the decision rules for `SKILL.md`, `references/`, `scripts/`, and metadata.
