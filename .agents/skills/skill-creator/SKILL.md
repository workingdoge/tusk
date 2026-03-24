---
name: skill-creator
description: Use when creating or updating skills in repos that use the tusk bootstrap model. Keep editable skill sources in repo-local `.agents/skills/<name>/`, project runtime copies through repo-local `.codex/skills/`, and avoid treating global `~/.codex/skills` paths as the source of truth.
---

# Tusk Skill Creator

Use this skill when the user wants to create or update a skill in a repo that
uses the `tusk` bootstrap model.

The main rule is:

- edit skill sources in `.agents/skills/<name>/`,
- project runtime copies into `.codex/skills/<name>/`,
- do not edit `.codex/skills/` or `~/.codex/skills/` as the source of truth.

## Choose the Right Home

1. Put a skill in `tusk/.agents/skills/<name>/` only when it is intentionally
   shared and generic across repos.
2. Put a skill in the consuming repo under its own `.agents/skills/<name>/`
   when it depends on that repo's domain context, policies, schemas, or
   workflows.
3. Do not centralize consumer-specific skills in `tusk`.

## Required Shape

Each skill must contain:

- `SKILL.md`
- `agents/openai.yaml`

Optional directories:

- `references/` for detailed material that should be loaded only when needed
- `scripts/` for deterministic helpers
- `assets/` for output resources

Do not create extra files such as `README.md`, `CHANGELOG.md`, or installation
notes unless the repo explicitly requires them.

## Authoring Flow

1. Decide whether the skill is shared or consumer-local.
2. Create or update the source under the correct `.agents/skills/<name>/`
   directory.
3. Keep `SKILL.md` concise and push variant-specific detail into `references/`
   only when needed.
4. Keep `agents/openai.yaml` aligned with the skill body.
5. Wire the skill into the repo-local runtime projection:
   - shared skills in `tusk`: add the skill to `sharedSkillSources` in
     `flake.nix`
   - consumer-local skills: add the skill to `repoSkillSources` in the
     consuming repo's `lib.tusk.bootstrap.mkRepoShell` call
6. Verify the projected runtime copy instead of hand-installing globals:
   - run `codex-nix-check`
   - run a shell smoke test that checks `.codex/skills/<name>/SKILL.md`
7. Treat global locations such as `~/.codex/skills` as compatibility-only
   projections. If you copy a skill there, do it explicitly and never edit it
   in place.

## Content Rules

- Prefer short procedural guidance over long explanation.
- Assume Codex already understands generic Markdown, YAML, and basic repo work.
- Keep references one hop from `SKILL.md`; do not build deep reference chains.
- Make trigger language in frontmatter concrete about when the skill should be
  used.
- Use scripts when the same deterministic logic would otherwise be rewritten.

## OpenAI Metadata

`agents/openai.yaml` should stay minimal unless the repo explicitly needs more.

Prefer:

- `display_name`
- `short_description`
- `default_prompt`

Only add icons or brand fields when the repo intentionally carries those assets.

## Runtime Boundary

`.codex/skills/` is a runtime projection built from store-backed skill packages.
It is not the editable skill tree.

If a repo uses `tusk` bootstrap correctly, the source/projection split should
be:

- source: `.agents/skills/<name>/`
- runtime projection: `.codex/skills/<name>/`
- optional compatibility projection: `~/.codex/skills/<name>/`
