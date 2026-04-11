---
name: skill-dev
description: >
  Use this skill when Codex needs to create, split, update, or validate a
  repo-authored shared skill inside `tusk`, especially when the work is to
  define the portable `SKILL.md` plus bundled-resources core, align or
  regenerate runtime-specific overlays such as `agents/openai.yaml`, fold
  upstream `skill-creator` or `skill-installer` behavior into the repo-owned
  authoring loop, or wire a new shared skill into the repo's dogfood runtime.
  Prefer editing `.agents/skills/*`, keeping the portable bundle canonical,
  validating with `tusk-skill-contract-check`, and using `tusk-codex`,
  `tusk-claude`, or `tusk-skill-loop` only after the authored source is
  coherent.
---

# skill-dev

## What this skill is
This is the repo-local authoring guide for shared `tusk` skills.

The canonical authored object is a portable skill bundle centered on
`SKILL.md`. OpenAI/Codex local behavior, hosted upload/versioning semantics,
installer flows, and future runtime quirks are adapter concerns layered on top
of that bundle.

It is not a generic prompt-engineering essay. It also does not replace the
upstream `skill-creator` or `skill-installer` skills; it tells `tusk` how to
use those native helpers without letting them define the repo's canonical
contract.

## Authoring contract
Treat these paths as the portable core:
- `.agents/skills/<name>/SKILL.md`
- optional `.agents/skills/<name>/references/`
- optional `.agents/skills/<name>/scripts/`
- optional `.agents/skills/<name>/assets/`

Treat these as runtime-specific overlays:
- optional `.agents/skills/<name>/agents/openai.yaml`
- optional future vendor or distribution metadata beside the bundle

Do not edit `.codex/skills/*` or `.claude/skills/*` directly. That is
projected runtime state.

## Upstream helpers
- Use `skill-creator` for upstream bundle/bootstrap patterns, portable
  frontmatter expectations, and helper ideas such as YAML generation or quick
  validation.
- Use `skill-installer` when the task is to ingest or stage external skills
  into a runtime, not when authoring the canonical shared skill source in this
  repo.
- Normalize anything borrowed from upstream back into
  `.agents/skills/<name>/...` so `tusk` remains the source of truth.

## Use this order
1. inspect the target skill under `.agents/skills/*`
2. decide whether the change belongs in the portable core, a runtime overlay,
   or repo wiring/validation
3. make the smallest source edit
4. run `tusk-skill-contract-check --repo <checkout>`
5. use `tusk-codex --checkout <workspace>` or
   `tusk-claude --checkout <workspace>` for a fresh session
6. use `tusk-skill-loop --checkout <workspace>` when the task specifically
   needs the Codex fast-restart loop
7. only then widen the adapter surface or runtime projection

Read `references/repo-authoring-loop.md` when you need the concrete repo loop
and the decision rules for portable core versus overlays.
Read `references/portable-skill-bundles.md` when you need the portable bundle,
overlay, and adapter split spelled out.

## Placement rules
- Put trigger conditions, narrow workflow, and routing guidance in `SKILL.md`.
- Put detailed repo-specific procedures, adapter notes, or eval checklists in
  `references/`.
- Put repeatable or fragile deterministic behavior in `scripts/`.
- Put bundled output resources in `assets/` when the skill needs files rather
  than more prose.
- Keep `agents/openai.yaml` aligned when the OpenAI/Codex UI surface is part of
  the task, but do not treat it as the canonical semantic core.

Default stance:
- `SKILL.md` should stay short.
- Prefer portable core semantics over vendor metadata.
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
- `tusk-skill-contract-check` validates the portable core for every authored
  skill and validates `agents/openai.yaml` only when that overlay is present.
- Keep publish/install/runtime policy in adapters. The portable bundle
  describes the skill; OpenAI-hosted versioning, Codex local discovery, and
  plugin packaging do not belong in the semantic core.
- The Codex runtime contract is fast restart, not hot reload. Do not claim
  otherwise in docs or metadata.
- The Claude runtime contract is repo-local project-skill projection plus a
  fresh launch from the checkout; do not claim a watch/reexec loop unless it
  actually exists.

## Deliverable shape
When finishing a shared-skill change, report:
1. which authored skill sources changed
2. whether the portable core, runtime overlays, or dogfood/flake wiring changed
3. validation results for `tusk-skill-contract-check`
4. whether the change expects `tusk-codex`, `tusk-claude`,
   `tusk-skill-loop`, or some combination

## References
- Read `references/repo-authoring-loop.md` for the concrete command loop and
  the decision rules for portable core versus overlays.
- Read `references/portable-skill-bundles.md` for the portable bundle,
  overlay, and adapter boundary.
