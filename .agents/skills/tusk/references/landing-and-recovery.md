# Landing and Recovery

Use this reference when the lane does not simply end at "one visible commit and stop", or when the lane's base, publish state, or landing owner changed mid-run.

## Landing Modes

### Stop at visible commit

- This is the default `tusk` endpoint.
- The worker leaves a verified visible `jj` commit and reports the handoff artifact.
- If another owner will publish or merge later, leave the issue open and record who owns the next step.

### Publish bookmark

- Create the bookmark late and push it only when the brief asks for publish.
- Record the exact bookmark name and remote handle.
- A pushed bookmark is usually a handoff point, not "done". Leave the issue open unless the repo explicitly treats publish as completion.

### Merge or land

- Only the declared landing owner should merge or land the change.
- After the merge lands elsewhere, fetch imported Git state, refresh the workspace if needed, then clean up the lane and close the issue.

## Issue State Rules

- A visible commit is not the same thing as landed work.
- A pushed bookmark or opened PR is not the same thing as merged work.
- Close the `bd` issue only when the repo's completion boundary is satisfied.
- If landing is owned by `coordinator`, `user`, or `CI`, leave the issue open and record:
  - the current visible commit or bookmark,
  - the next owner, and
  - the next expected event, such as review, merge, or follow-up verification.

## Recovery Patterns

### Base moved before landing

```bash
cd "$workspace_dir"
jj git fetch
jj rebase -b @ -o <new-base>
```

- Use this when the target base advanced and the lane should move with it.
- If conflicts appear, resolve them only if that is clearly in scope. Otherwise stop and report the exact conflict state.

### Workspace became stale after landing elsewhere

```bash
cd "$workspace_dir"
jj git fetch
jj workspace update-stale
```

- Use this before cleanup when another workspace, user, or merge queue landed related work.

### Publish already happened and review asked for changes

- If rewrite-after-publish is allowed, rewrite intentionally and report that the bookmark moved.
- If rewrite-after-publish is not allowed, add a follow-up commit or open a follow-up lane instead of force-pushing silently.

### Worker stopped after publish but before issue mutation

- Verify the bookmark, PR, or merge handle first.
- Then decide whether to relaunch the same workspace, leave a handoff, or close the issue.
- Do not assume the issue can be closed just because publication succeeded.

## Cleanup by State

### Landed

- Fetch imported Git state.
- Update the stale workspace if needed.
- Forget and remove the workspace.
- Close the issue.

### Published or handed off, not landed

- Keep the issue open.
- Record the bookmark or PR handle and the next owner.
- Remove the workspace only if that published handle is a sufficient handoff artifact. Otherwise keep it.

### Parked or blocked

- Keep the workspace or archive it intentionally.
- Leave the issue open with the exact blocker and the next owner.
