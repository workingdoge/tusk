set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  init-tusk-control-plane [--project NAME] [--tusk-input FLAKE_REF] TARGET_DIR

Bootstraps a new canonical bd+jj control-plane repo that imports tusk.

Options:
  --project NAME         Project name passed to `bd init` (default: TARGET_DIR basename)
  --tusk-input FLAKE_REF Flake ref to import as `tusk` (default: path:$repo_root or $TUSK_INPUT)
  -h, --help             Show this help text
EOF
}

project_name=""
tusk_input="${TUSK_INPUT:-}"
target_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      shift
      [ $# -gt 0 ] || { echo "error: --project requires a value" >&2; exit 1; }
      project_name="$1"
      ;;
    --tusk-input)
      shift
      [ $# -gt 0 ] || { echo "error: --tusk-input requires a value" >&2; exit 1; }
      tusk_input="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "$target_dir" ]; then
        echo "error: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      target_dir="$1"
      ;;
  esac
  shift
done

[ -n "$target_dir" ] || { usage >&2; exit 1; }

if [ -e "$target_dir" ] && find "$target_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
  echo "error: target directory is not empty: $target_dir" >&2
  exit 1
fi

mkdir -p "$target_dir"
target_dir="$(cd "$target_dir" && pwd)"

if [ -z "$project_name" ]; then
  project_name="$(basename "$target_dir")"
fi

if [ -z "$tusk_input" ]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$repo_root" ] && [ -f "$repo_root/flake.nix" ]; then
    tusk_input="path:$repo_root"
  fi
fi

if [ -z "$tusk_input" ]; then
  echo "error: could not determine tusk input; pass --tusk-input or set TUSK_INPUT" >&2
  exit 1
fi

mkdir -p \
  "$target_dir/data" \
  "$target_dir/decisions" \
  "$target_dir/runs" \
  "$target_dir/scripts"

cat > "$target_dir/.gitignore" <<'EOF'
.beads/
.devenv/
.direnv/
.jj/
.jj-workspaces/
.codex-prompts/
result
result-*
EOF

cat > "$target_dir/README.md" <<EOF
${project_name} is the canonical cross-repo control plane.

Rule:
- Product code stays in specialized repos.
- Tracking, operating notes, and shared execution artifacts live here.
- This repo is the canonical \`bd\` + \`jj\` root for cross-repo work.

Structure:
- \`STATUS.md\`: live execution status
- \`data/\`: imported artifacts and checkpoints
- \`decisions/\`: short dated decisions
- \`runs/\`: execution notes and evidence
- \`scripts/\`: thin glue scripts across repos

Workflow:
- run \`bd\` from this repo root
- use \`jj\` for local history and workspaces
- keep product code changes in specialized repos

Nix:
- \`flake.nix\` imports \`${tusk_input}\` as \`tusk\`
- use \`nix develop\` from this repo root
- use \`nix run .#install-tusk-openai-skill\` to install the bundled skill
EOF

cat > "$target_dir/STATUS.md" <<'EOF'
# Status

Current milestone:
- establish the control plane and convert active work into tracked issues

This week:
- confirm the source inventory
- define the immediate execution boundary
- cut the first visible `jj` commits for active setup work

Blockers:
- none recorded yet

Frozen:
- anything that does not improve the active critical path
EOF

cat > "$target_dir/data/README.md" <<'EOF'
Store imported artifacts, normalized outputs, and checkpoints here.
EOF

cat > "$target_dir/decisions/README.md" <<'EOF'
Keep short dated decisions here with the rationale and the chosen path.
EOF

cat > "$target_dir/runs/README.md" <<'EOF'
Keep dated execution notes and evidence here.
EOF

cat > "$target_dir/scripts/README.md" <<'EOF'
Keep thin cross-repo glue scripts here.
EOF

cat > "$target_dir/flake.nix" <<EOF
{
  description = "${project_name} control plane";

  inputs = {
    tusk.url = "${tusk_input}";
  };

  outputs = { self, tusk, ... }:
    let
      system = "aarch64-darwin";
      pkgs = tusk.inputs.nixpkgs.legacyPackages.\${system};
      beads = tusk.inputs.llm-agents.packages.\${system}.beads;
      codexPkg = tusk.inputs.llm-agents.packages.\${system}.codex;
      repoCodex = pkgs.writeShellApplication {
        name = "codex";
        runtimeInputs = [
          beads
          pkgs.git
        ];
        text = ''
          set -eu

          repo_root="''\${BEADS_WORKSPACE_ROOT:-\$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
          cd "\$repo_root"
          export BEADS_WORKSPACE_ROOT="\$repo_root"

          exec \${codexPkg}/bin/codex -C "\$repo_root" "\$@"
        '';
      };
    in
    {
      apps.\${system} = {
        beads = tusk.apps.\${system}.beads;
        codex = {
          type = "app";
          program = "\${repoCodex}/bin/codex";
        };
        codex-nix-check = tusk.apps.\${system}.codex-nix-check;
        init-tusk-control-plane = tusk.apps.\${system}.init-tusk-control-plane;
        install-tusk-openai-skill = tusk.apps.\${system}.install-tusk-openai-skill;
      };

      packages.\${system}.tusk-openai-skill = tusk.packages.\${system}.tusk-openai-skill;

      devShells.\${system}.default = pkgs.mkShell {
        packages = [
          beads
          repoCodex
          pkgs.direnv
          pkgs.dolt
          pkgs.git
          pkgs.jujutsu
          pkgs.jq
          pkgs.nixfmt
          pkgs.ripgrep
        ];

        shellHook = ''
          repo_root="\$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          export HOME_OPS_ROOT="\$repo_root"
          export BEADS_WORKSPACE_ROOT="\$repo_root"

          echo "${project_name} control plane"
          echo "  bd ready --json"
          echo "  jj st"
          echo "  nix run .#install-tusk-openai-skill"
        '';
      };

      formatter.\${system} = pkgs.nixfmt;
    };
}
EOF

(
  cd "$target_dir"
  git init -b main >/dev/null
  jj git init --colocate . >/dev/null
  bd init -p "$project_name" >/dev/null
)

cat > "$target_dir/AGENTS.md" <<'EOF'
# Agent Instructions

This project uses **bd** (beads) for issue tracking and **jj** (jujutsu) for local history/workspace management. Run `bd onboard` to get started.

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
jj st                 # Show working-copy status
jj log                # Show revision history
jj workspace add ...  # Create an issue workspace
bd sync               # Sync tracker exports with the git backing repo
```

## Workflow

- Run `bd` from the repo root.
- Use `jj` as the local history and workspace manager.
- Keep product code in specialized repos; use this repo as the cross-repo control plane.

## Issue Tracking

- Use `bd` for all task tracking.
- Use `--json` for programmatic access.
- Create linked follow-up issues for discovered work instead of expanding the current lane.

## Landing the Plane

Default completion boundary here is a visible `jj` commit, not an implicit git push.

1. File issues for remaining work.
2. Run the relevant quality gates.
3. Update issue status.
4. Cut a visible `jj` commit.
5. Sync tracker state if needed.
6. Publish only if that is actually in scope.
EOF

(
  cd "$target_dir"
  git add .gitignore AGENTS.md README.md STATUS.md flake.nix data/README.md decisions/README.md runs/README.md scripts/README.md
)

echo "Bootstrapped control plane at $target_dir"
echo "  project: $project_name"
echo "  tusk input: $tusk_input"
echo "  next: cd \"$target_dir\" && nix run .#beads -- status --json && jj st"
