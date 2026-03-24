# Tusk Managed-Repo Bootstrap Contract

## Status

Design note for the minimum contract a repo must satisfy to be treated as a
`tusk`-managed bootstrap target.

This note is intentionally narrower than a workflow control plane and narrower
than the full `tusk` operational calculus. Its job is to define how `tusk`
finds a repo, enters the right shell, discovers repo-local tracker and workspace
conventions, and begins disciplined work without taking ownership away from the
repo itself.

## Intent

`tusk` is bootstrap first.

That means the first contract it needs with a consumer repo is:

1. how to resolve the canonical repo root,
2. how to enter the repo's managed shell or equivalent runtime,
3. how to discover whether repo-local tracker state exists,
4. how to discover the repo's lane and workspace conventions,
5. and how to begin work without introducing a universal execution tracker.

The important boundary is:

- `tusk` bootstrap provides shared startup discipline,
- the consumer repo keeps authority over its own tracker, workspaces, and
  landing rules.

## Non-Goals

This contract does **not** define:

- a global execution tracker,
- a cross-repo control plane,
- a mandatory tracker lease service,
- one required lane wrapper such as `bd-lane`,
- or one required on-disk registry format.

Those may exist later as optional overlays. They are not required for bootstrap
adoption.

## Core Doctrine

A repo is `tusk`-managed when `tusk` can determine a stable bootstrap surface
for that repo without guessing at undeclared conventions.

The bootstrap surface is:

- canonical repo identity,
- shell entry,
- tracker mode,
- service preflight expectations,
- workspace layout,
- and repo-local guidance.

The bootstrap surface is **not**:

- issue truth,
- lane truth,
- tracker ownership,
- or landing authority.

Those remain repo-local.

## Managed-Repo Contract

The minimum managed-repo contract is:

### 1. Canonical Repo Root

The repo MUST have one canonical root that can be resolved deterministically.

The RECOMMENDED rule is:

- explicit `--repo` path first,
- otherwise registry entry,
- otherwise `git rev-parse --show-toplevel`.

All tracker, workspace, and shell conventions are relative to that root.

### 2. Shell Entry

The repo MUST declare how a worker or coordinator enters the managed runtime.

Examples:

- `nix develop --no-pure-eval path:.`
- `direnv allow` plus `use flake`
- repo-local wrapper around one of the above

This command is bootstrap-relevant because it determines whether `bd`, `jj`,
`dolt`, `codex`, and related helpers are ambient assumptions or managed repo
tools.

### 3. Tracker Mode

The repo MUST declare whether repo-local tracker state exists and, if it does,
how it is preflighted.

Minimum cases:

- `none`
- `bd-local`

If `bd-local` is active, the repo MUST declare:

- whether `.beads/` is expected under the repo root,
- the read-path preflight command, e.g. `bd ready --json`,
- whether a shared service such as `devenv up` is required before tracker use,
- and whether the tracker is coordinator-owned shared infrastructure.

### 4. Workspace Policy

The repo MUST declare the execution-lane workspace convention when lane
isolation is expected.

Minimum useful fields are:

- workspace tool, e.g. `jj`,
- workspace root, e.g. `.jj-workspaces/`,
- base revision selection rule, e.g. `main`,
- and lane naming convention, e.g. `{issue_id}-{slug}`.

### 5. Repo-Local Guidance

The repo MUST expose repo-local guidance for human and agent users.

The RECOMMENDED minimum is:

- `AGENTS.md` at the repo root,
- or an equivalent repo-local bootstrap note.

This is where repo-specific non-generic workflow constraints live.

## Registry Surface

The managed-repo registry should stay minimal.

It is a bootstrap discovery aid, not a second tracker.

The minimum content-equivalent registry entry is:

```text
RepoBootstrapEntry {
  repo_id,
  repo_root,
  shell,
  tracker,
  workspace,
  guidance
}
```

where:

- `repo_id` is a stable human-meaningful identifier,
- `repo_root` identifies the canonical repo path,
- `shell` declares runtime entry,
- `tracker` declares tracker mode and preflight,
- `workspace` declares lane layout,
- `guidance` points to repo-local instructions.

### Shell Entry Surface

The shell surface should be equivalent in content to:

```text
RepoShellEntry {
  kind,
  command,
  managed_by?,
  requires_direnv?
}
```

### Tracker Entry Surface

The tracker surface should be equivalent in content to:

```text
RepoTrackerEntry {
  kind,
  preflight_command?,
  service_command?,
  service_policy,
  coordinator_owned?
}
```

### Workspace Entry Surface

The workspace surface should be equivalent in content to:

```text
RepoWorkspaceEntry {
  kind,
  root,
  base_rev,
  naming
}
```

## Registry Flow

The bootstrap flow for a managed repo should be:

1. resolve the target repo,
2. load or infer the bootstrap entry,
3. enter the declared shell,
4. ensure shared services required by the tracker mode,
5. preflight the tracker when one exists,
6. claim or inspect issue state in the repo's own tracker,
7. create an isolated workspace according to the repo's workspace policy.

This preserves the right ownership boundary:

- bootstrap determines how to start,
- repo-local state determines what is true.

## Resolution Precedence

The RECOMMENDED precedence is:

1. explicit repo path or id supplied by the caller,
2. registry lookup by `repo_id`,
3. repo inference from the current working directory.

If no bootstrap entry exists, `tusk` MAY still operate in inferred mode, but it
MUST treat inferred values as local bootstrap facts, not as globally registered
truth.

## Bootstrap Adoption Tiers

It is useful to distinguish three tiers.

### Tier 0: Local Inference

`tusk` discovers a repo from the current directory and infers shell/tracker
facts locally.

### Tier 1: Registered Bootstrap Target

The repo has a stable registry entry that declares the bootstrap surface.

### Tier 2: Extended Workflow Overlay

The repo participates in optional overlays such as:

- tracker lease services,
- richer lane receipts,
- cross-repo planning references,
- or shared orchestration.

This tier is explicitly downstream of bootstrap.

## Relationship To Repo-Local Authority

The contract is only successful if it preserves repo-local authority.

In particular:

- repo-local trackers remain canonical for repo-local implementation issues,
- repo-local workspace state remains canonical for lane execution,
- repo-local landing rules remain canonical for landing and closure,
- registry state MUST NOT redefine repo-local issue state.

The registry tells `tusk` how to start work in a repo.
It does not tell the repo what work exists.

## Relationship To Future Shared Shell Work

This contract should precede extraction of a shared repo-shell constructor.

The constructor work in `tusk-9hx` should implement this contract, not invent a
different one.

That means:

- `63d` defines what a consumer repo must declare,
- `9hx` defines how `tusk` can package that shell surface for reuse.

## Recommendation

Proceed with:

1. a minimal bootstrap registry schema,
2. explicit shell/tracker/workspace/guidance fields,
3. explicit resolution precedence,
4. explicit preservation of repo-local tracker authority,
5. optional inference mode for unregistered repos,
6. and no assumption that wrappers or control-plane services exist yet.
