#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-skill-contract-check [--repo PATH]

Validate repo-authored skill structure, repo-owned OpenAI metadata, and the
repo-local Codex skill projection contract.
EOF
}

repo_arg=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      if [ "$#" -lt 2 ]; then
        echo "tusk-skill-contract-check: --repo requires a path argument" >&2
        exit 2
      fi
      repo_arg="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "tusk-skill-contract-check: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

export TUSK_PATHS_SH="${TUSK_PATHS_SH:?tusk-skill-contract-check requires TUSK_PATHS_SH}"
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

checkout_root="$(tusk_resolve_checkout_root "${repo_arg:-}")"
tracker_root="$(tusk_resolve_tracker_root "${repo_arg:-}")"
tusk_export_runtime_roots "$checkout_root" "$tracker_root"
cd "$checkout_root"

extract_frontmatter() {
  awk '
    BEGIN { marker = 0 }
    /^---$/ {
      marker += 1
      if (marker == 1) next
      if (marker == 2) exit
    }
    marker == 1 { print }
  ' "$1"
}

check_skill_source() {
  local skill_name="$1"
  local skill_root=".agents/skills/$skill_name"
  local skill_md="$skill_root/SKILL.md"
  local openai_yaml="$skill_root/agents/openai.yaml"
  local frontmatter=""

  test -d "$skill_root"
  test -f "$skill_md"
  test -f "$openai_yaml"

  frontmatter="$(extract_frontmatter "$skill_md")"
  test -n "$frontmatter"
  printf '%s\n' "$frontmatter" | grep -Eq "^name: ${skill_name}\$"
  printf '%s\n' "$frontmatter" | grep -Eq '^description:'

  grep -Eq '^interface:$' "$openai_yaml"
  grep -Eq '^  display_name: .+$' "$openai_yaml"
  grep -Eq '^  short_description: .+$' "$openai_yaml"
  grep -Eq '^  default_prompt: .+\$'"${skill_name}"'.*$' "$openai_yaml"
}

for skill_name in tusk ops nix skill-dev; do
  check_skill_source "$skill_name"
done

check_cmd="$(cat <<'EOF'
cd "$DEVENV_ROOT"
test "$CODEX_HOME" = "$DEVENV_ROOT/.codex"
for skill_name in tusk ops nix skill-dev; do
  test -L ".codex/skills/$skill_name"
  test "$(readlink ".codex/skills/$skill_name")" = "$DEVENV_ROOT/.agents/skills/$skill_name"
  test -f ".codex/skills/$skill_name/SKILL.md"
done
EOF
)"

if [ "${DEVENV_ROOT:-}" = "$checkout_root" ] && [ "${CODEX_HOME:-}" = "$checkout_root/.codex" ]; then
  sh -lc "$check_cmd"
else
  nix develop --no-pure-eval "path:$checkout_root" \
    -c sh -lc "export TUSK_CHECKOUT_ROOT=\"$TUSK_CHECKOUT_ROOT\"; export TUSK_TRACKER_ROOT=\"$TUSK_TRACKER_ROOT\"; export DEVENV_ROOT=\"$TUSK_CHECKOUT_ROOT\"; export BEADS_WORKSPACE_ROOT=\"$TUSK_TRACKER_ROOT\"; $check_cmd"
fi

nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake "path:'"$checkout_root"'";
    pkgs = flake.inputs.nixpkgs.legacyPackages.'"${TUSK_SKILL_CHECK_SYSTEM:?tusk-skill-contract-check requires TUSK_SKILL_CHECK_SYSTEM}"';
    consumer = flake.inputs.devenv.lib.mkShell {
      inherit (flake) inputs;
      inherit pkgs;
      modules = [
        flake.devenvModules.consumer
        {
          tusk.consumer.enable = true;
          tusk.consumer.smokeCheck.enable = false;
        }
      ];
    };
    dogfood = flake.inputs.devenv.lib.mkShell {
      inherit (flake) inputs;
      inherit pkgs;
      modules = [ flake.devenvModules.dogfood ];
    };
    consumerFiles = consumer.config.files or { };
    dogfoodFiles = dogfood.config.files or { };
  in
  if
    (! builtins.hasAttr ".codex/skills/tusk" consumerFiles)
    && (! builtins.hasAttr ".codex/skills/ops" consumerFiles)
    && (! builtins.hasAttr ".codex/skills/nix" consumerFiles)
    && (! builtins.hasAttr ".codex/skills/skill-dev" consumerFiles)
    && builtins.hasAttr ".codex/skills/tusk" dogfoodFiles
    && builtins.hasAttr ".codex/skills/ops" dogfoodFiles
    && builtins.hasAttr ".codex/skills/nix" dogfoodFiles
    && builtins.hasAttr ".codex/skills/skill-dev" dogfoodFiles
  then
    "ok"
  else
    throw "consumer/dogfood skill contract mismatch"
' >/dev/null
