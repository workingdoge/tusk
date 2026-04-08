#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-clean [--repo PATH] [--quarantine-root PATH] [--skip-path GLOB] [--apply]

Conservative repo cleanup for rebuildable local artifacts.

Default mode is dry-run. With --apply, matching directories are moved into a
quarantine tree instead of being deleted.

Skipped by design:
- .git
- .jj
- .jj-workspaces
- .beads
- .devenv
- .direnv
- .claude
- .codex

Current candidate directories:
- node_modules
- .wrangler
- .terraform
- target
- dist-newstyle
- .pytest_cache
- .mypy_cache
- .ruff_cache
- .turbo
- .parcel-cache
- .next
- .nuxt

`--skip-path` may be repeated. Globs are matched against absolute candidate
paths after discovery.
EOF
}

repo_root="$(pwd)"
quarantine_root="${HOME}/.cache/tusk-clean"
apply_mode=0
skip_paths=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo_root="$2"
      shift 2
      ;;
    --quarantine-root)
      quarantine_root="$2"
      shift 2
      ;;
    --apply)
      apply_mode=1
      shift
      ;;
    --skip-path)
      skip_paths+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

repo_root="$(cd "$repo_root" && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"
repo_slug="$(printf '%s' "$repo_root" | tr '/: ' '---' | tr -cd '[:alnum:]._\n-')"
quarantine_dir="${quarantine_root}/${repo_slug}/${timestamp}"

mapfile -t raw_candidates < <(
  find "$repo_root" \
    \( \
      -type d \( \
        -name .git -o \
        -name .jj -o \
        -name .jj-workspaces -o \
        -name .beads -o \
        -name .devenv -o \
        -name .direnv -o \
        -name .claude -o \
        -name .codex \
      \) \
    \) -prune -o \
    -type d \
    \( \
      -name node_modules -o \
      -name .wrangler -o \
      -name .terraform -o \
      -name target -o \
      -name dist-newstyle -o \
      -name .pytest_cache -o \
      -name .mypy_cache -o \
      -name .ruff_cache -o \
      -name .turbo -o \
      -name .parcel-cache -o \
      -name .next -o \
      -name .nuxt \
    \) \
    -print | sort
)

candidates=()
for path in "${raw_candidates[@]}"; do
  skip_candidate=0
  for pattern in "${skip_paths[@]}"; do
    if [[ "$path" == $pattern ]]; then
      skip_candidate=1
      break
    fi
  done

  if [[ $skip_candidate -eq 0 ]]; then
    candidates+=("$path")
  fi
done

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "No cleanup candidates found under $repo_root"
  exit 0
fi

echo "Repo: $repo_root"
echo "Mode: $([[ $apply_mode -eq 1 ]] && echo apply || echo dry-run)"
echo "Candidates:"

for path in "${candidates[@]}"; do
  du -sh "$path" 2>/dev/null || true
done

if [[ $apply_mode -ne 1 ]]; then
  echo
  echo "Dry-run only. Re-run with --apply to move these paths into:"
  echo "  $quarantine_dir"
  exit 0
fi

mkdir -p "$quarantine_dir"
manifest="$quarantine_dir/MANIFEST.txt"
: > "$manifest"

for path in "${candidates[@]}"; do
  rel="${path#$repo_root/}"
  dest="$quarantine_dir/$rel"
  mkdir -p "$(dirname "$dest")"
  mv -f "$path" "$dest"
  printf '%s -> %s\n' "$path" "$dest" >> "$manifest"
done

echo
echo "Moved ${#candidates[@]} paths into:"
echo "  $quarantine_dir"
echo "Manifest:"
echo "  $manifest"
