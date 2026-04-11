# Repo Authoring Loop

Use this when the task is concretely about authoring or evolving one shared
skill in `tusk`.

## Canonical object
- The authored source of truth is a portable bundle under
  `.agents/skills/<name>/`.
- Portable core: `SKILL.md` plus optional `references/`, `scripts/`, and
  `assets/`.
- Runtime overlays: optional `agents/openai.yaml` and future vendor/distribution
  metadata.
- If upstream helper behavior is worth keeping, absorb the relevant bootstrap
  or validation pattern into repo-owned docs or scripts instead of teaching a
  separate peer workflow.

## Source selection
- Edit `SKILL.md` when the change is about trigger conditions, the narrow
  workflow, or the top-level route through the portable bundle.
- Add or update `references/` when the detailed procedure would make `SKILL.md`
  too large, when only some tasks need the extra context, or when adapter notes
  should stay out of `SKILL.md`.
- Add `scripts/` when the same deterministic sequence would otherwise be copied
  into prompts repeatedly, or when correctness depends on code instead of prose.
- Add `assets/` when the skill needs bundled files rather than more context.
- Update `agents/openai.yaml` when the OpenAI/Codex-facing skill name, summary,
  or default invocation prompt would become stale.

## Repo loop
1. edit the authored source under `.agents/skills/<name>/...`
2. run `tusk-skill-contract-check --repo <checkout>`
3. if the task needs a fresh session, use:
   `tusk-codex --checkout <workspace>` or
   `tusk-claude --checkout <workspace>`
4. if the task is iterative and specifically needs the Codex restart loop, use:
   `tusk-skill-loop --checkout <workspace>`

The loop validates before restart. If validation fails, fix the authored source
and save again. Do not pretend the running Codex or Claude process can rescan
skills in-place.

## Runtime adapters
- Keep one canonical shared-skill authoring loop here. If upstream
  `skill-creator` behavior is worth keeping, absorb it into repo-owned
  `SKILL.md`, `references/`, or `scripts/` instead of teaching a separate peer
  flow.
- Treat staging, publishing, mounting, and attachment as runtime-specific
  adapter operations, not a generic installer concept.
- Use explicit verbs for runtime helpers. `stage-tusk-openai-skill` is honest
  about what it does; a universal `skill-installer` name is not.

## Projection and wiring
When adding a new shared skill, update all of these together:
- `.agents/skills/<name>/...`
- `flake.nix` skill source and dogfood projection
- `scripts/tusk-skill-contract-check.sh`

That keeps authored source, runtime projection, and validation in one line.

If the task also changes an OpenAI-specific adapter surface, keep
`agents/openai.yaml` and any related packaging/export path honest at the same
time. Do not smuggle adapter-only semantics back into the portable core.
