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

tusk__git_root_from() {
  local start="$1"

  (
    cd "${start}"
    git rev-parse --show-toplevel 2>/dev/null || pwd
  )
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

  if [ -n "${TUSK_CHECKOUT_ROOT:-}" ]; then
    candidate_dir="$(tusk__path_to_dir "${TUSK_CHECKOUT_ROOT}")"
    if tusk__find_flake_root_from "${candidate_dir}" >/dev/null 2>&1; then
      tusk__find_flake_root_from "${candidate_dir}"
    else
      tusk__git_root_from "${candidate_dir}"
    fi
    return
  fi

  if tusk__find_flake_root_from "${PWD}" >/dev/null 2>&1; then
    tusk__find_flake_root_from "${PWD}"
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

  for candidate in \
    "${repo_arg}" \
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
