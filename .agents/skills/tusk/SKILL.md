---
name: tusk
description: Claim and execute `bd` issues in dedicated `jj` workspaces or issue-scoped worktrees, including coordinating multiple parallel `codex exec` lanes, writing comprehensive worker briefs, and reporting compact lane status back to the user. Use when the user wants to point Codex at a specific issue id, fan out parallel issue work, run isolated worker lanes in fresh workspaces, or clean up finished issue workspaces while keeping the tracker rooted at the canonical repo. Tusk is the foundation and opening move for this workflow.
---

# Tusk

Use this skill to turn one tracked issue into one isolated execution lane. When multiple lanes are active, treat the outer Codex as the coordinator, keep the tracker in the canonical repo root, keep one claimed issue per active workspace, and treat each `codex exec` run as a bounded worker.

## Workflow

1. Resolve the canonical repo root.
   - Prefer `git rev-parse --show-toplevel`.
   - Run `bd` from the repo root even when code work happens elsewhere.
   - Use `jj --repository "$repo_root" ...` for repo-global workspace commands.
   - Check the repo instructions for workflow wrappers before assembling raw `bd` and `jj` commands. If the repo ships helpers such as `bd-lane`, `bd-new-issue`, or similar wrappers, prefer those first.
2. Preflight the tracker before relying on `bd` mutations.
   - Run one read command such as `bd ready --json` or `bd show <id> --json` from the repo root.
   - Check `bd dolt status` when the tracker uses Dolt server mode.
   - If the repo uses `tuskd`, treat server-mode Dolt as part of the contract. Fresh trackers should be initialized with `bd init --server`; embedded mode is a migration or unblocker task, not normal lane work.
   - If the repo documents a wrapper, dev shell, or service supervisor, use that before ad hoc recovery. Some repos require entering a managed shell and keeping a long-lived service session alive before `bd` is healthy.
   - If the repo uses `devenv up` or a similar interactive supervisor, keep it running in a PTY-backed coordinator session for the duration of tracker-dependent work instead of pushing that ownership into the worker lane.
   - If tracker health is bad, fix that first or downgrade the worker brief so `codex exec` does code work only and leaves issue mutation to the outer shell.
3. Pick and claim exactly one issue for the lane.
   - Use `bd ready --json`, `bd show <id>`, and `bd update <id> --claim --json`.
   - Prefer ready issues: clear goal, non-goals, verification, and landing boundary.
   - If the issue is too broad or underspecified, shape or split it before launching a worker.
   - When shaping or splitting work, prefer repo-local issue wrappers such as `bd-new-issue` when they exist.
   - Do not widen the lane. File discovered work as new linked issues instead.
4. Create or reuse an issue-scoped workspace.
   - If the repo ships a lane wrapper such as `bd-lane`, prefer it over manually reproducing claim, workspace creation, and prompt boilerplate. Fall back to raw `bd` and `jj` commands only when the wrapper does not exist or is insufficient for the task.
   - Prefer `$repo_root/.jj-workspaces/<issue-id>-<slug>`.
   - Prefer semantic workspace names that keep the issue id visible, such as `config-kwj-scaffold`.
   - If one issue needs parallel sublanes, add a stable suffix before the semantic slug, such as `config-kwj.1-sections`.
   - Reuse an existing workspace only if it is already dedicated to the same issue.
   - Use a sibling checkout such as `../repo-config-kwj` only when the repo already uses that convention or the user asked for it.
   - Prefer an explicit base revision such as `main` instead of inheriting from the current workspace implicitly.
   - Seed the new workspace's working-copy change with a lane-local message such as `-m "$issue_id: wip"`.
   - Remember that `jj workspace rename` changes the workspace label, not the directory path. If you want both to match, choose the semantic destination path when you create the workspace.
   - Do not initialize a separate tracker inside the workspace.
5. Write the execution brief.
   - Put the stable scope in the `codex exec` prompt: goal, non-goals, primary files, verification commands, and finish criteria.
   - Include the base revision and intended landing target so rebases, review handoffs, and cleanup decisions stay explicit.
   - Make the landing boundary explicit: stop at a visible `jj` commit, publish a bookmark, create a PR, or merge the change.
   - Use the worker brief contract in `references/coordinator-mode.md` when the user wants strict coordination or parallel lanes.
   - Keep the brief tied to the issue id so a later handoff can reuse it.
6. Launch `codex exec` in the workspace.
   - Always make the repo root writable too if tracker or shared files live outside the workspace. Use `--add-dir "$repo_root"`.
   - Prefer `--full-auto` for the standard autonomous run.
   - If a terminal wrapper needs it, allocate a PTY.
   - Keep shared tracker or service supervisors in the coordinator shell when the repo treats them as singleton infrastructure. The worker should consume a healthy environment, not become responsible for the shared backend lifecycle.
   - If tracker preflight is still unhealthy, explicitly tell the worker not to burn time retrying `bd` mutations. It should finish the code work and report the exact tracker failure.
7. Finish the lane.
   - Run the repo's verification gates.
   - Prefer one visible commit per issue unless the task genuinely needs a stack.
   - Cut the final commit intentionally; do not rely on an unnamed working-copy change as the handoff artifact.
   - Default handoff: a verified visible `jj` commit in the workspace. Do not assume publish or merge is in scope unless the brief says so.
   - Re-run tracker preflight before `bd close` or other final issue mutations.
   - If landing is owned elsewhere, leave the issue open and record the handoff state. Close it only when the repo's actual completion boundary has been met.
   - Forget and remove the workspace only after confirming the work is landed or intentionally kept for later.

## JJ History Flow

- Treat each workspace as one execution lane and one primary open change.
- Default flow: one issue, one workspace, one final visible commit.
- Use `jj describe` while shaping the lane. Use `jj commit` when you want to cut the final reviewable commit and open a fresh working-copy change.
- Create bookmarks only when publishing or when the repo's landing flow explicitly needs them.
- Keep the default workspace as the coordinator/control plane when possible, not the main place where issue work accumulates.

## Publish and Landing

- Default endpoint: one verified visible `jj` commit in the issue workspace. No bookmark push, PR creation, or merge unless the brief explicitly includes it.
- If publish is in scope, create the bookmark late, push it with `jj git push`, and report the exact bookmark or remote handle that now carries the change.
- If Git-host landing is in scope, make ownership explicit in the brief: `worker`, `coordinator`, `user`, or `CI`. Default owner: `coordinator` or `user`.
- Issue state should follow landing state, not just code state. A visible commit or pushed bookmark is usually handoff, not closure.
- Do not invent a Git branch or merge strategy inside `tusk`. Follow the repo's normal landing flow if one exists.
- After review or publication starts, only rewrite history, move bookmarks, or force-push when the brief or repo rules explicitly allow it.
- After the change lands elsewhere, sync the workspace with imported Git state before cleanup. Use `jj git fetch`, then `jj workspace update-stale` if needed, before forgetting the workspace.

## Tracker Contract

- Keep the tracker rooted at the canonical repo root. Workers may edit code in a workspace, but `bd` remains a repo-root concern.
- Default readiness contract: probe with `bd ready --json`, check `bd dolt status` when Dolt server mode exists, and confirm the issue can be read before asking a worker to mutate tracker state.
- Make shared backend ownership explicit. Default owner: the coordinator shell, especially when `devenv up` or another singleton supervisor keeps Dolt alive.
- Default tracker scope inside `tusk`: claim, read, update, and close existing issues only when the backend is healthy.
- First-time tracker bootstrap, `bd init`, Dolt setup, schema/admin repair, or tracker migration are not default lane work. Make those explicit tasks instead of surprising a worker with shared-state repair.
- If the repo uses `tuskd`, embedded Dolt mode is incompatible with the normal tracker contract. Fresh bootstrap should use `bd init --server`, and legacy embedded trackers should be handled as explicit migration work.
- If tracker readiness depends on shell, flake, `devenv`, or tool-provisioning changes, load the repo's Nix environment skill, such as `nix-interrogation`, if available.

## Environment Contract

- Capture the runtime contract in the worker brief when the repo depends on a managed shell or supervisor.
- Include the shell entry path the worker should assume, such as `nix develop`, `direnv`, `devenv shell`, or a repo wrapper.
- Include any coordinator-owned long-lived process the worker depends on, such as `devenv up`, and state that the worker must not try to own that singleton lifecycle.
- Include the tools or runtimes the worker may assume are already present, such as `bd`, `jj`, language toolchains, or repo-specific wrappers.
- State whether changing the runtime is in scope. Default: no.
- Treat shell authoring, flake edits, `devenv` module changes, dependency packaging, and tool installation as out of scope unless the issue is explicitly about the environment itself.
- If the issue is about the environment itself, say so explicitly in the brief and switch the lane goal from "use the runtime" to "change the runtime safely".
- If runtime authoring is in scope and the repo has a Nix environment skill such as `nix-interrogation`, load it instead of expanding `tusk` into a flake or shell authoring guide.

## Issue Shaping and Ordering

- Prefer issues that map cleanly to one workspace, one lane, and usually one final visible commit.
- A ready issue should name the goal, non-goals, verification, and landing boundary.
- Split issues on dependency edges, landing-owner changes, verification boundaries, or risk boundaries, not on arbitrary file boundaries alone.
- Order work as: runtime or tracker unblockers first, then dependency roots, then independent leaves in parallel, then integration or cleanup.
- Do not launch a worker on an omnibus issue that mixes unrelated outcomes. Shape it into linked follow-ups first.
- When new work is discovered, create linked follow-up issues instead of widening the current lane.

## Coordinator Mode

Use coordinator mode whenever more than one lane is active or the user expects high-signal progress updates instead of raw worker logs.

- Keep one lane ledger entry per issue.
- Report deltas to the user, not full transcripts, unless the user asks for worker output.
- Use a fixed per-lane shape:
  - `<issue_id>` `<status>` in `<workspace>`
  - `Goal: <one sentence>`
  - `Latest: <newest material event>`
  - `Verification: <not run | passed | failed>`
  - `Next: <next coordinator or worker action>`
  - `Blocker: <none | exact blocker>`
- Use stable status values: `queued`, `preflight`, `running`, `blocked`, `verifying`, `handoff`, `done`.
- If a worker hits a bounded stop condition, surface it as a lane blocker and decide in the coordinator shell whether to repair the environment, re-brief the worker, or end the lane.

## Core Commands

```bash
repo_root=$(git rev-parse --show-toplevel)
issue_id=config-kwj
slug=scaffold
base_rev=main

cd "$repo_root"
bd ready --json >/dev/null
bd dolt status || true
bd show "$issue_id"

if command -v bd-lane >/dev/null 2>&1; then
  bd-lane "$issue_id" --slug "$slug" --base "$base_rev" --no-exec
else
  workspace_name="${issue_id}-${slug}"
  workspace_dir="$repo_root/.jj-workspaces/$workspace_name"
  bd update "$issue_id" --claim --json
  jj --repository "$repo_root" workspace add "$workspace_dir" --name "$workspace_name" -r "$base_rev" -m "$issue_id: wip"
fi
```

## Guardrails

- Keep `bd` scoped to the canonical repo root, even when the active shell is inside a workspace.
- Preflight `bd` before asking `codex exec` to depend on tracker writes, and preflight again before final close/update steps.
- If the repo requires `devenv up` or another long-lived supervisor, start it once in the coordinator shell and keep it outside worker ownership.
- Treat tracker ownership as explicit shared infrastructure. Do not surprise workers with first-time `bd` or Dolt setup.
- Prefer repo-local workflow wrappers such as `bd-lane` and `bd-new-issue` when they exist, and fall back to raw `bd` and `jj` only when necessary.
- Prefer one claimed issue per active workspace.
- Prefer ready issues with clear verification and landing semantics. If an issue is fuzzy, shape or split it before launch.
- Prefer `jj workspace add -r <base>` over inheriting the new workspace's parent from ambient state.
- Prefer one primary visible commit per issue lane; stack only when the task really benefits from it.
- Default lane completion is a visible `jj` commit, not an implicit merge or Git-side landing.
- Create `jj` bookmarks late, usually right before publish or export.
- Do not close a `bd` issue just because a worker produced a clean commit. Closure follows the declared landing boundary.
- Make publish and merge ownership explicit in the worker brief. Do not assume the worker should open or merge a PR unless asked.
- Include the repo's environment contract in the worker brief whenever runtime assumptions are non-trivial.
- Include the lane's base revision and landing target in the worker brief whenever publish, review, or rebase work is plausible.
- If runtime or tracker readiness requires flake, shell, or `devenv` authoring, delegate that work to the repo's Nix environment skill when available.
- Do not let workers rewrite shells, flakes, or dependency provisioning unless that is explicit task scope.
- Treat worker prompts as contracts. Include scope, non-goals, verification, stop conditions, and output expectations every time.
- Do not run `bd init` or create `.beads/` inside `.jj-workspaces/` or sibling workspaces.
- Do not run `jj git init --colocate` unless the user explicitly asked to adopt `jj` in a git-only repo.
- If the workspace path sits outside the repo root, treat `--add-dir "$repo_root"` as mandatory for tracker writes.
- If `bd` is unhealthy, do not hide that behind repeated retries. Either repair the tracker first or keep issue mutation outside the worker run.
- Do not stream raw `codex exec` logs to the user by default. Translate them into lane status, blockers, and next actions.
- Use the repo's normal landing or export flow before forgetting a workspace.
- After a publish or merge event outside the workspace, sync imported Git state before cleanup.

## References

- Load [issue-exec-flow.md](references/issue-exec-flow.md) for prompt templates, alternate workspace layouts, and cleanup checklists.
- Load [coordinator-mode.md](references/coordinator-mode.md) for lane-ledger formatting and the full worker brief contract.
- Load [landing-and-recovery.md](references/landing-and-recovery.md) when the lane may publish, hand off for review, recover from a moved base, or clean up after landing elsewhere.
- Load [tracker-contract.md](references/tracker-contract.md) when `bd` or Dolt readiness, ownership, or degraded-mode behavior matters.
- Load [issue-shaping.md](references/issue-shaping.md) when deciding whether an issue is ready, how to split it, or how to order multiple issues.
