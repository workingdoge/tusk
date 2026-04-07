# Coordinator Mode

## When To Use

Use coordinator mode when:

- two or more issue lanes are active,
- the user wants parallel `codex exec` runs,
- the user wants compact progress reporting instead of worker transcripts, or
- a worker needs a comprehensive brief with bounded stop conditions.

Treat the outer Codex as the coordinator and each `codex exec` run as a worker.

## Lane Ledger

Keep one lane ledger entry per active issue. Report lane updates as deltas, not full recaps.

Use this format:

```text
- <issue_id> <status> in <workspace>
  Goal: <one sentence>
  Latest: <newest material event>
  Verification: <not run | passed: ... | failed: ...>
  Next: <next action>
  Blocker: <none | exact blocker>
```

Use only these status values:

- `queued`
- `preflight`
- `running`
- `blocked`
- `verifying`
- `handoff`
- `done`

Coordinator update rules:

- Lead with the lanes that changed since the last user-visible update.
- Prefer exact file paths, issue ids, and commands over vague summaries.
- Do not paste full worker transcripts unless the user asks for them.
- If all lanes are unchanged, do not restate the full ledger.

Before launching a lane, prefer ready issues with clear verification and landing boundaries. If the repo ships workflow wrappers such as `bd-lane` or `bd-new-issue`, use those first instead of rebuilding repo-local setup by hand. If an issue is broad or underspecified, shape or split it first rather than passing ambiguity into the worker.

## Worker Brief Contract

Use this structure for any non-trivial `codex exec` worker.

```text
Complete issue <issue-id> in this workspace.

Identity
- Active checkout root: <absolute path>
- Workspace path: <absolute path>
- Workspace name: <name>
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

Objective
- Goal: <what must be done>
- Done when: <finish condition>
- Non-goals: <what must not expand>
- Primary files or areas: <paths>

Operational rules
- Run bd only from the canonical tracker root.
- Do not initialize another tracker in the workspace.
- Do not widen scope; file discovered work separately.
- If the issue is under-shaped, stop and propose a better split or follow-up instead of improvising scope.
- Do not rewrite the runtime contract unless that is explicit task scope.
- Stop at the declared landing boundary. Do not publish or merge just because the code is done.
- Do not close the issue unless the declared landing boundary also satisfies repo completion.
- Keep retries bounded. If the tracker or environment is unhealthy, report the exact failure instead of thrashing.

Verification
- <command>
- <command>

Stop conditions
- tracker backend unhealthy
- missing dependency or credential
- ambiguous scope or conflicting repo state
- verification command fails in a way the worker cannot repair safely

Output contract
- State whether the goal was completed.
- List the material file changes.
- Report verification results command by command.
- Report publish or landing status and any bookmark, PR, or merge handle created.
- Report whether the issue was closed, handed off, or left open, and why.
- If blocked, report the exact command, error, and recommended next action.
```

## Codex Exec Launch Pattern

For coordinator-driven runs, prefer stdin so the full brief stays readable and reproducible:

```bash
prompt_file="$repo_root/.codex-prompts/${issue_id}.md"
codex exec \
  -C "$workspace_dir" \
  --add-dir "$repo_root" \
  --full-auto \
  --output-last-message "$workspace_dir/.codex-last.txt" \
  - < "$prompt_file"
```

Use inline prompts only for trivial single-lane work.

If the repo ships a lane wrapper such as `bd-lane`, let the coordinator use it for claim, workspace creation, and prompt materialization before falling back to a hand-built `codex exec` launch. If the coordinator needs to tune the brief, edit the wrapper-generated prompt and then launch `codex exec` manually.

If the repo depends on a long-lived supervisor such as `devenv up`, keep that in the coordinator shell or PTY session. Do not make each worker lane responsible for starting or stopping the shared tracker backend.

If the repo needs a managed shell or runtime wrapper, capture that in the worker brief up front. Workers should not have to guess whether they are supposed to use plain shell commands, `nix develop`, `direnv`, `devenv`, or another repo-specific entrypoint.

## Coordinator Recovery Rules

If a worker stops on a bounded failure:

- repair environment or tracker issues in the coordinator shell, then relaunch or finish the lane,
- update the lane ledger before relaunching, and
- keep issue mutation in the coordinator shell when the tracker is unreliable.

Do not let workers improvise infrastructure repair loops unless that repair is explicitly part of the task scope.
