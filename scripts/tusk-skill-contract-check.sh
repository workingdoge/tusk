#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-skill-contract-check [--repo PATH]

Validate repo-authored portable skill structure, optional OpenAI overlays, and
the repo-local Codex plus Claude skill projection contract.
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

check_openai_overlay() {
  local skill_name="$1"
  local openai_yaml="$2"

  grep -Eq '^interface:$' "$openai_yaml"
  grep -Eq '^  display_name: .+$' "$openai_yaml"
  grep -Eq '^  short_description: .+$' "$openai_yaml"
  grep -Eq '^  default_prompt: .+\$'"${skill_name}"'.*$' "$openai_yaml"
}

check_skill_source() {
  local skill_name="$1"
  local skill_root=".agents/skills/$skill_name"
  local skill_md="$skill_root/SKILL.md"
  local openai_yaml="$skill_root/agents/openai.yaml"
  local frontmatter=""

  test -d "$skill_root"
  test -f "$skill_md"

  frontmatter="$(extract_frontmatter "$skill_md")"
  test -n "$frontmatter"
  printf '%s\n' "$frontmatter" | grep -Eq "^name: ${skill_name}\$"
  printf '%s\n' "$frontmatter" | grep -Eq '^description:'

  if [ -f "$openai_yaml" ]; then
    check_openai_overlay "$skill_name" "$openai_yaml"
  fi
}

skill_names=()
for skill_root in .agents/skills/*; do
  [ -d "$skill_root" ] || continue
  skill_names+=("$(basename "$skill_root")")
done

test "${#skill_names[@]}" -gt 0

for skill_name in "${skill_names[@]}"; do
  check_skill_source "$skill_name"
done

check_script="$(mktemp "${TMPDIR:-/tmp}/tusk-skill-contract-check.XXXXXX")"
trap 'rm -f "$check_script"' EXIT
cat >"$check_script" <<'EOF'
cd "$DEVENV_ROOT"
shopt -s nullglob
test "$CODEX_HOME" = "$DEVENV_ROOT/.codex"
check_no_store_skill_artifacts() {
  local skill_root link_path link_target
  skill_root="$1"
  for link_path in "$skill_root"/*; do
    [ -e "$link_path" ] || continue
    [ -L "$link_path" ] || continue
    link_target="$(readlink "$link_path")"
    case "$link_target" in
      /nix/store/*-skill|/nix/store/*-openai-skill)
        echo "unexpected projected store skill artifact under $skill_root" >&2
        exit 1
        ;;
    esac
  done
}
for skill_root in .agents/skills/*; do
  [ -d "$skill_root" ] || continue
  skill_name="$(basename "$skill_root")"
  check_no_store_skill_artifacts "$skill_root"
  test -L ".codex/skills/$skill_name"
  test "$(readlink ".codex/skills/$skill_name")" = "$DEVENV_ROOT/.agents/skills/$skill_name"
  test -f ".codex/skills/$skill_name/SKILL.md"
  test -L ".claude/skills/$skill_name"
  test "$(readlink ".claude/skills/$skill_name")" = "$DEVENV_ROOT/.agents/skills/$skill_name"
  test -f ".claude/skills/$skill_name/SKILL.md"
done
EOF

if [ "${DEVENV_ROOT:-}" = "$checkout_root" ] && [ "${CODEX_HOME:-}" = "$checkout_root/.codex" ]; then
  bash "$check_script"
else
  nix develop --no-pure-eval "path:$checkout_root" \
    -c env \
      TUSK_CHECKOUT_ROOT="$TUSK_CHECKOUT_ROOT" \
      TUSK_TRACKER_ROOT="$TUSK_TRACKER_ROOT" \
      DEVENV_ROOT="$TUSK_CHECKOUT_ROOT" \
      BEADS_WORKSPACE_ROOT="$TUSK_TRACKER_ROOT" \
      bash "$check_script"
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
    dogfoodCodexSkills = dogfood.config.codex.skills or { };
    dogfoodClaudeSkills = dogfood.config.claude.skills or { };
    authoredSkills = pkgs.lib.filterAttrs (_: kind: kind == "directory") (builtins.readDir (flake.outPath + "/.agents/skills"));
    skillNames = builtins.attrNames authoredSkills;
  in
  if
    builtins.length skillNames > 0
    && builtins.all (name: ! builtins.hasAttr ".codex/skills/${name}" consumerFiles) skillNames
    && builtins.all (name: ! builtins.hasAttr ".claude/skills/${name}" consumerFiles) skillNames
    && builtins.all (name: ! builtins.hasAttr ".codex/skills/${name}" dogfoodFiles) skillNames
    && builtins.all (name: ! builtins.hasAttr ".claude/skills/${name}" dogfoodFiles) skillNames
    && builtins.all (name: (dogfoodCodexSkills.${name}.runtimePath or null) == ".agents/skills/${name}") skillNames
    && builtins.all (name: (dogfoodClaudeSkills.${name}.runtimePath or null) == ".agents/skills/${name}") skillNames
  then
    "ok"
  else
    throw "consumer/dogfood skill contract mismatch"
' >/dev/null
