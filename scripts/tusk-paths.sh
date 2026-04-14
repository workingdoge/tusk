#!/usr/bin/env bash
set -euo pipefail

tusk__path_to_dir() {
  local path="$1"

  if [ -d "${path}" ]; then
    printf '%s\n' "${path}"
    return
  fi

  dirname "${path}"
}

tusk__find_flake_root_from() {
  local start="$1"
  local current=""

  current="$(cd "${start}" && pwd)"
  while :; do
    if [ -f "${current}/flake.nix" ]; then
      printf '%s\n' "${current}"
      return 0
    fi

    if [ "${current}" = "/" ]; then
      return 1
    fi

    current="$(dirname "${current}")"
  done
}

tusk__normalize_git_root() {
  local root="$1"

  case "${root}" in
    */.git)
      dirname "${root}"
      ;;
    *)
      printf '%s\n' "${root}"
      ;;
  esac
}

tusk__jj_git_root_from() {
  local start="$1"
  local root=""

  root="$(
    cd "${start}"
    jj git root 2>/dev/null || true
  )"

  [ -n "${root}" ] || return 1
  tusk__normalize_git_root "${root}"
}

tusk__git_root_from() {
  local start="$1"

  if (
    cd "${start}"
    git rev-parse --show-toplevel 2>/dev/null
  ); then
    return 0
  fi

  if tusk__jj_git_root_from "${start}" >/dev/null 2>&1; then
    tusk__jj_git_root_from "${start}"
    return 0
  fi

  (
    cd "${start}"
    pwd
  )
}

tusk__pwd_checkout_root() {
  if tusk__find_flake_root_from "${PWD}" >/dev/null 2>&1; then
    tusk__find_flake_root_from "${PWD}"
    return 0
  fi

  tusk__git_root_from "${PWD}"
}

tusk__pwd_tracker_root() {
  local current_root=""
  local workspace_suffix=""
  local canonical_root=""

  current_root="$(tusk__pwd_checkout_root)"

  if [ -d "${current_root}/.beads" ]; then
    printf '%s\n' "${current_root}"
    return 0
  fi

  workspace_suffix="/.jj-workspaces/"
  if [ "${current_root#*"${workspace_suffix}"}" != "${current_root}" ]; then
    canonical_root="${current_root%%${workspace_suffix}*}"
    if [ -n "${canonical_root}" ] && [ -d "${canonical_root}/.beads" ]; then
      printf '%s\n' "${canonical_root}"
      return 0
    fi
  fi

  return 1
}

tusk_resolve_checkout_root() {
  local repo_arg="${1:-}"
  local candidate=""
  local candidate_dir=""

  if [ -n "${repo_arg}" ]; then
    candidate_dir="$(tusk__path_to_dir "${repo_arg}")"
    if tusk__find_flake_root_from "${candidate_dir}" >/dev/null 2>&1; then
      tusk__find_flake_root_from "${candidate_dir}"
    else
      tusk__git_root_from "${candidate_dir}"
    fi
    return
  fi

  if tusk__pwd_checkout_root >/dev/null 2>&1; then
    tusk__pwd_checkout_root
    return
  fi

  if [ -n "${TUSK_CHECKOUT_ROOT:-}" ]; then
    candidate_dir="$(tusk__path_to_dir "${TUSK_CHECKOUT_ROOT}")"
    if tusk__find_flake_root_from "${candidate_dir}" >/dev/null 2>&1; then
      tusk__find_flake_root_from "${candidate_dir}"
    else
      tusk__git_root_from "${candidate_dir}"
    fi
    return
  fi

  for candidate in \
    "${DEVENV_ROOT:-}" \
    "${BEADS_WORKSPACE_ROOT:-}" \
    "${TUSK_FLAKE_ROOT:-}"
  do
    if [ -n "${candidate}" ]; then
      candidate_dir="$(tusk__path_to_dir "${candidate}")"
      if tusk__find_flake_root_from "${candidate_dir}" >/dev/null 2>&1; then
        tusk__find_flake_root_from "${candidate_dir}"
      else
        tusk__git_root_from "${candidate_dir}"
      fi
      return
    fi
  done

  tusk__git_root_from "${PWD}"
}

tusk_resolve_tracker_root() {
  local repo_arg="${1:-}"
  local candidate=""

  if [ -n "${repo_arg}" ]; then
    tusk__git_root_from "$(tusk__path_to_dir "${repo_arg}")"
    return
  fi

  if tusk__pwd_tracker_root >/dev/null 2>&1; then
    tusk__pwd_tracker_root
    return
  fi

  for candidate in \
    "${TUSK_TRACKER_ROOT:-}" \
    "${BEADS_WORKSPACE_ROOT:-}" \
    "${DEVENV_ROOT:-}" \
    "${TUSK_FLAKE_ROOT:-}"
  do
    if [ -n "${candidate}" ]; then
      tusk__git_root_from "$(tusk__path_to_dir "${candidate}")"
      return
    fi
  done

  tusk__git_root_from "${PWD}"
}

tusk_export_runtime_roots() {
  local checkout_root="$1"
  local tracker_root="$2"

  export TUSK_CHECKOUT_ROOT="${checkout_root}"
  export TUSK_TRACKER_ROOT="${tracker_root}"
  export DEVENV_ROOT="${checkout_root}"
  export BEADS_WORKSPACE_ROOT="${tracker_root}"
}

# Legacy tracker state can carry a malformed self-pointing Dolt remote that
# causes every write to emit noisy auto-push warnings. Drop only that exact URL.
tusk__legacy_self_dolt_remote_url() {
  local repo_root="$1"

  printf 'git+ssh://file////%s\n' "${repo_root#/}"
}

tusk__parse_remote_name() {
  local line="$1"

  printf '%s\n' "${line%%[[:space:]]*}"
}

tusk__parse_remote_url() {
  local line="$1"
  local name=""
  local rest=""

  name="$(tusk__parse_remote_name "${line}")"
  rest="${line#"$name"}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  printf '%s\n' "${rest}"
}

tusk_find_legacy_self_dolt_remote_name() {
  local repo_root="$1"
  local bd_bin="$2"
  local legacy_url=""
  local line=""
  local name=""
  local url=""

  legacy_url="$(tusk__legacy_self_dolt_remote_url "${repo_root}")"
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    case "${line}" in
      No\ remotes\ configured.*)
        continue
        ;;
    esac

    name="$(tusk__parse_remote_name "${line}")"
    url="$(tusk__parse_remote_url "${line}")"
    if [ "${url}" = "${legacy_url}" ]; then
      printf '%s\n' "${name}"
      return 0
    fi
  done <<EOF
$("${bd_bin}" dolt remote list 2>/dev/null || true)
EOF

  return 1
}

tusk_heal_legacy_self_dolt_remote() {
  local repo_root="$1"
  local bd_bin="$2"
  local remote_name=""
  local remove_output=""

  if ! remote_name="$(tusk_find_legacy_self_dolt_remote_name "${repo_root}" "${bd_bin}")"; then
    return 0
  fi

  if remove_output="$("${bd_bin}" dolt remote remove "${remote_name}" 2>&1)"; then
    return 0
  fi

  if ! tusk_find_legacy_self_dolt_remote_name "${repo_root}" "${bd_bin}" >/dev/null 2>&1; then
    return 0
  fi

  echo "tusk: failed to remove legacy self-pointing Dolt remote ${remote_name}" >&2
  if [ -n "${remove_output}" ]; then
    printf '%s\n' "${remove_output}" >&2
  fi
  return 0
}
