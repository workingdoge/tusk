#!/bin/sh
set -eu

repo_root="${1:?repo root required}"
home_root="${2:-.codex}"
codex_home="${repo_root}/${home_root}"
legacy_home="${HOME}/.codex"

mkdir -p \
  "${codex_home}" \
  "${codex_home}/skills" \
  "${codex_home}/log" \
  "${codex_home}/sessions" \
  "${codex_home}/sqlite" \
  "${codex_home}/tmp"

copy_file_if_missing() {
  src="$1"
  dest="$2"

  if [ -e "$dest" ] || [ ! -f "$src" ]; then
    return 0
  fi

  cp -f "$src" "$dest"
}

copy_dir_if_missing() {
  src="$1"
  dest="$2"

  if [ -e "$dest" ] || [ ! -d "$src" ]; then
    return 0
  fi

  cp -Rf "$src" "$dest"
}

strip_skill_config() {
  src="$1"
  dest="$2"

  awk '
    BEGIN { skip = 0 }
    /^\[\[skills\.config\]\][[:space:]]*$/ {
      skip = 1
      next
    }
    skip && /^\[/ {
      skip = 0
    }
    !skip {
      print
    }
  ' "$src" > "$dest"
}

if [ ! -e "${codex_home}/config.toml" ] && [ -f "${legacy_home}/config.toml" ]; then
  tmp_config="${codex_home}/config.toml.tmp"
  strip_skill_config "${legacy_home}/config.toml" "${tmp_config}"
  mv -f "${tmp_config}" "${codex_home}/config.toml"
fi

copy_file_if_missing "${legacy_home}/auth.json" "${codex_home}/auth.json"
copy_file_if_missing "${legacy_home}/instructions.md" "${codex_home}/instructions.md"
copy_dir_if_missing "${legacy_home}/rules" "${codex_home}/rules"
