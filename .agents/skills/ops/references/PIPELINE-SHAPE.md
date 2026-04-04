# Pipeline shape after local inspection

Do **not** start here.
Inspect the flake and current automation surface first.

## Core model
Read a Nix-native operational pipeline as three layers:

1. Verified base
   Pure evaluations, builds, and checks.

2. Admissible effects
   Actions that are only allowed after the base has succeeded.
   Examples: release publication, deployment, lockfile update PRs, Pages
   publication.

3. Realizations
   The actual externalized side effects: deployed systems, pushed releases,
   updated repos, cache population.

## Why this skill exists
Many tools sit in different layers:
- `git-hooks-nix` lives close to local hygiene and check definition
- `actions.nix` lives at the forge workflow transport layer
- `hercules-ci-effects` lives at the admissible-effects layer
- deployment/cache tools live at the realization edge

So "CI/CD" is not one thing.

## Questions to answer first
1. What is already pure and validated?
2. What must remain pure?
3. What actions should happen only after success?
4. Where do secrets and mutable state enter?
5. Which platform is merely transport, and which platform is the semantic
   center?

## Practical split
### Verified base
Good contents:
- flake checks
- package builds
- system or home dry-runs
- linters and format checks
- lockfile consistency checks

### Admissible effects
Good contents:
- releases
- deployments
- auto-update PRs
- cache publication
- docs/site publication

### Secrets/state boundary
Treat secrets, credentials, and mutable deployment state as their own layer.
Do not blur them into ordinary checks.

## Selection rule
- If the repo only needs checks and forge events, a forge workflow transport may
  be enough.
- If the repo wants verified jobs plus principled effects, use a platform whose
  semantic center includes effects.

## Good outcomes
- a clear boundary between pure CI and effectful CD
- a small first effect rather than a giant pipeline rewrite
- room for unresolved design typeholes while the architecture is clarified
