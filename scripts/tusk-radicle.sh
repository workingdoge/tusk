#!/usr/bin/env bash
set -euo pipefail

program_name="tusk-radicle"
paths_sh="${TUSK_PATHS_SH:?TUSK_PATHS_SH is required}"

# shellcheck disable=SC1090
source "${paths_sh}"

default_branch="main"

usage() {
  cat <<'EOF'
Usage:
  tusk-radicle status [--repo PATH]
  tusk-radicle ensure-tools [--repo PATH]
  tusk-radicle fetch [--repo PATH] [--remote NAME]
  tusk-radicle push [--repo PATH] [--branch NAME] [--remote NAME]
  tusk-radicle init-existing --rid RID [--repo PATH] [--branch NAME]

Commands:
  status
      Print the current Radicle/Git hybrid wiring for the repo.

  ensure-tools
      Verify that the Radicle transport toolchain required by this helper is
      available and print the resolved tool paths.

  fetch
      Fetch Radicle refs through the helper-owned toolchain. Default remote:
      `rad`.

  push
      Push the selected branch to the Radicle remote through the helper-owned
      toolchain. Default remote: `rad`. Default branch: `main`.

  init-existing
      Attach an existing Radicle RID to the repo without stealing the GitHub
      branch upstream from `origin`. This uses `rad init --existing` to add the
      Radicle remote and signing configuration, then restores the branch
      upstream to the pre-existing Git remote.

Options:
  --repo PATH         Resolve the target checkout from PATH instead of $PWD.
  --rid RID           Existing Radicle RID to attach.
  --branch NAME       Branch whose Git upstream should be preserved. Default: main
  --remote NAME       Remote to use for fetch/push. Default: rad
  -h, --help          Show this help text.

Notes:
  - `RAD_PASSPHRASE` should be set when `rad` needs to unlock the local key.
  - If `.gitsigners` is not tracked or ignored by the repo yet, this script adds
    it to `.git/info/exclude` locally so the hybrid setup does not dirty the checkout.
EOF
}

fail() {
  echo "${program_name}: $*" >&2
  exit 1
}

resolve_repo_root() {
  local repo_arg="${1:-}"
  tusk_resolve_checkout_root "${repo_arg}"
}

ensure_git_repo() {
  local repo_root="$1"
  git -C "${repo_root}" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "`${repo_root}` is not a Git checkout"
}

ensure_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 \
    || fail "required command `${command_name}` is not available"
}

command_path_or_missing() {
  local command_name="$1"
  command -v "${command_name}" 2>/dev/null || true
}

tool_path_or_placeholder() {
  local command_name="$1"
  local path=""

  path="$(command_path_or_missing "${command_name}")"
  if [ -n "${path}" ]; then
    printf '%s\n' "${path}"
  else
    printf '<missing>\n'
  fi
}

ensure_radicle_transport_tools() {
  ensure_command git
  ensure_command rad
  ensure_command git-remote-rad
}

current_rid() {
  local repo_root="$1"
  local remote_url=""

  remote_url="$(git -C "${repo_root}" remote get-url rad 2>/dev/null || true)"
  remote_url="${remote_url#rad://}"
  remote_url="${remote_url%%/*}"
  printf '%s\n' "${remote_url}"
}

normalize_rid() {
  local rid="${1:-}"
  rid="${rid#rad://}"
  rid="${rid#rad:}"
  printf '%s\n' "${rid}"
}

rad_profile_home() {
  printf '%s\n' "${RAD_HOME:-${HOME}/.radicle}"
}

rad_storage_repo_path() {
  local repo_root="$1"
  local rid=""

  rid="$(current_rid "${repo_root}")"
  if [ -z "${rid}" ]; then
    printf '\n'
    return
  fi

  printf '%s/storage/%s\n' "$(rad_profile_home)" "${rid}"
}

current_branch_head() {
  local repo_root="$1"
  local branch="$2"

  git -C "${repo_root}" rev-parse "${branch}" 2>/dev/null || true
}

cached_remote_branch_head() {
  local repo_root="$1"
  local remote_name="$2"
  local branch="$3"

  git -C "${repo_root}" for-each-ref --format='%(objectname)' \
    "refs/remotes/${remote_name}/${branch}" 2>/dev/null | awk 'NR==1 { print $1 }'
}

live_remote_branch_head() {
  local repo_root="$1"
  local remote_name="$2"
  local branch="$3"
  local remote_head=""

  if [ "${remote_name}" = "origin" ]; then
    remote_head="$(
      GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}" \
        git -C "${repo_root}" ls-remote "${remote_name}" "refs/heads/${branch}" 2>/dev/null \
        | awk 'NR==1 { print $1 }'
    )"
  else
    remote_head="$(
      git -C "${repo_root}" ls-remote "${remote_name}" "refs/heads/${branch}" 2>/dev/null \
        | awk 'NR==1 { print $1 }'
    )"
  fi

  printf '%s\n' "${remote_head}"
}

remote_branch_head() {
  local repo_root="$1"
  local remote_name="$2"
  local branch="$3"
  local cached_head=""
  local live_head=""

  cached_head="$(cached_remote_branch_head "${repo_root}" "${remote_name}" "${branch}")"
  if [ -n "${cached_head}" ]; then
    printf '%s\n' "${cached_head}"
    return
  fi

  live_head="$(live_remote_branch_head "${repo_root}" "${remote_name}" "${branch}")"
  printf '%s\n' "${live_head}"
}

head_relation() {
  local repo_root="$1"
  local local_head="$2"
  local remote_head="$3"

  if [ -z "${local_head}" ] || [ -z "${remote_head}" ]; then
    printf 'unknown\n'
    return
  fi

  if [ "${local_head}" = "${remote_head}" ]; then
    printf 'in_sync\n'
    return
  fi

  if git -C "${repo_root}" cat-file -e "${remote_head}^{commit}" >/dev/null 2>&1; then
    if git -C "${repo_root}" merge-base --is-ancestor "${remote_head}" "${local_head}" >/dev/null 2>&1; then
      printf 'local_ahead\n'
      return
    fi

    if git -C "${repo_root}" merge-base --is-ancestor "${local_head}" "${remote_head}" >/dev/null 2>&1; then
      printf 'local_behind\n'
      return
    fi

    printf 'diverged\n'
    return
  fi

  printf 'different\n'
}

ensure_local_gitsigners_ignore() {
  local repo_root="$1"
  local exclude_file="${repo_root}/.git/info/exclude"

  if grep -qxF '.gitsigners' "${repo_root}/.gitignore" 2>/dev/null; then
    return
  fi

  if [ -f "${exclude_file}" ] && grep -qxF '.gitsigners' "${exclude_file}" 2>/dev/null; then
    return
  fi

  printf '\n.gitsigners\n' >> "${exclude_file}"
}

restore_git_upstream() {
  local repo_root="$1"
  local branch="$2"
  local preserved_remote="$3"
  local preserved_merge="$4"

  if [ -n "${preserved_remote}" ]; then
    git -C "${repo_root}" config "branch.${branch}.remote" "${preserved_remote}"
  else
    git -C "${repo_root}" config --unset-all "branch.${branch}.remote" >/dev/null 2>&1 || true
  fi

  if [ -n "${preserved_merge}" ]; then
    git -C "${repo_root}" config "branch.${branch}.merge" "${preserved_merge}"
  else
    git -C "${repo_root}" config --unset-all "branch.${branch}.merge" >/dev/null 2>&1 || true
  fi
}

show_status() {
  local repo_root="$1"
  local branch="$2"
  local branch_remote=""
  local branch_merge=""
  local origin_url=""
  local rad_url=""
  local rad_pushurl=""
  local rid=""
  local local_head=""
  local origin_head=""
  local rad_head=""
  local origin_relation=""
  local rad_relation=""
  local git_path=""
  local rad_path=""
  local git_remote_rad_path=""
  local transport_ready="false"
  local rad_storage_repo=""
  local rad_storage_ready="false"

  branch_remote="$(git -C "${repo_root}" config --get "branch.${branch}.remote" || true)"
  branch_merge="$(git -C "${repo_root}" config --get "branch.${branch}.merge" || true)"
  origin_url="$(git -C "${repo_root}" remote get-url origin 2>/dev/null || true)"
  rad_url="$(git -C "${repo_root}" remote get-url rad 2>/dev/null || true)"
  rad_pushurl="$(git -C "${repo_root}" remote get-url --push rad 2>/dev/null || true)"
  rid="$(current_rid "${repo_root}")"
  local_head="$(current_branch_head "${repo_root}" "${branch}")"
  origin_head="$(remote_branch_head "${repo_root}" origin "${branch}")"
  rad_head="$(remote_branch_head "${repo_root}" rad "${branch}")"
  origin_relation="$(head_relation "${repo_root}" "${local_head}" "${origin_head}")"
  rad_relation="$(head_relation "${repo_root}" "${local_head}" "${rad_head}")"
  git_path="$(tool_path_or_placeholder git)"
  rad_path="$(tool_path_or_placeholder rad)"
  git_remote_rad_path="$(tool_path_or_placeholder git-remote-rad)"
  rad_storage_repo="$(rad_storage_repo_path "${repo_root}")"
  if [ "${git_path}" != "<missing>" ] && [ "${rad_path}" != "<missing>" ] && [ "${git_remote_rad_path}" != "<missing>" ]; then
    transport_ready="true"
  fi
  if [ -n "${rad_storage_repo}" ] && [ -d "${rad_storage_repo}" ]; then
    rad_storage_ready="true"
  fi

  cat <<EOF
repo_root=${repo_root}
branch=${branch}
local_head=${local_head:-<unknown>}
git_path=${git_path}
rad_path=${rad_path}
git_remote_rad_path=${git_remote_rad_path}
rad_transport_ready=${transport_ready}
rad_storage_repo=${rad_storage_repo:-<missing>}
rad_storage_ready=${rad_storage_ready}
branch_remote=${branch_remote:-<unset>}
branch_merge=${branch_merge:-<unset>}
origin_url=${origin_url:-<missing>}
origin_head=${origin_head:-<unknown>}
origin_relation=${origin_relation}
rad_url=${rad_url:-<missing>}
rad_pushurl=${rad_pushurl:-<missing>}
rid=${rid:-<missing>}
rad_head=${rad_head:-<unknown>}
rad_relation=${rad_relation}
rad_profile_home=${HOME}/.radicle
node_status=$(rad node status >/dev/null 2>&1 && printf running || printf stopped)
EOF
}

ensure_tools() {
  local repo_root="$1"
  local rad_storage_repo=""

  ensure_git_repo "${repo_root}"
  ensure_radicle_transport_tools
  rad_storage_repo="$(rad_storage_repo_path "${repo_root}")"

  cat <<EOF
repo_root=${repo_root}
git_path=$(command -v git)
rad_path=$(command -v rad)
git_remote_rad_path=$(command -v git-remote-rad)
rad_profile_home=$(rad_profile_home)
rad_storage_repo=${rad_storage_repo:-<missing>}
rad_storage_ready=$([ -n "${rad_storage_repo}" ] && [ -d "${rad_storage_repo}" ] && printf true || printf false)
node_status=$(rad node status >/dev/null 2>&1 && printf running || printf stopped)
EOF
}

ensure_radicle_storage_ready() {
  local repo_root="$1"
  local remote_name="$2"
  local action_name="$3"
  local storage_path=""
  local rid=""

  if [ "${remote_name}" != "rad" ]; then
    return
  fi

  rid="$(current_rid "${repo_root}")"
  [ -n "${rid}" ] || fail "remote \`${remote_name}\` is not configured for ${repo_root}"

  storage_path="$(rad_storage_repo_path "${repo_root}")"
  if [ ! -d "${storage_path}" ]; then
    fail "local Radicle storage for \`rad:${rid}\` is missing at \`${storage_path}\`; attach or clone the repo before using \`${program_name} ${action_name}\`"
  fi
}

fetch_remote() {
  local repo_root="$1"
  local branch="$2"
  local remote_name="$3"

  ensure_git_repo "${repo_root}"
  ensure_radicle_transport_tools
  ensure_radicle_storage_ready "${repo_root}" "${remote_name}" "fetch"

  git -C "${repo_root}" fetch "${remote_name}"
  show_status "${repo_root}" "${branch}"
}

push_remote() {
  local repo_root="$1"
  local branch="$2"
  local remote_name="$3"

  ensure_git_repo "${repo_root}"
  ensure_radicle_transport_tools
  ensure_radicle_storage_ready "${repo_root}" "${remote_name}" "push"
  current_branch_head "${repo_root}" "${branch}" >/dev/null
  git -C "${repo_root}" rev-parse "${branch}^{commit}" >/dev/null 2>&1 \
    || fail "branch `${branch}` does not resolve to a local commit"

  git -C "${repo_root}" push "${remote_name}" "${branch}:refs/heads/${branch}"
  show_status "${repo_root}" "${branch}"
}

init_existing() {
  local repo_root="$1"
  local branch="$2"
  local rid="$3"
  local normalized_rid=""
  local preserved_remote=""
  local preserved_merge=""

  [ -n "${rid}" ] || fail "`init-existing` requires --rid"
  normalized_rid="$(normalize_rid "${rid}")"

  ensure_command git
  ensure_command rad
  ensure_git_repo "${repo_root}"

  preserved_remote="$(git -C "${repo_root}" config --get "branch.${branch}.remote" || true)"
  preserved_merge="$(git -C "${repo_root}" config --get "branch.${branch}.merge" || true)"

  if [ "$(current_rid "${repo_root}")" != "${normalized_rid}" ]; then
    (
      cd "${repo_root}"
      rad init --existing "rad:${normalized_rid}" --setup-signing --no-confirm .
    )
  fi

  restore_git_upstream "${repo_root}" "${branch}" "${preserved_remote}" "${preserved_merge}"
  ensure_local_gitsigners_ignore "${repo_root}"
}

main() {
  local repo_arg=""
  local branch="${default_branch}"
  local rid=""
  local remote_name="rad"
  local command_name="${1:-}"
  local repo_root=""

  if [ "$#" -eq 0 ]; then
    usage
    exit 1
  fi

  case "${command_name}" in
    -h|--help)
      usage
      exit 0
      ;;
  esac
  shift

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        [ "$#" -ge 2 ] || fail "`--repo` requires a path"
        repo_arg="$2"
        shift 2
        ;;
      --rid)
        [ "$#" -ge 2 ] || fail "`--rid` requires a value"
        rid="$2"
        shift 2
        ;;
      --branch)
        [ "$#" -ge 2 ] || fail "`--branch` requires a value"
        branch="$2"
        shift 2
        ;;
      --remote)
        [ "$#" -ge 2 ] || fail "`--remote` requires a value"
        remote_name="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
  done

  repo_root="$(resolve_repo_root "${repo_arg}")"

  case "${command_name}" in
    status)
      show_status "${repo_root}" "${branch}"
      ;;
    ensure-tools)
      ensure_tools "${repo_root}"
      ;;
    fetch)
      fetch_remote "${repo_root}" "${branch}" "${remote_name}"
      ;;
    push)
      push_remote "${repo_root}" "${branch}" "${remote_name}"
      ;;
    init-existing)
      init_existing "${repo_root}" "${branch}" "${rid}"
      show_status "${repo_root}" "${branch}"
      ;;
    *)
      fail "unknown command: ${command_name}"
      ;;
  esac
}

main "$@"
