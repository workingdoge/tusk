# Nix tooling after local probing

Do **not** start here.
Use this note after you know whether the task is topology, provenance, failure,
or authoring.

## Tooling doctrine
- Prefer the smallest factual probe over a large build.
- Prefer local evaluation over remote state.
- Prefer official docs after the probe, not before it.
- Validate the smallest changed slice, not the whole world.

## Inspection order
1. `python3 scripts/detect-shape.py .`
2. `scripts/probe-flake.sh .`
3. inspect only the narrow files involved
4. use focused `nix eval` or the helper probes
5. only then read docs

## Core tools
### Repo shape
- `python3 scripts/detect-shape.py .`
- `scripts/probe-flake.sh .`
- `rg -n '<pattern>' .`

Use when:
- you need to know whether the repo is plain flake, NixOS, Darwin, Home
  Manager, Den, or mixed
- you need to map outputs before changing anything

### Focused evaluation
- `scripts/probe-config-path.sh <flake-ref> <domain> <name> <config-path>`
- `scripts/probe-eval.sh '<installable>' [--show-trace]`
- `nix eval`

Use when:
- the question is about a realized value
- you want to test one installable or one config path
- you want to validate a narrow authoring slice before a build

### Interactive exploration
- `nix repl`

Use only after:
- the target path or expression is already narrow
- JSON evaluation is not enough

Avoid using `nix repl` as the first move.

### Build and realization checks
- `nix build <installable> --dry-run`
- `home-manager build --flake <flake-ref>#<name>` when the repo actually uses
  Home Manager in that form
- `darwin-rebuild build|switch --flake <flake-ref>#<name>` only at the system
  boundary

Use when:
- the authoring step changes realized system shape
- option-level `nix eval` is no longer enough

Prefer `build --dry-run` before any live switch.

### Hygiene tools
- `nix fmt`
- `statix check .`
- `deadnix .`

Use when:
- the repo already uses these tools
- formatting or linting is part of the requested change

Do not substitute linting for evaluation.

### Repo-local wrappers
If the flake or repo already provides wrappers, use them after the narrow probes.
Examples:
- `codex-nix-check`
- `nix run .#codex-nix-check`
- repo-local validation scripts

Treat wrappers as convenience, not as a replacement for understanding what is
being evaluated.

## Den-specific tool use
For Den questions, inspect in this order:
1. `flake.nix`
2. `den.default`
3. schema declarations such as `den.hosts`, `den.homes`, or other witnesses
4. the relevant `den.aspects`
5. the relevant `den.ctx.*` stages
6. only then the official Den docs

For Den authoring, prefer:
- narrow `nix eval` on the target output or config path
- `nix build --dry-run` for the target realization class
- source inspection of batteries before inventing a local replacement

## Failure handling
When evaluation fails:
1. save the trace
2. run `python3 scripts/classify-trace.py < trace.txt`
3. identify the first user-owned file
4. rerun the smallest failing installable with `scripts/probe-eval.sh`

Do not start with a full rebuild if a single installable already fails.

## Anti-patterns
Avoid:
- building the full system when one config path would answer the question
- reading large docs pages before probing the local flake
- using `nix repl` before the scope is narrow
- using a repo wrapper without understanding which installable it checks
