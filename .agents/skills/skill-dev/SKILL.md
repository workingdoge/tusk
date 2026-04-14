---
name: skill-dev
description: >
  Use this skill when Codex needs to create, split, update, or validate a
  repo-authored shared skill inside `tusk`, especially when the work is to
  define the portable `SKILL.md` plus bundled-resources core, align or
  regenerate runtime-specific overlays such as `agents/openai.yaml`, fold
  useful upstream creator patterns into the repo-owned authoring loop, or wire
  a new shared skill into the repo's dogfood runtime or an adapter-specific
  runtime helper in the flake surface. Prefer editing `.agents/skills/*`,
  keeping the portable bundle canonical, validating with
  `tusk-skill-contract-check`, and using `tusk-codex`, `tusk-claude`, or
  `tusk-skill-loop` only after the authored source is coherent.
---

# skill-dev

## What this skill is
This is the repo-local authoring guide for shared `tusk` skills.

The canonical authored object is a portable skill bundle centered on
`SKILL.md`. OpenAI/Codex local behavior, hosted upload/versioning semantics,
staging or publish flows, and future runtime quirks are adapter concerns layered on top
of that bundle.

Shared skills here operate around stable surfaces that `tusk` owns. Tracked
upstream `premath` and `fish` own doctrine, and `bridge` owns the canonical
bridge+secret domain stack. Do not use `skill-dev` to smuggle canonical domain
meaning back into `tusk` just because a shared skill needs to mention it.

It is not a generic prompt-engineering essay. It is the first-class shared
skill authoring surface in this repo.

Absorb useful upstream `skill-creator` patterns here when they help, but do not
present `skill-creator` as a peer workflow. Do not treat `skill-installer` as
a generic authoring concept. Staging, publishing, mounting, or attaching a
skill are runtime-specific adapter operations.

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
- Borrow upstream bootstrap or validation ideas when they help, but normalize
  anything useful back into `.agents/skills/<name>/...` so `tusk` remains the
  source of truth.
- Do not teach separate peer workflows for `skill-creator` or
  `skill-installer` inside this repo-owned authoring surface.

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
- Keep `agents/openai.yaml` aligned when the OpenAI/Codex-facing metadata or
  adapter behavior would otherwise become stale, but do not treat it as the
  canonical semantic core.

Default stance:
- `SKILL.md` should stay short.
- Prefer portable core semantics over vendor metadata.
- Add `references/` before turning `SKILL.md` into a wall of text.
- Add `scripts/` only when the same logic would otherwise be recopied or when
  correctness depends on a deterministic sequence.

## Repo-specific rules
- Shared skills here are repo-authored infrastructure, not consumer-local
  project context.
- Keep shared skill semantics aligned with the current ownership split:
  tracked upstream `premath` and `fish` define doctrine, `bridge` owns the
  canonical bridge+secret domain stack, and `tusk` owns shared workflow and
  operator-facing skill surfaces.
- When a shared skill needs to describe a cross-repo seam, describe the seam
  as an edge contract with named endpoint owners instead of collapsing the
  repos into one pseudo-owner. If a third proof consumer matters, say so
  explicitly rather than hiding it inside the upstream wording.
- If a skill is only useful in one consuming repo, keep it there until it is
  intentionally promoted.
- If a lesson comes from a downstream repo's local wrapper or root-export
  contract, keep the detailed wrapper behavior there. Promote only the
  general routing rule into `tusk`, such as "prefer the local wrapper over
  inherited upstream env."
- Wire new shared skills through `flake.nix`, `devenvModules.dogfood`, and
  `tusk-skill-contract-check` together so projection and validation stay in
  sync.
- `tusk-skill-contract-check` validates the portable core for every authored
  skill and validates `agents/openai.yaml` only when that overlay is present.
- Keep staging/publish/runtime policy in adapters. The portable bundle
  describes the skill; OpenAI-hosted versioning, Codex local discovery, and
  plugin packaging do not belong in the semantic core.
- Name runtime-specific helpers for the runtime verb they perform. Prefer
  `stage-*`, `publish-*`, or `attach-*` over a fake universal `install-*`
  surface.
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
5. which runtime-specific staging or publish helpers changed, if any

## Conformance to agentskills.io

The portable core of every authored skill here conforms to the open Agent
Skills specification at <https://agentskills.io/specification>. That
specification is the cross-tool contract shared by Claude Code, Codex, Cursor,
GitHub Copilot, Gemini CLI, Goose, OpenHands, and others. Authoring against it
is what makes one `.agents/skills/<name>/` bundle work in any of those
runtimes, not just tusk's dogfood shell.

Hard rules the spec imposes (treat these as MUST when authoring a new skill or
editing frontmatter):

- `name` (required): 1-64 characters, unicode lowercase alphanumeric plus
  hyphens; must not start or end with a hyphen; no consecutive hyphens; must
  match the parent directory name.
- `description` (required): 1-1024 characters; should state both what the
  skill does and when to use it; should include keywords agents can match on.
- `SKILL.md` body: YAML frontmatter first, then Markdown. Keep the body under
  ~500 lines / ~5000 tokens. Move long material into `references/`.
- Canonical optional directories: `scripts/`, `references/`, `assets/`.
- File references inside `SKILL.md` should be relative and one level deep.

Optional frontmatter fields the spec defines (use when relevant, never invent
vendor-specific substitutes for these):

- `license` — short license name or reference to a bundled license file.
- `compatibility` — ≤500 chars; environment requirements (intended product,
  required tools, network access). Most skills should omit this.
- `metadata` — arbitrary string→string map for repo-local annotations.
- `allowed-tools` — experimental; space-separated pre-approved tools.

Tusk-local extensions layered on top of the spec (always opt-in, never
replace spec-core):

- `agents/openai.yaml` — OpenAI/Codex-facing overlay with UI metadata and
  prompt. See `references/portable-skill-bundles.md`.
- Projected runtime state under `.codex/skills/` and `.claude/skills/` —
  generated, never authored.
- `tusk-skill-contract-check` — repo-owned validator that enforces both the
  spec's hard rules on `SKILL.md` and the tusk extension rules on any present
  overlay.

Two validators you should know about:

- `tusk-skill-contract-check --repo <checkout>` — repo-local, always run
  before finishing a skill edit.
- `skills-ref validate ./skill-dir` — upstream reference validator from the
  spec authors; runs the spec's hard rules standalone. See
  <https://github.com/agentskills/agentskills/tree/main/skills-ref>.

When they disagree, trust `skills-ref` on questions about spec-core rules and
trust `tusk-skill-contract-check` on the tusk extensions. If a genuine drift
appears (e.g. the spec evolves), land a `skill-dev` lane that re-aligns the
repo validator instead of silently diverging.

## References
- Read `references/repo-authoring-loop.md` for the concrete command loop and
  the decision rules for portable core versus overlays.
- Read `references/portable-skill-bundles.md` for the portable bundle,
  overlay, and adapter boundary.
