# Official-source platform map

Use this file after the local flake shape is known.

## Official sources
- flake.parts `actions-nix`:
  `https://flake.parts/options/actions-nix.html`
- flake.parts `git-hooks-nix`:
  `https://flake.parts/options/git-hooks-nix.html`
- flake.parts `hercules-ci-effects`:
  `https://flake.parts/options/hercules-ci-effects.html`
- Hercules CI effects docs:
  `https://docs.hercules-ci.com/hercules-ci/effects/`
- Hercules CI effects reference:
  `https://docs.hercules-ci.com/hercules-ci-agent/effects.html`
- actions.nix source:
  `https://github.com/nialov/actions.nix`

## Positioning
### git-hooks-nix
Use for:
- local developer hygiene
- pre-commit hooks
- check definitions integrated into the flake

Do not treat it as the center of CI/CD architecture.

### actions.nix
Use for:
- generating GitHub or Gitea workflow files from Nix
- keeping workflow definition closer to the flake

Read it as a transport-layer tool.
It helps author workflow YAML in Nix, but it does not by itself give a deeper
effects model.

### hercules-ci-effects
Use for:
- post-success actions that should only run after validated jobs
- workflows needing secrets and mutable state
- release, deployment, lockfile update, and similar effectful continuations

Read it as an effects layer, not just another CI frontend.
This is the better fit when the semantic center is "verified sections plus
admissible effects."

## Selection rule
- Choose `actions.nix` when forge workflow generation is the main problem.
- Choose Hercules plus effects when principled effectful continuation is the
  main problem.
- Keep `git-hooks-nix` orthogonal; it can coexist with either path.

## Adjacent threshold tools
These are not the center of the skill, but may matter at the realization edge:
- `deploy-rs`
- `colmena`
- `attic`

Read them as downstream realization tools, not as substitutes for the pipeline
model itself.
