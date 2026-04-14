# Issue Execution Flow

## Repo Wrappers First

Before assembling raw `bd` and `jj` commands, look for repo-local workflow wrappers. If the repo ships helpers such as `bd-lane` and `bd-new-issue`, prefer them because they usually encode the repo's workspace layout, prompt shape, tracker contract, and naming conventions already.

If you are inside a downstream repo from another repo's shell, prefer that
downstream repo's local wrapper or root-export helper before trusting
inherited upstream `TUSK_*`, `BEADS_*`, or `DEVENV_*` env. The fallback
expansions below are only for cases where no stricter local contract exists.

Example coordinator setup when the repo ships `bd-lane`:

```bash
# In a downstream repo with its own wrapper or root-export helper, prefer that
# local contract before falling back to inherited upstream env.
checkout_root="${TUSK_CHECKOUT_ROOT:-${DEVENV_ROOT:-$PWD}}"
repo_root="${TUSK_TRACKER_ROOT:-${BEADS_WORKSPACE_ROOT:-$(git -C "$checkout_root" rev-parse --show-toplevel)}}"
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

When you need to shape a follow-up issue and the repo ships `bd-new-issue`, prefer that wrapper too:

```bash
bd-new-issue \
  --title "Follow up: tighten tracker handoff behavior" \
  --goal "Track the newly discovered workflow gap without widening the current lane." \
  --acceptance "A separate linked issue exists for the new work." \
  --verify "bd show <new-id> --json"
```

## Preferred Layout

When no wrapper exists, or when you need to bypass the wrapper deliberately, prefer a repo-local workspace path when the repo already uses `jj` workspaces:

```bash
# In a downstream repo with its own wrapper or root-export helper, prefer that
# local contract before falling back to inherited upstream env.
checkout_root="${TUSK_CHECKOUT_ROOT:-${DEVENV_ROOT:-$PWD}}"
repo_root="${TUSK_TRACKER_ROOT:-${BEADS_WORKSPACE_ROOT:-$(git -C "$checkout_root" rev-parse --show-toplevel)}}"
issue_id=config-kwj
slug=scaffold
base_rev=main
workspace_name="${issue_id}-${slug}"
workspace_dir="$repo_root/.jj-workspaces/$workspace_name"

cd "$repo_root"
bd ready --json >/dev/null
bd dolt status || true
bd show "$issue_id"
bd update "$issue_id" --claim --json
jj --repository "$repo_root" workspace add "$workspace_dir" --name "$workspace_name" -r "$base_rev" -m "$issue_id: wip"
```

This keeps the workspace discoverable and makes cleanup predictable.

Prefer an explicit base revision instead of inheriting from the current workspace implicitly. In most repos, `main` is the right default unless the user asked to branch from another change.

Prefer semantic workspace names that keep the issue id visible in both the path and the workspace label. Examples:

- `config-kwj-scaffold`
- `config-kwj.1-sections` for a second lane on the same issue

If you rename the current workspace later, remember that `jj workspace rename` updates the workspace name but does not rename the directory path. If you want path and name to match, choose the semantic destination path at creation time.

## Tracker Preflight

Before the worker depends on `bd`, confirm that the shared tracker is healthy from the canonical tracker root.

```bash
cd "$repo_root"
bd ready --json >/dev/null
bd dolt status || true
```

If the repo documents a managed shell or service supervisor, honor that before relying on the probe above. Keep shared service ownership in the coordinator shell rather than in the worker lane. Example for a repo that uses `devenv`-managed services:

```bash
# Keep this alive in a separate PTY-backed coordinator session.
nix develop --no-pure-eval path:. -c devenv up

# Then run tracker preflight from the canonical tracker root.
cd "$repo_root"
nix develop --no-pure-eval path:. -c bd ready --json >/dev/null
nix develop --no-pure-eval path:. -c bd dolt status || true
```

If the repo documents a dedicated preflight wrapper, use that instead of improvising. If the repo ships a lane wrapper such as `bd-lane`, let that wrapper own the claim and workspace-setup boilerplate unless you need a custom path it cannot express. If the tracker is unhealthy:

- repair it before launching `codex exec`, or
- launch `codex exec` with a degraded brief that forbids issue mutation and tells the worker to report the exact `bd` failure.

Do not spend the worker budget on repeated `bd close` retries when the backend itself is unhealthy.

Load `tracker-contract.md` when tracker ownership, degraded mode, or first-time setup responsibilities are ambiguous.

## Alternate Layout

Use a sibling checkout only when the repo already uses that pattern or the user asked for it:

```bash
# In a downstream repo with its own wrapper or root-export helper, prefer that
# local contract before falling back to inherited upstream env.
checkout_root="${TUSK_CHECKOUT_ROOT:-${DEVENV_ROOT:-$PWD}}"
repo_root="${TUSK_TRACKER_ROOT:-${BEADS_WORKSPACE_ROOT:-$(git -C "$checkout_root" rev-parse --show-toplevel)}}"
repo_name=$(basename "$repo_root")
issue_id=config-kwj
slug=sections
base_rev=main
workspace_dir="$(cd "$repo_root/.." && pwd)/${repo_name}-${issue_id}"
workspace_name="${issue_id}-${slug}"

cd "$repo_root"
bd show "$issue_id"
bd update "$issue_id" --claim --json
jj --repository "$repo_root" workspace add "$workspace_dir" --name "$workspace_name" -r "$base_rev" -m "$issue_id: wip"
```

When the workspace lives outside the tracker root, `codex exec` should still receive `--add-dir "$repo_root"` so it can update the shared tracker and other repo-level files.

## Codex Exec Template

Wrapper-first coordinator flow:

```bash
cd "$repo_root"
bd-lane "$issue_id" --slug "$slug" --base "$base_rev" --no-exec

# Review or refine the generated prompt if the repo wrapper wrote one.
# Then launch codex exec from the prepared workspace.
```

Use a short inline prompt for simple work:

```bash
codex exec \
  -C "$workspace_dir" \
  --add-dir "$repo_root" \
  --full-auto \
  --output-last-message "$workspace_dir/.codex-last.txt" \
  "Complete $issue_id in this workspace. Canonical tracker root: $repo_root. Run bd only from $repo_root. Keep changes scoped to $issue_id. Run the required verification commands before finishing. If bd is unhealthy, report the exact failure instead of retrying tracker mutations repeatedly. Update or close $issue_id only if bd is working."
```

When the repo needs a coordinator-owned service session such as `devenv up`, start that outside the worker first. The worker prompt should assume the tracker is already up, and report preflight failure instead of trying to own the shared service lifecycle.

## JJ Commit Flow

Default lane policy:

- one issue -> one workspace -> one primary visible commit
- one open working-copy change during implementation
- bookmarks only when publishing

Useful commands:

```bash
cd "$workspace_dir"

# Refine the open lane change while work is still in progress.
jj describe -m "$issue_id: clearer summary"

# Cut the final reviewable commit and open a fresh working-copy change.
jj commit -m "$issue_id: final summary"

# Publish only when needed by the repo flow.
publish_name="${issue_id}-${slug}"
jj bookmark create "$publish_name" -r @-
jj git push --bookmark "$publish_name"
```

Use stacked commits only when the issue truly benefits from separate review units. Otherwise keep amending the same lane change until the final `jj commit`.

## Publish and Landing

Default boundary:

- the worker finishes with a verified visible `jj` commit,
- bookmark creation and `jj git push` happen only when the brief asks for publish,
- PR creation or merge happens only when the brief names that landing step explicitly.

Keep landing ownership explicit:

- `worker` when the lane is expected to publish or land the change directly,
- `coordinator` when the outer shell should push, open the PR, or merge after verifying worker output,
- `user` when the lane should stop at a clean handoff point,
- `CI` when automation owns the final merge after review.

Useful commands:

```bash
cd "$workspace_dir"

# Default handoff artifact: the final visible commit.
jj log -r @-

# Publish only when the brief asks for it.
publish_name="${issue_id}-${slug}"
jj bookmark create "$publish_name" -r @-
jj git push --bookmark "$publish_name"

# After the change lands elsewhere, sync imported Git state before cleanup.
jj git fetch
jj workspace update-stale || true
```

After publication starts, do not rewrite history, move bookmarks, or force-push unless the repo flow or brief explicitly allows it.

If you need to relabel the current workspace without moving its directory:

```bash
cd "$workspace_dir"
jj workspace rename "${issue_id}-${slug}"
```

Use that only when the workspace directory path is already acceptable or when the path/name mismatch is intentional.

## Environment Notes

When the repo runtime is non-trivial, put that contract in the prompt instead of assuming the worker will rediscover it. Capture:

- how the worker is expected to enter the runtime,
- whether a coordinator-owned supervisor such as `devenv up` must already be running,
- which tools are assumed to be present, and
- whether runtime changes are in scope.

Default policy: runtime usage is in scope, runtime authoring is not. If the issue is specifically about flakes, shells, `devenv`, or dependency/tool provisioning, say that explicitly in the lane goal.

If runtime authoring is in scope and the repo has a Nix environment skill such as `nix-interrogation`, load it instead of expanding this reference into a shell-authoring guide.

Use stdin for a longer brief:

```bash
prompt_file="$repo_root/.codex-prompts/${issue_id}.md"
codex exec \
  -C "$workspace_dir" \
  --add-dir "$repo_root" \
  --full-auto \
  --output-last-message "$workspace_dir/.codex-last.txt" \
  - < "$prompt_file"
```

For parallel lanes or coordinator-driven runs, load `coordinator-mode.md` and build the prompt file from that worker brief contract.

Use this prompt structure:

```text
Complete issue <issue-id> in this workspace.

Context
- Active checkout root: <absolute path>
- Workspace path: <absolute path>
- Only active issue for this lane: <issue-id>
- Base revision: <revset used to create the workspace>

Tracker
- Canonical tracker root: <absolute path, usually the canonical repo root>
- Tracker preflight: <ready | degraded | unavailable>
- Shared backend owner: <coordinator | worker>
- Tracker mutations in scope: <yes | no>

Environment
- Enter runtime with: <command or already-active shell>
- Shared supervisor: <none | command already running in coordinator>
- Assumed tools: <bd, jj, language toolchain, repo wrapper, ...>
- Runtime changes in scope: <yes | no>

Publish and landing
- Publish in scope: <no | create bookmark and push | create PR | merge/land>
- Landing owner: <worker | coordinator | user | CI>
- Landing target: <branch, bookmark, PR base, or none>
- Rewrite after publish allowed: <yes | no>

Scope
- Goal: <what must be done>
- Non-goals: <what must not expand>
- Primary files: <paths or areas>
- If the issue is not ready, stop and propose a tighter split or follow-up instead of widening the lane.

Operational rules
- Run bd only from the canonical tracker root.
- Do not initialize another tracker in the workspace.
- Prefer repo-local workflow wrappers when they exist; fall back to raw `bd` and `jj` commands only when needed.
- File discovered work as linked follow-ups instead of widening scope.
- Treat the workspace as one primary open change unless the task explicitly needs a stack.
- If bd fails because the tracker backend is unhealthy, stop after a bounded diagnosis step and report the exact command and error.

Verification
- <command>
- <command>

Finish
- Summarize changes, verification, and remaining risks.
- State whether the lane ended as one visible commit or a deliberate stack.
- State publish and landing status, including any bookmark, PR, or merge handle if one exists.
- Close the issue only if the repo's completion boundary is met. Otherwise leave an explicit handoff state and next owner.
- Leave the workspace clean or explain why not.
```

## Cleanup Checklist

Choose cleanup based on lane state.

If the repo ships a compaction wrapper such as `tuskd compact-lane`, prefer it over replaying handoff, finish, workspace cleanup, archive, and close manually.

### Landed

Run full cleanup only after the work is actually landed:

```bash
cd "$workspace_dir"
jj git fetch
jj workspace update-stale || true

cd "$repo_root"
bd ready --json >/dev/null
bd show "$issue_id"
jj --repository "$repo_root" workspace list
jj --repository "$repo_root" workspace forget "$workspace_name"
rm -rf "$workspace_dir"
bd close "$issue_id" --reason "Done" --json
```

### Published or handed off, not landed

- Keep the issue open.
- Record the visible commit, bookmark, or PR handle plus the next owner.
- Remove the workspace only if that handle is a sufficient handoff artifact. Otherwise keep it for follow-up.

### Parked or blocked

- Keep the workspace unless there is a deliberate reason to archive or remove it.
- Leave a handoff note in the repo's accepted memory surface and explain why the issue remains open, blocked, or in progress.
- Load `landing-and-recovery.md` when the base moved, the workspace went stale, or publication already happened.
- Load `issue-shaping.md` when the blocker is really an underspecified or over-broad issue.
