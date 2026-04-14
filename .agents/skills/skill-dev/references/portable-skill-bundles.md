# Portable Skill Bundles

Use this when a shared-skill change needs a clean boundary between the authored
bundle and runtime-specific behavior.

## Canonical object

The canonical authored object in `tusk` is a portable skill bundle under
`.agents/skills/<name>/`.

The portable core is the open Agent Skills specification at
<https://agentskills.io/specification>. Everything else in this repo layers on
top of that spec-core and is either an opt-in overlay or generated projected
runtime state.

Spec-core (agentskills.io — portable across Claude Code, Codex, Cursor,
GitHub Copilot, Gemini CLI, Goose, OpenHands, etc.):
- `SKILL.md` with required `name` + `description` frontmatter (see the
  Conformance section of `SKILL.md` for hard rules).
- optional `references/`
- optional `scripts/`
- optional `assets/`
- optional spec frontmatter fields: `license`, `compatibility`, `metadata`,
  `allowed-tools` (experimental).

Tusk-local extensions (never replace spec-core; runtime-surface-specific):
- optional `agents/openai.yaml` — OpenAI/Codex-facing UI metadata and prompt.
- future vendor or distribution metadata beside the bundle, when it would
  only make sense for one runtime.

Projected runtime state (generated; do not author directly):
- `.codex/skills/<name>`
- `.claude/skills/<name>`

Validators:
- `tusk-skill-contract-check` — repo-owned; validates `SKILL.md` against both
  spec-core and tusk-local extensions; validates `agents/openai.yaml` only
  when present.
- `skills-ref validate ./skill-dir` — upstream reference validator from the
  spec authors (<https://github.com/agentskills/agentskills/tree/main/skills-ref>);
  good for checking spec-core conformance independently.

Keep authored source under `.agents/skills/*`. Do not edit projected runtime
state directly.

## What belongs in the portable core

Put a statement in the portable core when it should remain true across runtime
surfaces:
- what the skill does
- when it should trigger
- the narrow workflow
- bundled references, scripts, and assets that support the workflow

`SKILL.md` is the routing and instruction center. Use the frontmatter for the
portable routing boundary. Use the body for the narrow workflow and directions
to bundled resources.

When the open Agent Skills frontmatter fields are useful, keep them in the
portable core rather than inventing vendor-specific substitutes.

If the skill needs to refer to upstream meaning, keep the ownership honest:
tracked upstream `premath` / `fish` define doctrine, `bridge` owns the
canonical bridge+secret domain stack, and `tusk` owns shared operator-facing
skill bundles around those surfaces.

## What belongs in overlays and adapters

Put a statement in an overlay or adapter when it only makes sense for one
runtime surface:
- `agents/openai.yaml` UI metadata and default prompt
- hosted upload, versioning, and attachment semantics
- local installer/discovery conventions
- plugin packaging
- runtime policy or permission behavior

Decision rule:
- if the statement should still be true after switching runtimes, keep it in
  the portable bundle
- if it only exists because one runtime needs it, keep it in an overlay or
  adapter
- if it only exists because one downstream repo exports a local wrapper or
  tracker-root helper, keep the detailed behavior in that downstream repo and
  only lift the reusable routing rule into shared skill docs

## Upstream helper integration

Use `skill-creator` when you need upstream bootstrap patterns, validation
ideas, or helper-script examples. Treat its output as raw material that must be
normalized back into `.agents/skills/<name>/...`.

Use `skill-installer` when the task is external skill ingress or runtime
staging. It is not the source of truth for repo-authored shared skills.

If an upstream helper becomes part of the stable repo loop, promote the needed
procedure into repo-owned `references/` or `scripts/` rather than depending on
prompt memory.

## Validation posture

Default stance:
- lenient on ingest of the portable bundle
- strict on publish or adapter packaging

In this repo that means:
- `tusk-skill-contract-check` validates `SKILL.md` for every authored skill
- `tusk-skill-contract-check` validates `agents/openai.yaml` only when present
- OpenAI-specific packaging helpers may still require `agents/openai.yaml`

## Future tooling rule

If the repo grows a richer skill registry or publication surface, do not key it
by skill name alone. Names are routing metadata, not stable global identity.
Use a source-aware identifier such as source plus locator plus content digest.
